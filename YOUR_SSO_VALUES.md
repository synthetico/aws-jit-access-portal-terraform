# Your SSO Configuration Summary

## ✅ Configuration Complete

Your SSO values have been configured in `terraform.tfvars`:

```hcl
# IAM Identity Center Instance
sso_instance_arn = "arn:aws:sso:::instance/ssoins-72238ae6eda141e6"

# Permission Set (what users will get)
permission_set_arn = "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718"

# Target AWS Account (where they'll get access)
target_account_id = "935595346298"
```

---

## 🔄 How It Works (Simple Flow)

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User Requests Access                                         │
│    "I need database admin access for 4 hours"                   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Manager Approves via Email Link                             │
│    "Yes, grant john.doe@company.com access"                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Grant Access Lambda Executes                                │
│                                                                  │
│    sso_admin.create_account_assignment(                         │
│      InstanceArn="arn:aws:sso:::instance/ssoins-72238ae6...",  │
│      TargetId="935595346298",                                   │
│      PermissionSetArn="arn:aws:sso:::permissionSet/.../ps-...",│
│      PrincipalType="USER",                                      │
│      PrincipalId="john.doe@company.com"                         │
│    )                                                             │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Result                                                        │
│    ✅ User john.doe@company.com now has:                        │
│       • Permission Set ps-7223e05fa041f718                      │
│       • In AWS Account 935595346298                             │
│       • For 4 hours (then auto-revoked)                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📍 Where Your Values Are Used

### In Terraform (`main.tf`, `iam.tf`, `lambda.tf`)

**Lambda Environment Variables:**
```hcl
resource "aws_lambda_function" "grant_access" {
  environment {
    variables = {
      SSO_INSTANCE_ARN   = var.sso_instance_arn    # ssoins-72238ae6...
      PERMISSION_SET_ARN = var.permission_set_arn  # ps-7223e05fa041f718
      TARGET_ACCOUNT_ID  = var.target_account_id   # 935595346298
    }
  }
}
```

**IAM Permissions:**
```hcl
data "aws_iam_policy_document" "lambda_sso" {
  statement {
    actions = [
      "sso:CreateAccountAssignment",
      "sso:DeleteAccountAssignment"
    ]
    resources = [
      var.sso_instance_arn,      # ssoins-72238ae6...
      var.permission_set_arn,    # ps-7223e05fa041f718
    ]
  }
}
```

---

### In Lambda Code (`lambda/grant_access.py`)

**Environment Variables Loaded:**
```python
SSO_INSTANCE_ARN = os.environ['SSO_INSTANCE_ARN']
# → "arn:aws:sso:::instance/ssoins-72238ae6eda141e6"

PERMISSION_SET_ARN = os.environ['PERMISSION_SET_ARN']
# → "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718"

TARGET_ACCOUNT_ID = os.environ['TARGET_ACCOUNT_ID']
# → "935595346298"
```

**API Call:**
```python
response = sso_admin.create_account_assignment(
    InstanceArn=SSO_INSTANCE_ARN,
    TargetId=TARGET_ACCOUNT_ID,
    TargetType='AWS_ACCOUNT',
    PermissionSetArn=PERMISSION_SET_ARN,
    PrincipalType='USER',
    PrincipalId=user_id  # e.g., "john.doe@company.com"
)
```

---

## 🎯 What This Means

### Your Instance ARN (`ssoins-72238ae6eda141e6`)
- This is **your IAM Identity Center instance**
- It's like a "home base" for all SSO operations
- Every API call to grant/revoke access needs this

### Your Permission Set (`ps-7223e05fa041f718`)
- This defines **WHAT permissions** users get
- Could be AdministratorAccess, PowerUserAccess, ReadOnly, etc.
- To see what this permission set includes:
  ```bash
  aws sso-admin describe-permission-set \
    --instance-arn arn:aws:sso:::instance/ssoins-72238ae6eda141e6 \
    --permission-set-arn arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718
  ```

### Your Target Account (`935595346298`)
- This is **WHERE** users get access
- The actual AWS account (could be prod, dev, security, etc.)
- When access is granted, users can log in to this account

---

## 🚀 Next Steps

### 1. Deploy the Infrastructure
```bash
terraform init
terraform apply
```

### 2. After Deployment

**Test the SSO integration:**
```bash
# Invoke the grant access Lambda directly
aws lambda invoke \
  --function-name tdemy-jit-portal-grant-access \
  --payload '{
    "user_id": "test.user@company.com",
    "duration_hours": 1,
    "justification": "Testing SSO integration"
  }' \
  response.json

cat response.json
```

**Verify in IAM Identity Center:**
1. Open AWS Console → IAM Identity Center
2. Go to **AWS accounts** → Select account `935595346298`
3. Click **Assigned users and groups**
4. You should see the test user with your permission set

### 3. Verify Automatic Revocation

After the duration expires (e.g., 1 hour), check again:
- The assignment should be automatically removed
- EventBridge Scheduler triggered the revoke Lambda
- Session status in DynamoDB should be "REVOKED"

---

## 📚 Additional Resources

- **[SSO_CONFIGURATION_GUIDE.md](./SSO_CONFIGURATION_GUIDE.md)** - Deep dive into how SSO works
- **[DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md)** - Full deployment walkthrough
- **[README.md](./README.md)** - Complete project documentation
- **[.infracodebase/sso-integration-flow.json](./canvas)** - Visual diagram (open in Canvas tab)

---

## ❓ Questions?

**"Can I use multiple permission sets?"**
- Not with this single deployment
- But you can deploy multiple stacks with different permission sets
- Or modify the code to accept permission set ARN as a request parameter

**"Can I target multiple AWS accounts?"**
- Not with this single deployment
- But you can deploy multiple stacks, one per target account
- Or modify the code to accept target account as a request parameter

**"What permissions does ps-7223e05fa041f718 include?"**
- Run the `describe-permission-set` command above to see details
- Check in AWS Console → IAM Identity Center → Permission sets

---

## ✅ Configuration Checklist

- [x] SSO Instance ARN configured
- [x] Permission Set ARN configured
- [x] Target Account ID configured
- [x] Values saved in `terraform.tfvars`
- [ ] Run `terraform init`
- [ ] Run `terraform apply`
- [ ] Test grant access
- [ ] Verify in IAM Identity Center
- [ ] Test automatic revocation
