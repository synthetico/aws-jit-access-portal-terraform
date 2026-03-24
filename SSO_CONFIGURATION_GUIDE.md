# IAM Identity Center (SSO) Configuration Guide

## Your SSO Configuration Values

You've configured the following SSO values in `terraform.tfvars`:

```hcl
sso_instance_arn   = "arn:aws:sso:::instance/ssoins-72238ae6eda141e6"
permission_set_arn = "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718"
target_account_id  = "935595346298"
```

## What Each Value Does

### 1. **SSO Instance ARN** (`sso_instance_arn`)
```
arn:aws:sso:::instance/ssoins-72238ae6eda141e6
```

**What it is:** The unique identifier for your IAM Identity Center (formerly AWS SSO) instance.

**Where it's used:**
- In the `grant_access.py` Lambda function when calling `sso_admin.create_account_assignment()`
- Required for ALL IAM Identity Center API operations
- Passed as an environment variable to Lambda functions

**How Terraform uses it:**
```hcl
resource "aws_lambda_function" "grant_access" {
  environment {
    variables = {
      SSO_INSTANCE_ARN = var.sso_instance_arn  # <-- Your instance ARN
    }
  }
}
```

**In the Lambda code (grant_access.py line 141-148):**
```python
response = sso_admin.create_account_assignment(
    InstanceArn=SSO_INSTANCE_ARN,  # <-- Your ssoins-72238ae6eda141e6
    TargetId=TARGET_ACCOUNT_ID,
    TargetType='AWS_ACCOUNT',
    PermissionSetArn=PERMISSION_SET_ARN,
    PrincipalType='USER',
    PrincipalId=user_id
)
```

---

### 2. **Permission Set ARN** (`permission_set_arn`)
```
arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718
```

**What it is:** The specific set of permissions that will be granted to users when they request access.

**Common permission sets:**
- AdministratorAccess (full AWS admin rights)
- PowerUserAccess (admin without IAM)
- ReadOnlyAccess (view-only)
- DatabaseAdministrator (RDS/DynamoDB admin)
- Custom permission sets you've created

**Where it's used:**
- Defines WHAT permissions users get when access is granted
- Stored in DynamoDB to track which permissions were assigned
- Passed to IAM Identity Center API when creating account assignments

**How it flows through the system:**
```
User requests access
   ↓
terraform.tfvars (permission_set_arn)
   ↓
Lambda environment variable (PERMISSION_SET_ARN)
   ↓
sso_admin.create_account_assignment(PermissionSetArn=...)
   ↓
User gets permissions defined in ps-7223e05fa041f718
```

---

### 3. **Target Account ID** (`target_account_id`)
```
935595346298
```

**What it is:** The 12-digit AWS account ID where users will receive temporary access.

**Where it's used:**
- Specifies WHERE the permissions are granted (which AWS account)
- Passed to IAM Identity Center API when creating assignments
- Stored in DynamoDB for audit tracking

**Example scenario:**
```
Organization Structure:
├── Management Account (111111111111)
├── Dev Account (222222222222)
├── Prod Account (935595346298) ← YOUR TARGET ACCOUNT
└── Security Account (444444444444)

When a user requests JIT access:
→ They get permissions in account 935595346298
→ NOT in the management or other accounts
```

---

## How the Grant Access Flow Works

Here's the complete flow showing how your SSO values are used:

```
1. User logs in to Cognito (with MFA)
   ↓
2. User makes API request: POST /request-access
   {
     "user_id": "john.doe@company.com",
     "duration_hours": 4,
     "justification": "Fix production database issue"
   }
   ↓
3. Step Functions approval workflow runs
   ↓
4. After manager approval, grant_access Lambda is invoked
   ↓
5. Lambda calls IAM Identity Center API:

   sso_admin.create_account_assignment(
     InstanceArn="arn:aws:sso:::instance/ssoins-72238ae6eda141e6",
     TargetId="935595346298",
     TargetType="AWS_ACCOUNT",
     PermissionSetArn="arn:aws:sso:::permissionSet/.../ps-7223e05fa041f718",
     PrincipalType="USER",
     PrincipalId="john.doe@company.com"
   )
   ↓
6. IAM Identity Center creates the assignment
   ↓
7. User john.doe@company.com now has the permissions from ps-7223e05fa041f718
   in AWS account 935595346298 for the next 4 hours
   ↓
8. EventBridge Scheduler triggers automatic revocation after 4 hours
```

---

## Environment Variables Passed to Lambda Functions

Your SSO values become Lambda environment variables via Terraform:

### Grant Access Lambda
```bash
SSO_INSTANCE_ARN   = "arn:aws:sso:::instance/ssoins-72238ae6eda141e6"
PERMISSION_SET_ARN = "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718"
TARGET_ACCOUNT_ID  = "935595346298"
MAX_DURATION_HOURS = 12
```

### Revoke Access Lambda
```bash
SSO_INSTANCE_ARN   = "arn:aws:sso:::instance/ssoins-72238ae6eda141e6"
PERMISSION_SET_ARN = "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718"
TARGET_ACCOUNT_ID  = "935595346298"
```

---

## How to Find These Values (Reference)

If you need to find these values in the AWS Console:

### SSO Instance ARN:
1. Go to **IAM Identity Center** console
2. Click **Settings** in left sidebar
3. Copy the **Instance ARN**

### Permission Set ARN:
1. Go to **IAM Identity Center** console
2. Click **Permission sets** in left sidebar
3. Click on your desired permission set
4. Copy the **Permission set ARN**

### Target Account ID:
1. Go to **AWS Organizations** console (or any console)
2. Click account dropdown in top-right
3. The 12-digit number is your account ID

---

## What Happens During Deployment

When you run `terraform apply`:

1. **Terraform reads** `terraform.tfvars`
2. **Creates Lambda functions** with your SSO values as environment variables
3. **Grants IAM permissions** to Lambda execution roles:
   - `sso:CreateAccountAssignment` (grant access)
   - `sso:DeleteAccountAssignment` (revoke access)
   - `sso:DescribeAccountAssignmentCreationStatus`
   - `sso:DescribeAccountAssignmentDeletionStatus`

4. **Lambda functions** can now call IAM Identity Center APIs using your instance

---

## Security & Permissions

### Required IAM Permissions

Your Lambda execution roles need these permissions for your SSO instance:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sso:CreateAccountAssignment",
        "sso:DeleteAccountAssignment",
        "sso:DescribeAccountAssignmentCreationStatus",
        "sso:DescribeAccountAssignmentDeletionStatus"
      ],
      "Resource": [
        "arn:aws:sso:::instance/ssoins-72238ae6eda141e6",
        "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718",
        "arn:aws:sso:*:935595346298:account/*"
      ]
    }
  ]
}
```

**These permissions are automatically created by Terraform in `iam.tf`.**

---

## Testing Your Configuration

After deployment, you can test if the SSO integration works:

### 1. **Check Lambda Environment Variables**
```bash
aws lambda get-function-configuration \
  --function-name tdemy-jit-portal-grant-access \
  --query 'Environment.Variables'
```

Expected output:
```json
{
  "SSO_INSTANCE_ARN": "arn:aws:sso:::instance/ssoins-72238ae6eda141e6",
  "PERMISSION_SET_ARN": "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718",
  "TARGET_ACCOUNT_ID": "935595346298"
}
```

### 2. **Manual Test Lambda Invocation**
```bash
aws lambda invoke \
  --function-name tdemy-jit-portal-grant-access \
  --payload '{"user_id":"test.user@company.com","duration_hours":1,"justification":"Test"}' \
  response.json

cat response.json
```

### 3. **Verify in IAM Identity Center**
1. Go to IAM Identity Center console
2. Click **AWS accounts** → Select account `935595346298`
3. Click **Assigned users and groups**
4. You should see your test user with permission set `ps-7223e05fa041f718`

---

## Common Issues & Troubleshooting

### Error: "AccessDeniedException"
**Cause:** Lambda doesn't have permission to call SSO APIs
**Fix:** Check that IAM role has `sso:CreateAccountAssignment` permission

### Error: "ResourceNotFoundException"
**Cause:** SSO instance ARN or permission set ARN is incorrect
**Fix:** Verify ARNs in IAM Identity Center console match `terraform.tfvars`

### Error: "ConflictException"
**Cause:** User already has this permission set assigned
**Fix:** This is expected behavior - the portal tracks active assignments

### Error: "User not found"
**Cause:** User ID doesn't exist in your IAM Identity Center directory
**Fix:** Ensure `user_id` matches email/username in your identity source

---

## Next Steps

✅ **You've configured:** SSO instance, permission set, and target account
✅ **Ready to deploy:** Run `terraform init && terraform apply`
✅ **After deployment:** Test the grant/revoke flow

**To deploy:**
```bash
cd /tmp/workspaces/e8733245-2aac-4230-a800-484a0ebb4fb3/code
terraform init
terraform apply
```

**To test:**
See the "Testing Your Configuration" section above.
