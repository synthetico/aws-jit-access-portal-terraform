# Download Complete Package and Deploy from Scratch

## Package Location

Your complete deployment package is ready at:

```
/tmp/jit-access-portal-package-20260325-061905.tar.gz   (40KB - Linux/Mac)
/tmp/jit-access-portal-package-20260325-061905.zip      (64KB - Windows)
```

## What's Included

The package contains everything you need:

- ✅ All Terraform configuration files (main.tf, variables.tf, outputs.tf, etc.)
- ✅ All Lambda function source code (6 Python files)
- ✅ Frontend web interface (HTML)
- ✅ Deployment scripts (deploy-frontend.sh, test-portal.sh)
- ✅ Complete documentation (7 guides)
- ✅ Your SSO configuration (terraform.tfvars with your values)
- ✅ Quick start script

## Download Options

### Option 1: Download from Terminal

If you have access to the workspace terminal:

```bash
# Copy to your local machine (Linux/Mac)
cp /tmp/jit-access-portal-package-20260325-061905.tar.gz ~/Downloads/

# Or for Windows
cp /tmp/jit-access-portal-package-20260325-061905.zip ~/Downloads/
```

### Option 2: Direct File Access

The files are located at:
- `/tmp/jit-access-portal-package-20260325-061905.tar.gz`
- `/tmp/jit-access-portal-package-20260325-061905.zip`

You can download these directly from your file browser or terminal.

---

## Deploy from Scratch - Step by Step

### Step 1: Extract the Package

**Linux/Mac:**
```bash
cd ~/Downloads
tar -xzf jit-access-portal-package-20260325-061905.tar.gz
cd jit-access-portal-package-20260325-061905
```

**Windows:**
```powershell
# Extract the ZIP file
# Then open PowerShell in the extracted folder
cd jit-access-portal-package-20260325-061905
```

### Step 2: Verify Your Configuration

Check that `terraform.tfvars` has your correct SSO values:

```bash
cat terraform.tfvars
```

Should show:
```hcl
sso_instance_arn = "arn:aws:sso:::instance/ssoins-72238ae6eda141e6"
permission_set_arn = "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718"
target_account_id = "935595346298"
```

If these values are wrong, edit `terraform.tfvars` before proceeding.

### Step 3: Clean Up Old Resources (Optional)

**If you want a completely fresh start**, delete existing AWS resources first:

#### Option A: Quick Cleanup Script

```bash
# You can create a cleanup script or manually delete via AWS Console
# See docs/DEPLOY_FROM_SCRATCH.md for details
```

#### Option B: Manual Cleanup via AWS Console

1. Lambda Functions - Delete all `tdemy-jit-portal-*`
2. IAM Roles - Delete all `tdemy-jit-portal-*`
3. DynamoDB Tables - Delete `tdemy-jit-portal-sessions` and `tdemy-jit-portal-approval-requests`
4. S3 Bucket - Delete `tdemy-jit-portal-frontend-935595346298`
5. API Gateway - Delete `tdemy-jit-portal-api`
6. Cognito User Pool - Delete `tdemy-jit-portal-user-pool`
7. Step Functions - Delete `tdemy-jit-portal-approval-workflow`
8. CloudWatch Log Groups - Delete all `/aws/lambda/tdemy-jit-portal-*`
9. SQS Queues - Delete DLQ queues
10. SNS Topic - Delete approval notifications topic

### Step 4: Clean Local Terraform State

```bash
# Remove any old state files
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Step 5: Configure AWS CLI

Make sure AWS CLI is configured with credentials:

```bash
aws configure

# Or verify existing configuration
aws sts get-caller-identity
```

### Step 6: Initialize Terraform

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/aws v5.100.0...
- Installing hashicorp/archive v2.7.1...

Terraform has been successfully initialized!
```

### Step 7: Validate Configuration

```bash
terraform validate
```

Expected: `Success! The configuration is valid.`

### Step 8: Review Deployment Plan

```bash
terraform plan
```

This shows all resources that will be created (~50+ resources).

### Step 9: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

**Duration:** 3-5 minutes

**Resources created:**
- 6 Lambda functions
- 2 DynamoDB tables
- 1 API Gateway
- 1 Cognito User Pool
- 1 Step Functions state machine
- 1 S3 bucket
- 1 SNS topic
- IAM roles and policies
- CloudWatch Log Groups
- SQS queues

### Step 10: Save Deployment Outputs

```bash
# View all outputs
terraform output

# Save specific outputs
echo "API URL: $(terraform output -raw api_gateway_url)"
echo "Frontend URL: $(terraform output -raw website_url)"
echo "User Pool ID: $(terraform output -raw cognito_user_pool_id)"
echo "Client ID: $(terraform output -raw cognito_client_id)"
```

### Step 11: Deploy Frontend

```bash
chmod +x deploy-frontend.sh
./deploy-frontend.sh
```

This uploads the web interface to S3 and configures public access.

### Step 12: Create Test User

```bash
# Create user
aws cognito-idp admin-create-user \
  --region us-east-1 \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username test@example.com \
  --user-attributes \
    Name=email,Value=test@example.com \
    Name=email_verified,Value=true \
    Name=custom:manager_email,Value=manager@example.com

# Set permanent password
aws cognito-idp admin-set-user-password \
  --region us-east-1 \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username test@example.com \
  --password 'TestPassword123!' \
  --permanent
```

### Step 13: Test the Portal

**Via Web Interface:**

```bash
# Get the URL
terraform output website_url

# Visit in browser, then:
# 1. Click "Get Token from Cognito Hosted UI"
# 2. Log in with test@example.com / TestPassword123!
# 3. Submit an access request
```

**Via CLI Script:**

```bash
chmod +x test-portal.sh
./test-portal.sh
```

**Via curl:**

```bash
# Get token from Cognito Hosted UI first, then:
TOKEN="your_token_here"

curl -X POST $(terraform output -raw api_gateway_url)/request-access \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"duration_hours": 4, "justification": "Testing"}'
```

---

## Verification Checklist

After deployment, verify:

- [ ] `terraform apply` completed successfully
- [ ] All outputs display correctly
- [ ] Frontend is accessible at S3 URL
- [ ] Cognito Hosted UI loads
- [ ] Test user can log in
- [ ] Access request returns execution ARN
- [ ] Step Functions execution appears in AWS Console
- [ ] Approval request in DynamoDB
- [ ] SNS subscription confirmation received

---

## Documentation Included

All guides are in the `docs/` folder:

1. **DEPLOY_FROM_SCRATCH.md** - Complete deployment guide
2. **TESTING_GUIDE.md** - Comprehensive testing instructions
3. **QUICK_TEST_NOW.md** - 5-minute quick start
4. **SSO_CONFIGURATION_GUIDE.md** - Deep dive on SSO integration
5. **YOUR_SSO_VALUES.md** - Your specific configuration
6. **FIXING_STATE_ISSUE.md** - Troubleshooting Terraform state
7. **GET_URLS_MANUAL.md** - Get URLs from AWS Console

---

## Quick Reference

### Get Deployment Info

```bash
# All outputs
terraform output

# Specific values
terraform output -raw api_gateway_url
terraform output -raw website_url
terraform output -raw cognito_user_pool_id
terraform output -raw cognito_client_id
```

### Create Users

```bash
aws cognito-idp admin-create-user \
  --region us-east-1 \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username USER@example.com \
  --user-attributes Name=email,Value=USER@example.com
```

### View Logs

```bash
# Request access Lambda
aws logs tail /aws/lambda/tdemy-jit-portal-request-access --region us-east-1 --follow

# Grant access Lambda
aws logs tail /aws/lambda/tdemy-jit-portal-grant-access --region us-east-1 --follow

# Step Functions
aws logs tail /aws/vendedlogs/states/tdemy-jit-portal-approval-workflow --region us-east-1 --follow
```

### Check Active Sessions

```bash
aws dynamodb scan \
  --region us-east-1 \
  --table-name tdemy-jit-portal-sessions
```

### List Step Functions Executions

```bash
aws stepfunctions list-executions \
  --region us-east-1 \
  --state-machine-arn $(terraform output -raw step_functions_arn)
```

---

## Troubleshooting

### Issue: "Resource already exists"

**Solution:** Clean up old resources first (see Step 3 above)

### Issue: Terraform state locked

**Solution:**
```bash
terraform force-unlock <LOCK_ID>
```

### Issue: Lambda deployment fails

**Solution:** Re-run `terraform apply` (code is auto-packaged)

### Issue: Frontend shows network error

**Solution:**
1. Verify frontend was deployed: `./deploy-frontend.sh`
2. Check API URL is correct in index.html
3. Verify CORS settings in API Gateway

---

## Next Steps After Successful Deployment

1. ✅ Test the full approval workflow
2. 📧 Confirm SNS subscription (check email)
3. 👥 Add production users
4. 🔐 Review IAM permissions
5. 📊 Set up CloudWatch alarms
6. 🔄 Configure automated backups
7. 📝 Document your specific use cases

---

## Support

For issues:
1. Check CloudWatch Logs
2. Review Terraform output
3. Verify SSO configuration
4. Check AWS service quotas
5. See documentation in `docs/` folder

---

## Package Contents Summary

```
jit-access-portal-package-20260325-061905/
├── Terraform Files (7 files)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   ├── approval-workflow.tf
│   ├── approval-lambdas.tf
│   └── cognito.tf
├── Lambda Functions (6 files)
│   ├── grant_access.py
│   ├── revoke_access.py
│   ├── request_access.py
│   ├── send_approval_email.py
│   ├── wait_for_approval.py
│   └── process_approval.py
├── Frontend (1 file)
│   └── index.html
├── Scripts (4 files)
│   ├── deploy-frontend.sh
│   ├── test-portal.sh
│   ├── get-portal-urls.sh
│   └── import-existing-resources.sh
└── Documentation (8 files)
    ├── README.md
    ├── PACKAGE_README.md
    └── docs/
        ├── DEPLOY_FROM_SCRATCH.md
        ├── TESTING_GUIDE.md
        ├── QUICK_TEST_NOW.md
        ├── SSO_CONFIGURATION_GUIDE.md
        ├── YOUR_SSO_VALUES.md
        ├── FIXING_STATE_ISSUE.md
        └── GET_URLS_MANUAL.md
```

---

## Ready to Deploy!

```bash
# Extract
tar -xzf jit-access-portal-package-20260325-061905.tar.gz
cd jit-access-portal-package-20260325-061905

# Deploy
terraform init
terraform apply

# Test
./deploy-frontend.sh
terraform output website_url
```

Good luck! 🚀
