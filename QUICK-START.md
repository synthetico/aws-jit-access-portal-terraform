# Quick Start Guide - JIT Access Portal

This is a condensed guide for deploying the Zero-Trust JIT Access Portal with Cognito authentication, MFA, and approval workflow.

## What You Need

Before starting, gather these three values:

| Item | How to Get It | Example |
|------|---------------|---------|
| **SSO Instance ARN** | `aws sso-admin list-instances` | `arn:aws:sso:::instance/ssoins-abc123` |
| **Permission Set ARN** | `aws sso-admin list-permission-sets --instance-arn <INSTANCE>` | `arn:aws:sso:::permissionSet/ssoins-abc123/ps-def456` |
| **Account ID** | `aws sts get-caller-identity --query Account --output text` | `123456789012` |

### Get SSO Instance ARN

```bash
aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text
```

### Get Permission Set ARN (AdministratorAccess)

```bash
# Replace <INSTANCE_ARN> with your SSO Instance ARN
INSTANCE_ARN="arn:aws:sso:::instance/ssoins-YOUR_ID"

# List all permission sets
aws sso-admin list-permission-sets --instance-arn $INSTANCE_ARN

# Describe each to find AdministratorAccess
aws sso-admin describe-permission-set \
  --instance-arn $INSTANCE_ARN \
  --permission-set-arn <PERMISSION_SET_ARN> \
  --query 'PermissionSet.Name'
```

### Get Account ID

```bash
aws sts get-caller-identity --query Account --output text
```

---

## Deploy in 5 Steps

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Fill in the three values you gathered above:

```hcl
sso_instance_arn       = "arn:aws:sso:::instance/ssoins-YOUR_ID"
target_account_id      = "123456789012"
permission_set_arn     = "arn:aws:sso:::permissionSet/ssoins-.../ps-..."
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

Type `yes` when prompted. Deployment takes ~3-5 minutes.

### 3. Create Users

```bash
# Get User Pool ID
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)

# Create requester (employee)
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username employee@example.com \
  --user-attributes \
    Name=email,Value=employee@example.com \
    Name=name,Value="John Employee" \
    Name=custom:manager_email,Value=manager@example.com \
  --message-action SUPPRESS

aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username employee@example.com \
  --password 'TempPassword123!' \
  --permanent

# Create manager (approver)
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

**Important:** The `custom:manager_email` attribute is **required** for the approval workflow.

### 4. Subscribe Manager to SNS

```bash
# Get SNS Topic ARN
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)

# Subscribe manager email
aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol email \
  --notification-endpoint manager@example.com
```

**The manager must click the confirmation link in their email.**

### 5. Test the Portal

```bash
# Get website URL
terraform output website_url
```

1. **Open the URL** in your browser
2. **Sign in** as employee@example.com
3. **Set up MFA** (first login only - scan QR code with authenticator app)
4. **Request access:**
   - User ID: Your SSO user email/ID
   - Duration: 4 hours
   - Justification: "Testing JIT access"
5. **Approve as manager:**
   - Manager receives email with approve/deny links
   - Click "APPROVE"
   - Sign in as manager@example.com
   - Access is granted automatically

---

## What This Deploys

### Authentication & Security
- ✅ **Cognito User Pool** with MFA (TOTP required)
- ✅ **Advanced Security Mode** for anomaly detection
- ✅ **Password Policy** (12+ chars, symbols, numbers)

### Approval Workflow
- ✅ **Step Functions** state machine for approval orchestration
- ✅ **SNS Email Notifications** to managers
- ✅ **DynamoDB Table** for tracking approvals

### Access Management
- ✅ **IAM Identity Center Integration** for SSO assignments
- ✅ **EventBridge Scheduler** for automatic revocation
- ✅ **DynamoDB TTL** for automatic session cleanup

### API & Frontend
- ✅ **API Gateway** with JWT authorizer (Cognito)
- ✅ **S3 Static Website** for the portal UI
- ✅ **Lambda Functions** (6 total):
  - `request-access` - Entry point, starts approval workflow
  - `send-approval-email` - Sends email to manager
  - `wait-for-approval` - Stores Step Functions task token
  - `process-approval` - Handles approve/deny decisions
  - `grant-access` - Creates SSO assignment (called after approval)
  - `revoke-access` - Deletes SSO assignment when session expires

### Monitoring & Audit
- ✅ **CloudWatch Logs** (30-day retention)
- ✅ **Dead Letter Queues** for error handling
- ✅ **Step Functions Logging** for workflow visibility

---

## Key Features

| Feature | Implementation |
|---------|---------------|
| **MFA** | Cognito enforces TOTP for all users |
| **Approval** | Step Functions workflow with SNS email |
| **Auto-Revocation** | EventBridge Scheduler triggers revoke Lambda |
| **Audit Trail** | CloudWatch Logs for all operations |
| **Least-Privilege** | IAM policies scoped to specific resources |

---

## Important Outputs

```bash
# View all outputs
terraform output

# Key outputs:
terraform output website_url              # Portal URL
terraform output api_gateway_url          # API base URL
terraform output cognito_user_pool_id     # For creating users
terraform output cognito_client_id        # For frontend auth
terraform output sns_topic_arn            # For email subscriptions
terraform output step_functions_arn       # Workflow state machine
```

---

## Monitoring

### View Logs

```bash
# Request access Lambda (entry point)
aws logs tail /aws/lambda/tdemy-jit-portal-request-access --follow

# Approval workflow
aws logs tail /aws/vendedlogs/states/tdemy-jit-portal-approval-workflow --follow

# Grant/revoke Lambda
aws logs tail /aws/lambda/tdemy-jit-portal-grant-access --follow
aws logs tail /aws/lambda/tdemy-jit-portal-revoke-access --follow
```

### Check Active Sessions

```bash
# View active JIT sessions
aws dynamodb scan \
  --table-name tdemy-jit-portal-sessions \
  --filter-expression "#status = :status" \
  --expression-attribute-names '{"#status":"Status"}' \
  --expression-attribute-values '{":status":{"S":"ACTIVE"}}' \
  --query 'Items[*].[RequestID.S, UserID.S, GrantedAt.S, ExpiresAt.S]' \
  --output table

# View approval requests
aws dynamodb scan \
  --table-name tdemy-jit-portal-approval-requests \
  --query 'Items[*].[ApprovalID.S, RequesterEmail.S, Status.S, RequestedAt.S]' \
  --output table
```

---

## Troubleshooting

### No approval email received?

```bash
# Check SNS subscription status
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)
aws sns list-subscriptions-by-topic --topic-arn $SNS_TOPIC_ARN

# Status should be "Confirmed" (not "PendingConfirmation")
# If pending, manager needs to click confirmation link in email
```

### "Manager email not set" error?

```bash
# Update user's manager email attribute
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
aws cognito-idp admin-update-user-attributes \
  --user-pool-id $USER_POOL_ID \
  --username employee@example.com \
  --user-attributes Name=custom:manager_email,Value=manager@example.com
```

### MFA not working?

```bash
# Check user MFA status
aws cognito-idp admin-get-user \
  --user-pool-id $USER_POOL_ID \
  --username employee@example.com \
  --query 'UserMFASettingList'

# Should return: ["SOFTWARE_TOKEN_MFA"]
```

---

## Cleanup

```bash
# Delete any active schedules first
aws scheduler list-schedules --name-prefix tdemy-jit-portal-revoke | \
  jq -r '.Schedules[].Name' | \
  xargs -I {} aws scheduler delete-schedule --name {}

# Destroy all resources
terraform destroy
```

---

## Next Steps

For detailed information, see:
- **[DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md)** - Complete deployment walkthrough
- **[README.md](./README.md)** - Full project documentation

For production hardening:
- Set up CloudFront for HTTPS
- Enable CloudTrail for compliance
- Add CloudWatch alarms
- Configure custom domain
- Integrate with Slack for notifications
