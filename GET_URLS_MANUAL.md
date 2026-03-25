# How to Get Your JIT Portal URLs (Manual Method)

Since AWS CLI credentials aren't configured, here's how to get all the URLs directly from the AWS Console:

## 1. API Gateway URL (Backend API)

**Steps:**
1. Open [AWS Console](https://console.aws.amazon.com)
2. Go to **API Gateway** service
3. Look for **tdemy-jit-portal-api**
4. Click on it
5. In the left sidebar, click **Stages**
6. Click on **$default** stage
7. Look for **Invoke URL** at the top

**Your API URL will look like:**
```
https://abc123xyz.execute-api.us-east-1.amazonaws.com
```

**API Endpoints:**
- `POST /request-access` - Request JIT access
- `POST /grant-access` - Grant access (called by Step Functions)
- `POST /revoke-access` - Revoke access
- `POST /process-approval` - Process manager approval/denial

---

## 2. S3 Frontend URL (Web Portal)

**Steps:**
1. Open [AWS Console](https://console.aws.amazon.com)
2. Go to **S3** service
3. Look for bucket: **tdemy-jit-portal-frontend-935595346298**
4. Click on it
5. Go to **Properties** tab
6. Scroll down to **Static website hosting**
7. Copy the **Bucket website endpoint**

**Your frontend URL will look like:**
```
http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com
```

**Note:** The frontend files haven't been uploaded yet, so you'll need to build and deploy them separately.

---

## 3. Cognito User Pool Details

**Steps:**
1. Open [AWS Console](https://console.aws.amazon.com)
2. Go to **Amazon Cognito** service
3. Click on **User pools**
4. Look for **tdemy-jit-portal-user-pool**
5. Click on it

**Get User Pool ID:**
- At the top of the page, you'll see "User pool ID" (e.g., `us-east-1_abc123xyz`)

**Get App Client ID:**
1. Click on **App integration** tab
2. Scroll to **App clients and analytics**
3. Click on your app client
4. Copy the **Client ID**

**Get Cognito Domain:**
1. In the **App integration** tab
2. Look for **Domain** section
3. Your domain will be: `tdemy-jit-portal-935595346298`

**Cognito Hosted UI URL:**
```
https://tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com
```

**Login URL:**
```
https://tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com/login?client_id=<YOUR_CLIENT_ID>&response_type=token&scope=openid+email+profile&redirect_uri=<YOUR_FRONTEND_URL>
```

---

## 4. Step Functions State Machine

**Steps:**
1. Open [AWS Console](https://console.aws.amazon.com)
2. Go to **Step Functions** service
3. Look for **tdemy-jit-portal-approval-workflow**
4. Click on it to see execution history

---

## 5. DynamoDB Tables

**Access Tables:**
1. Open [AWS Console](https://console.aws.amazon.com)
2. Go to **DynamoDB** service
3. Click on **Tables**

**Your tables:**
- **tdemy-jit-portal-sessions** - Active JIT sessions
- **tdemy-jit-portal-approval-requests** - Approval requests tracking

---

## 6. CloudWatch Logs

**Steps:**
1. Open [AWS Console](https://console.aws.amazon.com)
2. Go to **CloudWatch** service
3. Click on **Logs** → **Log groups**

**Your log groups:**
- `/aws/lambda/tdemy-jit-portal-grant-access`
- `/aws/lambda/tdemy-jit-portal-revoke-access`
- `/aws/lambda/tdemy-jit-portal-request-access`
- `/aws/lambda/tdemy-jit-portal-send-approval-email`
- `/aws/lambda/tdemy-jit-portal-wait-for-approval`
- `/aws/lambda/tdemy-jit-portal-process-approval`
- `/aws/vendedlogs/states/tdemy-jit-portal-approval-workflow`
- `/aws/apigateway/tdemy-jit-portal`

---

## Quick Reference Summary

Once you've gathered the information above, save it here:

```bash
# API Gateway
API_URL="https://__________.execute-api.us-east-1.amazonaws.com"

# S3 Frontend
FRONTEND_URL="http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com"

# Cognito
USER_POOL_ID="us-east-1__________"
APP_CLIENT_ID="__________________________"
COGNITO_DOMAIN="tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com"

# Step Functions
STATE_MACHINE_ARN="arn:aws:states:us-east-1:935595346298:stateMachine:tdemy-jit-portal-approval-workflow"
```

---

## Testing the Backend API

Once you have the API URL, you can test it:

### 1. Create a test user in Cognito:

Go to Cognito → User pools → tdemy-jit-portal-user-pool → Users → Create user

**User details:**
- Username: `test@example.com`
- Email: `test@example.com`
- Email verified: ✅ (check this)
- Temporary password: `TempPassword123!`

**Custom attributes:**
- `custom:manager_email`: `manager@example.com`

### 2. Get a JWT token:

Use the Cognito Hosted UI or AWS CLI to authenticate and get a JWT token.

**Via AWS Console (easier):**
1. Go to Cognito Hosted UI: `https://tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com/login`
2. Add query parameters:
   ```
   ?client_id=<YOUR_CLIENT_ID>
   &response_type=token
   &scope=openid+email+profile
   &redirect_uri=https://example.com
   ```
3. Log in with your test user
4. After login, the URL will contain `id_token=...` - copy this token

### 3. Test the API:

```bash
curl -X POST https://YOUR_API_URL/request-access \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "duration_hours": 4,
    "justification": "Testing JIT access portal"
  }'
```

**Expected response:**
```json
{
  "execution_arn": "arn:aws:states:...",
  "message": "Access request submitted. Awaiting manager approval."
}
```

### 4. Check Step Functions execution:

Go to Step Functions → tdemy-jit-portal-approval-workflow → Executions

You should see a running execution waiting for approval.

### 5. Check manager's email:

The manager should receive an email with:
- Approve link: `https://YOUR_API_URL/process-approval?token=...&decision=approve`
- Deny link: `https://YOUR_API_URL/process-approval?token=...&decision=deny`

---

## Next Steps

1. ✅ Get all URLs from AWS Console (using steps above)
2. ✅ Create a test user in Cognito
3. ✅ Test the request-access API endpoint
4. ✅ Verify Step Functions workflow triggers
5. ✅ Check that approval emails are sent
6. 🔄 Fix Terraform state (see FIXING_STATE_ISSUE.md)
7. 🚀 Deploy frontend (HTML/JS files to S3)

---

## Troubleshooting

**If API returns 401 Unauthorized:**
- Check JWT token is valid (not expired)
- Verify Cognito user pool ID in API Gateway authorizer
- Check CloudWatch Logs for API Gateway

**If Step Functions doesn't start:**
- Check CloudWatch Logs for request-access Lambda
- Verify IAM role permissions
- Check Step Functions state machine is enabled

**If approval emails aren't sent:**
- Check SNS topic exists and has email subscription
- Verify email address in SNS subscription is confirmed
- Check CloudWatch Logs for send-approval-email Lambda

**If DynamoDB errors occur:**
- Verify tables exist and are active
- Check Lambda IAM roles have DynamoDB permissions
- Look at CloudWatch Logs for specific error messages
