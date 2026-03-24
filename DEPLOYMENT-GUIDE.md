# JIT Access Portal - Complete Deployment Guide

This guide walks you through deploying the Zero-Trust JIT Access Portal with Cognito authentication, MFA, and approval workflow.

## Prerequisites

- AWS Account with administrative access
- IAM Identity Center (AWS SSO) enabled
- Terraform >= 1.5.0
- AWS CLI configured
- Git (optional, for version control)

---

## Phase 1: Gather Required Information

### Step 1.1: Get SSO Instance ARN

The SSO Instance ARN identifies your IAM Identity Center instance.

```bash
# List all SSO instances (usually just one)
aws sso-admin list-instances

# Expected output:
{
    "Instances": [
        {
            "InstanceArn": "arn:aws:sso:::instance/ssoins-1234567890abcdef",
            "IdentityStoreId": "d-1234567890"
        }
    ]
}
```

**Copy the `InstanceArn` value** - you'll need this for `terraform.tfvars`.

### Step 1.2: Get Permission Set ARN

The Permission Set ARN identifies which permission set to assign (e.g., AdministratorAccess).

```bash
# First, list all permission sets
aws sso-admin list-permission-sets \
  --instance-arn arn:aws:sso:::instance/ssoins-YOUR_INSTANCE_ID

# Expected output:
{
    "PermissionSets": [
        "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-abc123def456",
        "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-def456ghi789"
    ]
}

# Then, describe each to find AdministratorAccess
aws sso-admin describe-permission-set \
  --instance-arn arn:aws:sso:::instance/ssoins-YOUR_INSTANCE_ID \
  --permission-set-arn arn:aws:sso:::permissionSet/ssoins-YOUR_INSTANCE_ID/ps-YOUR_PERMISSION_SET_ID

# Expected output:
{
    "PermissionSet": {
        "Name": "AdministratorAccess",
        "PermissionSetArn": "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-abc123def456",
        ...
    }
}
```

**Copy the `PermissionSetArn` for AdministratorAccess** - you'll need this for `terraform.tfvars`.

### Step 1.3: Get Target Account ID

This is your 12-digit AWS account ID where permissions will be granted.

```bash
aws sts get-caller-identity --query Account --output text

# Expected output:
123456789012
```

**Copy your account ID** - you'll need this for `terraform.tfvars`.

### Summary of Required Values

At this point, you should have:

| Value | Example | Where to Use |
|-------|---------|-------------|
| SSO Instance ARN | `arn:aws:sso:::instance/ssoins-1234567890abcdef` | `sso_instance_arn` |
| Permission Set ARN | `arn:aws:sso:::permissionSet/ssoins-.../ps-...` | `permission_set_arn` |
| Account ID | `123456789012` | `target_account_id` |

---

## Phase 2: Configure Terraform Variables

### Step 2.1: Create terraform.tfvars

```bash
cd /path/to/jit-portal
cp terraform.tfvars.example terraform.tfvars
```

### Step 2.2: Edit terraform.tfvars

Open `terraform.tfvars` in your editor and fill in the values you gathered:

```hcl
# AWS region for deployment
aws_region = "us-east-1"

# IAM Identity Center (SSO) Instance ARN (from Step 1.1)
sso_instance_arn = "arn:aws:sso:::instance/ssoins-1234567890abcdef"

# Target AWS Account ID (from Step 1.3)
target_account_id = "123456789012"

# Permission Set ARN for AdministratorAccess (from Step 1.2)
permission_set_arn = "arn:aws:sso:::permissionSet/ssoins-1234567890abcdef/ps-abc123def456"

# Maximum session duration in hours (1-12)
max_session_duration_hours = 12

# Project name (used for resource naming)
project_name = "tdemy-jit-portal"

# Environment tag
environment = "production"

# API Gateway throttling settings
api_throttle_rate_limit  = 10  # requests per second
api_throttle_burst_limit = 20  # burst capacity
```

**Save the file.**

---

## Phase 3: Deploy Infrastructure

### Step 3.1: Initialize Terraform

```bash
terraform init
```

This downloads the AWS and Archive providers and prepares your workspace.

### Step 3.2: Review the Plan

```bash
terraform plan
```

Review the output to see what resources will be created:
- Cognito User Pool with MFA
- DynamoDB tables (sessions, approval requests)
- Lambda functions (6 total)
- API Gateway with Cognito authorizer
- Step Functions state machine
- S3 bucket for frontend
- IAM roles and policies
- CloudWatch log groups
- SNS topic
- SQS dead letter queues
- EventBridge Scheduler role

### Step 3.3: Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes approximately 3-5 minutes.

### Step 3.4: Capture Outputs

After deployment completes, Terraform will display important outputs:

```bash
# View all outputs
terraform output

# Save specific outputs for later use
terraform output -raw website_url > website_url.txt
terraform output -raw api_gateway_url > api_url.txt
```

**Important outputs:**
- `website_url` - The S3 static website URL
- `api_gateway_url` - The API Gateway base URL
- `cognito_user_pool_id` - For creating users
- `cognito_client_id` - For frontend authentication
- `dynamodb_table_name` - For querying sessions

---

## Phase 4: Configure Cognito Users

### Step 4.1: Create a Test User

```bash
# Get the User Pool ID from Terraform output
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)

# Create a user
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username john.doe@example.com \
  --user-attributes \
    Name=email,Value=john.doe@example.com \
    Name=name,Value="John Doe" \
    Name=custom:manager_email,Value=manager@example.com \
  --message-action SUPPRESS

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username john.doe@example.com \
  --password 'TempPassword123!' \
  --permanent
```

**Important:** The `custom:manager_email` attribute is REQUIRED for the approval workflow.

### Step 4.2: Create a Manager User

Create the manager who will approve requests:

```bash
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username manager@example.com \
  --user-attributes \
    Name=email,Value=manager@example.com \
    Name=name,Value="Jane Manager" \
    Name=custom:manager_email,Value=manager@example.com \
  --message-action SUPPRESS

aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username manager@example.com \
  --password 'ManagerPass123!' \
  --permanent
```

### Step 4.3: Configure MFA for Users

Each user must set up MFA on first login. You can do this via:

1. **AWS Console:**
   - Navigate to Cognito User Pools → Select your pool
   - Click on the user → Enable MFA → Choose TOTP
   - User will be prompted to scan QR code with authenticator app

2. **AWS CLI (for testing):**
   ```bash
   # Enable MFA for a user
   aws cognito-idp admin-set-user-mfa-preference \
     --user-pool-id $USER_POOL_ID \
     --username john.doe@example.com \
     --software-token-mfa-settings Enabled=true,PreferredMfa=true
   ```

---

## Phase 5: Configure SNS Email Subscription

The approval workflow sends emails via SNS. You need to subscribe the manager's email.

```bash
# Get the SNS Topic ARN
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)

# Subscribe manager email
aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol email \
  --notification-endpoint manager@example.com
```

**The manager will receive a confirmation email.** They must click the confirmation link to activate the subscription.

---

## Phase 6: Test the Portal

### Step 6.1: Access the Portal

```bash
# Get the website URL
terraform output website_url
```

Open the URL in your browser. You'll see the JIT Access Portal login page.

### Step 6.2: Authenticate with Cognito

1. Click "Sign In"
2. Enter credentials (e.g., `john.doe@example.com` / `TempPassword123!`)
3. If first login, you'll be prompted to set up MFA
   - Scan the QR code with Google Authenticator or Authy
   - Enter the 6-digit code to verify
4. Complete login

### Step 6.3: Request Access

1. Fill out the form:
   - **User ID:** Your SSO user ID (email or ID from Identity Center)
   - **Duration:** Select hours (1-12)
   - **Justification:** Provide business reason
2. Click "Request Access"
3. You'll receive a confirmation with an approval ID

### Step 6.4: Approve the Request (as Manager)

1. Manager receives email with approval links
2. Manager clicks "APPROVE" link
3. Manager is redirected to the portal
4. Manager authenticates with Cognito
5. Approval is processed automatically

### Step 6.5: Verify Access Granted

```bash
# Check sessions table
aws dynamodb scan \
  --table-name tdemy-jit-portal-sessions \
  --query 'Items[*].[RequestID.S, UserID.S, Status.S, GrantedAt.S]' \
  --output table

# Check approval requests table
aws dynamodb scan \
  --table-name tdemy-jit-portal-approval-requests \
  --query 'Items[*].[ApprovalID.S, RequesterEmail.S, Status.S]' \
  --output table
```

---

## Phase 7: Monitor and Troubleshoot

### CloudWatch Logs

View logs for each component:

```bash
# Request access Lambda
aws logs tail /aws/lambda/tdemy-jit-portal-request-access --follow

# Grant access Lambda
aws logs tail /aws/lambda/tdemy-jit-portal-grant-access --follow

# Approval workflow Step Functions
aws logs tail /aws/vendedlogs/states/tdemy-jit-portal-approval-workflow --follow

# API Gateway
aws logs tail /aws/apigateway/tdemy-jit-portal --follow
```

### Step Functions Executions

```bash
# List executions
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw step_functions_arn) \
  --max-results 10

# Get execution details
aws stepfunctions describe-execution \
  --execution-arn arn:aws:states:us-east-1:123456789012:execution:tdemy-jit-portal-approval-workflow:approval-abc123
```

### Common Issues

**Issue:** "Manager email not set"
- **Solution:** Update user attribute:
  ```bash
  aws cognito-idp admin-update-user-attributes \
    --user-pool-id $USER_POOL_ID \
    --username john.doe@example.com \
    --user-attributes Name=custom:manager_email,Value=manager@example.com
  ```

**Issue:** No approval email received
- **Solution:** Check SNS subscription status:
  ```bash
  aws sns list-subscriptions-by-topic --topic-arn $SNS_TOPIC_ARN
  ```
  Ensure status is "Confirmed" (not "PendingConfirmation")

**Issue:** MFA not working
- **Solution:** Ensure advanced security is enabled and user has enrolled:
  ```bash
  aws cognito-idp admin-get-user \
    --user-pool-id $USER_POOL_ID \
    --username john.doe@example.com
  ```

---

## Phase 8: Production Hardening (Optional)

### Enable CloudTrail

```bash
# Create a trail to log all API calls
aws cloudtrail create-trail \
  --name jit-portal-audit \
  --s3-bucket-name your-cloudtrail-bucket

aws cloudtrail start-logging --name jit-portal-audit
```

### Add CloudFront for HTTPS

```bash
# Create CloudFront distribution for S3 website
# (Use AWS Console or add cloudfront.tf resource)
```

### Set Up Alarms

```bash
# Create alarm for failed access grants
aws cloudwatch put-metric-alarm \
  --alarm-name jit-portal-grant-failures \
  --alarm-description "Alert on failed JIT access grants" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=tdemy-jit-portal-grant-access
```

---

## Phase 9: Cleanup (if needed)

To destroy all resources:

```bash
# Delete any pending EventBridge schedules first
aws scheduler list-schedules --name-prefix tdemy-jit-portal-revoke | \
  jq -r '.Schedules[].Name' | \
  xargs -I {} aws scheduler delete-schedule --name {}

# Destroy infrastructure
terraform destroy
```

---

## Summary

You've successfully deployed a production-grade Zero-Trust JIT Access Portal with:

✅ **Cognito Authentication** - Secure user login with email/password
✅ **MFA Enforcement** - TOTP-based multi-factor authentication required for all users
✅ **Approval Workflow** - Manager approval required via Step Functions
✅ **Email Notifications** - SNS-based approval requests
✅ **Automated Revocation** - EventBridge Scheduler removes access automatically
✅ **Audit Logging** - CloudWatch Logs for all operations
✅ **Least-Privilege IAM** - All roles scoped to minimum required permissions

## Next Steps

1. Integrate with Slack for approval notifications
2. Add approval dashboard for managers
3. Implement session extension capability
4. Set up CloudWatch dashboards
5. Enable AWS Config for compliance tracking

For questions or issues, review the CloudWatch logs or consult the README.md file.
