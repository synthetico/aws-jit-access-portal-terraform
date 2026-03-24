# Zero-Trust JIT Access Portal for AWS

A production-ready Just-In-Time (JIT) access management system for AWS using IAM Identity Center, built with Terraform.

## Architecture Overview

This solution implements a Zero-Trust JIT access portal that:
- Provides time-limited elevated permissions through IAM Identity Center
- Automatically revokes access when the session expires
- Tracks all access requests in DynamoDB with audit logs
- Follows AWS security best practices with least-privilege IAM policies

### Components

- **Frontend**: S3-hosted static website with HTML form
- **API Gateway**: HTTP API that receives access requests
- **Grant Lambda**: Python 3.12 function that creates SSO account assignments
- **Revoke Lambda**: Python 3.12 function that deletes SSO account assignments
- **DynamoDB**: Session tracking with TTL for automatic cleanup
- **EventBridge Scheduler**: Automated access revocation at session expiration
- **CloudWatch Logs**: Comprehensive logging for all components
- **SQS Dead Letter Queues**: Error handling for Lambda failures

## Prerequisites

1. **AWS Account** with IAM Identity Center enabled
2. **Terraform** >= 1.5.0
3. **AWS CLI** configured with appropriate credentials
4. **IAM Identity Center** (formerly AWS SSO) setup with:
   - At least one user
   - A permission set (e.g., AdministratorAccess)
   - The instance ARN and permission set ARN

## Required Information

Before deploying, gather the following:

### 1. SSO Instance ARN
```bash
aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text
```

### 2. Permission Set ARN
```bash
# List all permission sets
aws sso-admin list-permission-sets --instance-arn <YOUR_SSO_INSTANCE_ARN>

# Get details of a specific permission set
aws sso-admin describe-permission-set \
  --instance-arn <YOUR_SSO_INSTANCE_ARN> \
  --permission-set-arn <PERMISSION_SET_ARN>
```

### 3. Target Account ID
Your 12-digit AWS account ID where permissions will be granted.

## Deployment Instructions

### Step 1: Clone and Configure

```bash
# Navigate to the project directory
cd tdemy-jit-portal

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
nano terraform.tfvars
```

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Review the Plan

```bash
terraform plan
```

### Step 4: Deploy

```bash
terraform apply
```

Review the changes and type `yes` to confirm.

### Step 5: Access the Portal

After deployment, Terraform will output the website URL:

```bash
terraform output website_url
```

Visit this URL in your browser to access the JIT portal.

## Configuration

### terraform.tfvars

```hcl
aws_region                 = "us-east-1"
sso_instance_arn          = "arn:aws:sso:::instance/ssoins-xxxxx"
target_account_id         = "123456789012"
permission_set_arn        = "arn:aws:sso:::permissionSet/ssoins-xxxxx/ps-xxxxx"
max_session_duration_hours = 12
project_name              = "tdemy-jit-portal"
environment               = "prototype"
api_throttle_rate_limit   = 10
api_throttle_burst_limit  = 20
```

## Usage

### Requesting Access

1. Navigate to the portal URL
2. Enter your **User ID** (SSO user email or ID)
3. Select the **duration** (1-12 hours)
4. Provide a **justification** for the access request
5. Click **Request Access**

The system will:
- Grant the AdministratorAccess permission set to your user
- Store the session in DynamoDB
- Schedule automatic revocation via EventBridge Scheduler
- Return a confirmation with request ID and expiration time

### Access Revocation

Access is automatically revoked when the session expires. The revocation Lambda:
- Deletes the SSO account assignment
- Updates the session status in DynamoDB
- Cleans up the EventBridge schedule

## Security Features

### Least-Privilege IAM Policies

All Lambda functions have minimal permissions:

**Grant Lambda:**
- `sso:CreateAccountAssignment` (scoped to specific instance and permission set)
- `dynamodb:PutItem`, `GetItem`, `UpdateItem`, `Query` (scoped to sessions table)
- `scheduler:CreateSchedule` (scoped to revocation schedules)
- `identitystore:DescribeUser`, `ListUsers`

**Revoke Lambda:**
- `sso:DeleteAccountAssignment` (scoped to specific instance and permission set)
- `dynamodb:GetItem`, `DeleteItem`, `UpdateItem` (scoped to sessions table)
- `scheduler:DeleteSchedule` (scoped to revocation schedules)

### Data Protection

- **Encryption at Rest**: DynamoDB server-side encryption enabled
- **Point-in-Time Recovery**: Enabled for DynamoDB table
- **TTL**: Automatic cleanup of expired sessions
- **CloudWatch Logs**: 30-day retention for audit trails

### API Security

- **Throttling**: Rate limiting (10 req/s, burst 20)
- **CORS**: Configured for frontend origin
- **Request Validation**: Input validation in Lambda
- **Error Handling**: Dead letter queues for failed invocations

## Monitoring and Logging

### CloudWatch Log Groups

- `/aws/lambda/tdemy-jit-portal-grant-access`
- `/aws/lambda/tdemy-jit-portal-revoke-access`
- `/aws/apigateway/tdemy-jit-portal`

### DynamoDB Table Structure

**Primary Key**: `RequestID` (String)

**Attributes**:
- `UserID` (String) - GSI hash key
- `DurationHours` (Number)
- `Justification` (String)
- `GrantedAt` (ISO 8601 timestamp)
- `ExpiresAt` (ISO 8601 timestamp)
- `ExpirationTime` (Unix timestamp) - TTL attribute
- `Status` (String) - ACTIVE, REVOKED, FAILED
- `AssignmentID` (String) - SSO assignment request ID
- `PermissionSetArn` (String)
- `TargetAccountId` (String)

### Viewing Logs

```bash
# Grant Lambda logs
aws logs tail /aws/lambda/tdemy-jit-portal-grant-access --follow

# Revoke Lambda logs
aws logs tail /aws/lambda/tdemy-jit-portal-revoke-access --follow

# API Gateway logs
aws logs tail /aws/apigateway/tdemy-jit-portal --follow
```

## Troubleshooting

### Common Issues

**1. "User not found" error**
- Verify the User ID matches the Identity Center user
- Check if the user exists: `aws identitystore list-users --identity-store-id <ID>`

**2. "Assignment already exists"**
- The user already has this permission set assigned
- Manually remove the assignment or wait for automatic revocation

**3. Throttling errors**
- SSO Admin API has low rate limits
- The Lambda includes retry logic with exponential backoff
- Check CloudWatch Logs for retry attempts

**4. EventBridge Scheduler not triggering**
- Verify the scheduler role has `lambda:InvokeFunction` permission
- Check EventBridge Scheduler console for schedule status
- Review CloudWatch Logs for scheduler execution

### Manual Cleanup

```bash
# List active schedules
aws scheduler list-schedules --name-prefix tdemy-jit-portal-revoke

# Delete a specific schedule
aws scheduler delete-schedule --name tdemy-jit-portal-revoke-<REQUEST_ID>

# Query DynamoDB for active sessions
aws dynamodb query \
  --table-name tdemy-jit-portal-sessions \
  --index-name UserIDIndex \
  --key-condition-expression "UserID = :uid" \
  --expression-attribute-values '{":uid":{"S":"user@example.com"}}'
```

## Cost Estimation

Estimated monthly costs (us-east-1, light usage):

- **Lambda**: ~$0.20 (1M requests, 256MB, 1s avg duration)
- **API Gateway**: ~$3.50 (1M requests)
- **DynamoDB**: ~$0.25 (on-demand, light usage)
- **EventBridge Scheduler**: ~$1.00 (per schedule execution)
- **S3**: ~$0.50 (static hosting, minimal traffic)
- **CloudWatch Logs**: ~$0.50 (30-day retention)

**Total**: ~$6/month for light usage

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

Note: Manually delete any EventBridge Schedules if they exist, as Terraform may not track them.

## Production Recommendations

1. **Add Authentication**: Integrate with Cognito or OIDC provider
2. **Implement Approval Workflow**: Require manager approval for high-privilege requests
3. **Add Slack/Email Notifications**: Alert on access grants and revocations
4. **Enable AWS CloudTrail**: Comprehensive audit logging
5. **Add CloudFront**: Serve S3 website via HTTPS with custom domain
6. **Implement IP Allowlisting**: Restrict API access to corporate networks
7. **Add MFA Requirement**: Enforce MFA for access requests
8. **Set Up Alarms**: CloudWatch alarms for failed grants/revocations
9. **Enable AWS Config**: Track configuration changes
10. **Implement Session Extension**: Allow users to extend sessions before expiration

## References

- [AWS Prescriptive Guidance - Dynamic Permission Sets](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/manage-aws-permission-sets-dynamically-by-using-terraform.html)
- [IAM Identity Center Best Practices](https://blog.resiz.es/iam-identity-center/)
- [EventBridge Scheduler with Lambda](https://docs.aws.amazon.com/lambda/latest/dg/with-eventbridge-scheduler.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This project is provided as-is for educational and prototype purposes.
