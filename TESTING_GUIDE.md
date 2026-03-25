# Complete Testing Guide for JIT Access Portal

## Your Portal URLs

```
API Gateway:  https://j0362geq43.execute-api.us-east-1.amazonaws.com
User Pool ID: us-east-1_2OOoBRhNj
Client ID:    7ekm0frce3ldhhl0dg9p3ird0r
S3 Frontend:  http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com
Cognito UI:   https://tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com
```

---

## Testing Method 1: Via Web Frontend (Easiest)

### Step 1: Deploy the Frontend

```bash
./deploy-frontend.sh
```

This will:
- Upload index.html to S3
- Configure S3 for static website hosting
- Set public read permissions

### Step 2: Access the Portal

1. Open: [http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com](http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com)

2. Click "Get Token from Cognito Hosted UI"

3. Log in with your Cognito user credentials

4. You'll be redirected back with the token automatically filled in

5. Fill in:
   - **Duration**: How long you need access (1-12 hours)
   - **Justification**: Business reason for access

6. Click "Request Access"

7. You should see: "Request submitted! Manager will receive approval email."

---

## Testing Method 2: Via CLI Script (Most Complete)

### Prerequisites

1. **Set permanent password for your Cognito user:**

```bash
aws cognito-idp admin-set-user-password \
  --region us-east-1 \
  --user-pool-id us-east-1_2OOoBRhNj \
  --username <YOUR_EMAIL> \
  --password 'YourSecurePassword123!' \
  --permanent
```

2. **Setup MFA (if required):**

The user pool enforces MFA, so you'll need to:
- Use Cognito Hosted UI to set up MFA on first login
- Or disable MFA requirement temporarily for testing

**Disable MFA temporarily:**
```bash
aws cognito-idp update-user-pool \
  --region us-east-1 \
  --user-pool-id us-east-1_2OOoBRhNj \
  --mfa-configuration OPTIONAL
```

### Run the Test Script

```bash
./test-portal.sh
```

This script will:
1. Authenticate with Cognito
2. Get JWT tokens
3. Submit access request to API
4. Show Step Functions execution status
5. Provide manual approval links

---

## Testing Method 3: Manual curl Commands

### Step 1: Get JWT Token

**Option A: Via Cognito Hosted UI**

1. Open this URL in browser (replace with your details):
```
https://tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com/login?client_id=7ekm0frce3ldhhl0dg9p3ird0r&response_type=token&scope=openid+email+profile&redirect_uri=https://example.com
```

2. Log in with your credentials

3. After login, you'll be redirected to:
```
https://example.com/#id_token=eyJraW...&access_token=eyJra...
```

4. Copy the `id_token` value (the long string after `id_token=` and before `&`)

**Option B: Via AWS CLI** (requires USER_PASSWORD_AUTH enabled)

This won't work by default because the client is configured for Cognito Hosted UI flow.

### Step 2: Test the API

```bash
# Set your token
TOKEN="<YOUR_ID_TOKEN_FROM_STEP_1>"

# Request access
curl -X POST https://j0362geq43.execute-api.us-east-1.amazonaws.com/request-access \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "duration_hours": 4,
    "justification": "Testing JIT access portal"
  }'
```

**Expected Response:**
```json
{
  "execution_arn": "arn:aws:states:us-east-1:935595346298:execution:tdemy-jit-portal-approval-workflow:abc123",
  "start_date": "2024-01-15T10:30:00.000Z",
  "message": "Access request submitted for approval. Awaiting manager decision."
}
```

---

## Verifying the Workflow

### 1. Check Step Functions Execution

```bash
aws stepfunctions list-executions \
  --region us-east-1 \
  --state-machine-arn "arn:aws:states:us-east-1:935595346298:stateMachine:tdemy-jit-portal-approval-workflow" \
  --max-results 5
```

### 2. Check DynamoDB for Approval Request

```bash
aws dynamodb scan \
  --region us-east-1 \
  --table-name tdemy-jit-portal-approval-requests \
  --limit 5
```

### 3. Check CloudWatch Logs

```bash
# Request Access Lambda logs
aws logs tail /aws/lambda/tdemy-jit-portal-request-access \
  --region us-east-1 \
  --follow

# Step Functions logs
aws logs tail /aws/vendedlogs/states/tdemy-jit-portal-approval-workflow \
  --region us-east-1 \
  --follow
```

### 4. Manually Approve/Deny (for testing)

Get the task token from DynamoDB:

```bash
# Get latest approval request
aws dynamodb scan \
  --region us-east-1 \
  --table-name tdemy-jit-portal-approval-requests \
  --limit 1 \
  --query 'Items[0].TaskToken.S' \
  --output text
```

Then approve:

```bash
TASK_TOKEN="<TOKEN_FROM_ABOVE>"

curl -X POST "https://j0362geq43.execute-api.us-east-1.amazonaws.com/process-approval?token=${TASK_TOKEN}&decision=approve"
```

Or deny:

```bash
curl -X POST "https://j0362geq43.execute-api.us-east-1.amazonaws.com/process-approval?token=${TASK_TOKEN}&decision=deny"
```

---

## Checking if Access Was Granted

### 1. Check DynamoDB Sessions Table

```bash
aws dynamodb scan \
  --region us-east-1 \
  --table-name tdemy-jit-portal-sessions
```

You should see active sessions with:
- Status: ACTIVE
- User ID
- Permission Set ARN
- Expiration time

### 2. Check IAM Identity Center Assignments

```bash
aws sso-admin list-account-assignments \
  --region us-east-1 \
  --instance-arn "arn:aws:sso:::instance/ssoins-72238ae6eda141e6" \
  --account-id "935595346298" \
  --permission-set-arn "arn:aws:sso:::permissionSet/ssoins-72238ae6eda141e6/ps-7223e05fa041f718"
```

### 3. Check CloudWatch Logs for Grant Lambda

```bash
aws logs tail /aws/lambda/tdemy-jit-portal-grant-access \
  --region us-east-1 \
  --follow
```

---

## Common Issues & Solutions

### Issue 1: "Network Error" in Frontend

**Cause:** CORS issue or API Gateway not configured
**Solution:**
1. Check API Gateway CORS settings
2. Verify API URL is correct
3. Check browser console for specific error

### Issue 2: "401 Unauthorized"

**Cause:** Invalid or expired JWT token
**Solution:**
1. Get a fresh token from Cognito Hosted UI
2. Verify token is the `id_token` not `access_token`
3. Check token hasn't expired (valid for 1 hour)

### Issue 3: "MFA Required" but Can't Set It Up

**Solution:**
```bash
# Disable MFA for testing
aws cognito-idp update-user-pool \
  --region us-east-1 \
  --user-pool-id us-east-1_2OOoBRhNj \
  --mfa-configuration OPTIONAL
```

### Issue 4: No Approval Email Received

**Cause:** SNS subscription not confirmed
**Solution:**
1. Check SNS topic subscriptions:
   ```bash
   aws sns list-subscriptions --region us-east-1
   ```
2. Find the pending confirmation and click the link
3. Or manually approve using the curl command above

### Issue 5: "User doesn't exist in Identity Center"

**Cause:** The Cognito user email doesn't match any user in IAM Identity Center
**Solution:**
1. Create matching user in IAM Identity Center with same email
2. Or update the Lambda to use Cognito user ID as principal

---

## Complete Test Flow

Here's the full end-to-end test:

1. **Create User:**
   ```bash
   aws cognito-idp admin-create-user \
     --region us-east-1 \
     --user-pool-id us-east-1_2OOoBRhNj \
     --username test@example.com \
     --user-attributes \
       Name=email,Value=test@example.com \
       Name=email_verified,Value=true \
       Name=custom:manager_email,Value=manager@example.com
   ```

2. **Set Password:**
   ```bash
   aws cognito-idp admin-set-user-password \
     --region us-east-1 \
     --user-pool-id us-east-1_2OOoBRhNj \
     --username test@example.com \
     --password 'TestPass123!' \
     --permanent
   ```

3. **Deploy Frontend:**
   ```bash
   ./deploy-frontend.sh
   ```

4. **Access Portal:**
   - Visit: http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com
   - Click "Get Token from Cognito Hosted UI"
   - Log in with test@example.com / TestPass123!
   - Submit access request

5. **Approve Request:**
   - Check manager@example.com's email
   - Click approve link
   - OR manually approve via curl (see above)

6. **Verify Access Granted:**
   ```bash
   aws dynamodb scan \
     --region us-east-1 \
     --table-name tdemy-jit-portal-sessions
   ```

7. **Wait for Auto-Revocation:**
   - After the duration expires, access should be automatically revoked
   - Check session status changes to "REVOKED"

---

## Success Criteria

You know it's working when:

1. ✅ Frontend loads without errors
2. ✅ User can log in via Cognito Hosted UI
3. ✅ Access request returns execution ARN
4. ✅ Step Functions execution shows in AWS Console
5. ✅ Approval request appears in DynamoDB
6. ✅ Manager receives email with approve/deny links
7. ✅ After approval, session appears in DynamoDB with "ACTIVE" status
8. ✅ IAM Identity Center shows account assignment
9. ✅ After expiration, session status changes to "REVOKED"
10. ✅ IAM Identity Center assignment is removed

---

## Next Steps After Successful Test

1. **Add More Users:**
   - Create users in Cognito
   - Ensure they exist in IAM Identity Center
   - Test with different duration values

2. **Test Denial Flow:**
   - Submit request
   - Click "Deny" link in email
   - Verify execution stops without granting access

3. **Test Auto-Revocation:**
   - Request 1-hour access
   - Approve it
   - Wait 1 hour
   - Verify it's automatically revoked

4. **Monitor Logs:**
   - Set up CloudWatch alarms
   - Monitor for errors
   - Track request volume

5. **Production Readiness:**
   - Enable MFA enforcement
   - Add CloudFront for HTTPS frontend
   - Configure custom domain
   - Set up backup and disaster recovery
