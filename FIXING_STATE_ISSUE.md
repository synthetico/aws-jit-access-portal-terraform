# Fixing Terraform State Issue

## Problem

You ran `terraform apply` and resources were created in AWS, but then you got errors saying resources already exist. This means:

1. ✅ **Resources ARE created in AWS** (good news!)
2. ❌ **Terraform state is out of sync** (needs fixing)

## Solution Options

### Option 1: Destroy and Recreate (Cleanest - RECOMMENDED)

This will delete everything and start fresh with proper state tracking:

```bash
# Delete all resources manually or via AWS Console, then:
terraform apply
```

**Manual deletion steps:**
1. Go to AWS Console → CloudFormation (if used) OR manually delete:
   - Lambda functions (tdemy-jit-portal-*)
   - IAM roles (tdemy-jit-portal-*)
   - DynamoDB tables (tdemy-jit-portal-*)
   - S3 buckets (tdemy-jit-portal-frontend-*)
   - API Gateway (tdemy-jit-portal-api)
   - Cognito User Pool
   - Step Functions state machine
   - CloudWatch Log Groups

2. After deletion:
   ```bash
   terraform apply
   ```

---

### Option 2: Import Existing Resources (Faster)

Import the existing resources into Terraform state without recreating them:

```bash
# Make the script executable
chmod +x import-existing-resources.sh

# Run the import script
./import-existing-resources.sh

# Verify and apply any remaining changes
terraform plan
terraform apply
```

This script will import all existing resources into Terraform state.

---

### Option 3: Quick Fix - Get URLs Now, Fix State Later

If you just want to use the portal immediately:

```bash
# Make the script executable
chmod +x get-portal-urls.sh

# Get all the URLs and configuration info
./get-portal-urls.sh
```

This will show you:
- API Gateway URL
- S3 Website URL
- Cognito User Pool details
- Step Functions ARN

Then you can fix the Terraform state later when convenient.

---

## Getting Your Portal URL (Quickest Method)

Since you need the URL now, here's the fastest way:

### Via AWS Console:

1. **API Gateway URL:**
   - Go to AWS Console → API Gateway
   - Click on "tdemy-jit-portal-api"
   - Look for "Invoke URL" (something like: `https://abc123xyz.execute-api.us-east-1.amazonaws.com`)

2. **S3 Frontend URL:**
   - Go to AWS Console → S3
   - Click on bucket "tdemy-jit-portal-frontend-935595346298"
   - Go to "Properties" tab → Scroll to "Static website hosting"
   - The URL will be shown (something like: `http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com`)

3. **Cognito Hosted UI:**
   - Go to AWS Console → Cognito
   - Click on "tdemy-jit-portal-user-pool"
   - Go to "App integration" tab
   - Look for "Cognito domain" (something like: `https://tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com`)

---

## Recommended Approach

**For now (immediate use):**
1. Get URLs from AWS Console (steps above)
2. Test the portal
3. Create users and try the workflow

**Later (clean up):**
Choose Option 1 (destroy and recreate) or Option 2 (import) to fix Terraform state properly.

---

## Why This Happened

The most common causes:
1. **Multiple `terraform apply` runs** - First run created resources, second run tried to create them again
2. **Lost state file** - The `terraform.tfstate` file was deleted or not saved
3. **Different working directory** - Running Terraform from a different location

To prevent this in the future:
- Use **remote state backend** (S3 + DynamoDB locking)
- Always commit `terraform.tfstate` to version control (if using local state)
- Use `terraform plan` before `terraform apply`

---

## Next Steps After Getting URLs

1. **Create a test user:**
   ```bash
   aws cognito-idp admin-create-user \
     --region us-east-1 \
     --user-pool-id <USER_POOL_ID> \
     --username test@example.com \
     --user-attributes \
       Name=email,Value=test@example.com \
       Name=email_verified,Value=true \
       Name=custom:manager_email,Value=manager@example.com \
     --temporary-password TempPassword123!
   ```

2. **Set permanent password:**
   ```bash
   aws cognito-idp admin-set-user-password \
     --region us-east-1 \
     --user-pool-id <USER_POOL_ID> \
     --username test@example.com \
     --password YourSecurePassword123! \
     --permanent
   ```

3. **Enable MFA for user:**
   ```bash
   aws cognito-idp admin-set-user-mfa-preference \
     --region us-east-1 \
     --user-pool-id <USER_POOL_ID> \
     --username test@example.com \
     --software-token-mfa-settings Enabled=true,PreferredMfa=true
   ```

4. **Test the portal:**
   - Visit the S3 website URL
   - Log in with your credentials
   - Set up MFA (scan QR code with authenticator app)
   - Request JIT access
   - Check manager's email for approval link

---

## Support

If you encounter issues:
1. Check CloudWatch Logs for Lambda errors
2. Check API Gateway logs
3. Verify IAM permissions
4. Check Step Functions execution history
