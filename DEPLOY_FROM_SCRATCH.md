# Deploy JIT Access Portal from Scratch

This guide will help you deploy the complete JIT Access Portal infrastructure from a fresh start.

## Prerequisites

1. **AWS Account** with IAM Identity Center enabled
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.5.0 installed
4. **Your SSO Details:**
   - SSO Instance ARN
   - Permission Set ARN
   - Target Account ID

## Step 1: Clean Up Any Existing Resources (Optional)

If you want to completely start fresh, delete existing resources:

### Option A: Via AWS Console

1. **Lambda Functions** - Delete all `tdemy-jit-portal-*` functions
2. **IAM Roles** - Delete all `tdemy-jit-portal-*` roles
3. **DynamoDB Tables** - Delete `tdemy-jit-portal-sessions` and `tdemy-jit-portal-approval-requests`
4. **S3 Bucket** - Delete `tdemy-jit-portal-frontend-935595346298`
5. **API Gateway** - Delete `tdemy-jit-portal-api`
6. **Cognito User Pool** - Delete `tdemy-jit-portal-user-pool`
7. **Step Functions** - Delete `tdemy-jit-portal-approval-workflow`
8. **CloudWatch Log Groups** - Delete all `/aws/lambda/tdemy-jit-portal-*`
9. **SQS Queues** - Delete `tdemy-jit-portal-grant-dlq` and `tdemy-jit-portal-revoke-dlq`
10. **SNS Topic** - Delete `tdemy-jit-portal-approval-notifications`

### Option B: Via Script (Coming Soon)

We can create a cleanup script if needed.

## Step 2: Verify terraform.tfvars

Check your `terraform.tfvars` file has the correct values:

```bash
cat terraform.tfvars
```

Should show:
```hcl
aws_region = "us-east-1"
sso_instance_arn = "arn:aws:sso:::instance/ssoins-72238ae6eda141e6"
target_account_id = "935595346298"
permission_set_arn = "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718"
max_session_duration_hours = 12
project_name = "tdemy-jit-portal"
environment = "prototype"
api_throttle_rate_limit = 10
api_throttle_burst_limit = 20
```

## Step 3: Clean Terraform State

Remove any existing Terraform state files:

```bash
rm -f terraform.tfstate*
rm -rf .terraform/
```

## Step 4: Initialize Terraform

```bash
terraform init
```

This will:
- Download required providers (AWS, Archive)
- Initialize the backend
- Prepare the working directory

## Step 5: Validate Configuration

```bash
terraform validate
```

You should see: `Success! The configuration is valid.`

## Step 6: Plan the Deployment

Review what will be created:

```bash
terraform plan
```

This will show all resources that will be created (~50+ resources).

## Step 7: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

**Expected duration:** 3-5 minutes

**What gets created:**
- 6 Lambda functions (grant, revoke, request, send-email, wait, process)
- 2 DynamoDB tables (sessions, approval-requests)
- 1 API Gateway (HTTP API)
- 1 Cognito User Pool with domain
- 1 Step Functions state machine
- 1 S3 bucket (for frontend)
- 1 SNS topic (for approval emails)
- 2 SQS queues (dead letter queues)
- Multiple IAM roles and policies
- Multiple CloudWatch Log Groups

## Step 8: Get Deployment Outputs

After successful deployment, save these values:

```bash
terraform output
```

Or get specific outputs:

```bash
echo "API Gateway URL:"
terraform output -raw api_gateway_url

echo "User Pool ID:"
terraform output -raw cognito_user_pool_id

echo "App Client ID:"
terraform output -raw cognito_app_client_id

echo "S3 Website URL:"
terraform output -raw s3_website_url
```

## Step 9: Subscribe to SNS Topic

You'll receive a confirmation email for the SNS topic. **Click the confirmation link** to start receiving approval emails.

```bash
# Check SNS subscriptions
aws sns list-subscriptions --region us-east-1
```

## Step 10: Deploy Frontend

```bash
chmod +x deploy-frontend.sh
./deploy-frontend.sh
```

This uploads the HTML frontend to S3 and configures website hosting.

## Step 11: Create Test User

```bash
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

## Step 12: Test the Portal

Visit the frontend URL:
```bash
terraform output s3_website_url
```

Or test via curl:
```bash
./test-portal.sh
```

## Verification Checklist

After deployment, verify:

- [ ] API Gateway exists and has endpoints
- [ ] Cognito User Pool exists with domain
- [ ] Lambda functions are deployed
- [ ] DynamoDB tables are created
- [ ] Step Functions state machine exists
- [ ] S3 bucket exists with frontend files
- [ ] SNS topic subscription is confirmed
- [ ] Test user can log in
- [ ] Access request workflow completes
- [ ] Manager receives approval email

## Troubleshooting Fresh Deployment

### Issue: "Resource already exists"

**Cause:** Previous resources weren't fully cleaned up

**Solution:**
1. Go to AWS Console
2. Manually delete the conflicting resource
3. Run `terraform apply` again

### Issue: "Terraform state is locked"

**Cause:** Previous terraform process didn't complete

**Solution:**
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Issue: Lambda deployment fails

**Cause:** Lambda function code not packaged

**Solution:**
```bash
# Lambda code is auto-packaged by Terraform using archive_file
# Just re-run: terraform apply
```

### Issue: Cognito domain already exists

**Cause:** Domain from previous deployment still exists

**Solution:**
1. Go to Cognito → User pools → Old pool → App integration → Domain
2. Delete the domain
3. Or change `project_name` in terraform.tfvars to something unique

## Post-Deployment Configuration

### 1. Configure Email for SNS

The manager email in the user's `custom:manager_email` attribute must be subscribed to SNS.

Add more manager emails:
```bash
aws sns subscribe \
  --region us-east-1 \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --protocol email \
  --notification-endpoint another-manager@example.com
```

### 2. Optional: Disable MFA for Testing

```bash
aws cognito-idp update-user-pool \
  --region us-east-1 \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --mfa-configuration OPTIONAL
```

### 3. Optional: Add CloudFront for HTTPS

The S3 website is HTTP only. For HTTPS, add CloudFront:

```hcl
# Add to main.tf
resource "aws_cloudfront_distribution" "frontend" {
  # CloudFront configuration here
}
```

## Files Included in Your Package

```
.
├── main.tf                          # Core infrastructure
├── approval-workflow.tf             # Step Functions state machine
├── approval-lambdas.tf              # Approval Lambda functions
├── cognito.tf                       # Cognito User Pool
├── variables.tf                     # Input variables
├── outputs.tf                       # Output values
├── terraform.tfvars                 # Your configuration values
├── lambda/
│   ├── grant_access.py             # Grant access Lambda
│   ├── revoke_access.py            # Revoke access Lambda
│   ├── request_access.py           # Request access Lambda
│   ├── send_approval_email.py      # Send email Lambda
│   ├── wait_for_approval.py        # Wait for approval Lambda
│   └── process_approval.py         # Process decision Lambda
├── frontend/
│   └── index.html                  # Web portal UI
├── deploy-frontend.sh              # Deploy frontend script
├── test-portal.sh                  # Test automation script
├── DEPLOY_FROM_SCRATCH.md          # This file
├── TESTING_GUIDE.md                # Complete testing guide
├── QUICK_TEST_NOW.md               # Quick start guide
└── README.md                       # Project documentation
```

## Expected Outputs After Deployment

After successful `terraform apply`, you'll see:

```
Outputs:

api_gateway_url = "https://abc123.execute-api.us-east-1.amazonaws.com"
cognito_app_client_id = "abc123xyz456"
cognito_domain = "tdemy-jit-portal-935595346298"
cognito_user_pool_id = "us-east-1_ABC123XYZ"
s3_bucket_name = "tdemy-jit-portal-frontend-935595346298"
s3_website_url = "http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com"
sns_topic_arn = "arn:aws:sns:us-east-1:935595346298:tdemy-jit-portal-approval-notifications"
state_machine_arn = "arn:aws:states:us-east-1:935595346298:stateMachine:tdemy-jit-portal-approval-workflow"
```

## Cost Estimate

Free tier eligible resources:
- Lambda: First 1M requests/month free
- API Gateway: First 1M requests/month free
- DynamoDB: 25GB storage free
- CloudWatch Logs: 5GB ingestion free
- SNS: First 1,000 emails free

**Estimated monthly cost (beyond free tier):** $5-10 for light usage

## Next Steps

1. ✅ Complete fresh deployment
2. ✅ Test the workflow end-to-end
3. ✅ Add production users
4. 📝 Document your specific use cases
5. 🔒 Configure additional security controls
6. 📊 Set up monitoring and alerting
7. 🔄 Configure backup and disaster recovery

## Support

If you encounter issues:
1. Check CloudWatch Logs for errors
2. Review Terraform plan output
3. Verify IAM permissions
4. Ensure SSO values are correct
5. Check AWS service quotas

---

**Ready to deploy?**

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

Good luck! 🚀
