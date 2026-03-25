# Quick Test - Get Started in 5 Minutes

## Your Setup

```
API:      https://j0362geq43.execute-api.us-east-1.amazonaws.com
Frontend: http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com
Cognito:  https://tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com
```

---

## Option 1: Test via Web (Easiest - 2 minutes)

### Step 1: Deploy Frontend

```bash
chmod +x deploy-frontend.sh
./deploy-frontend.sh
```

### Step 2: Set Your User's Password

```bash
aws cognito-idp admin-set-user-password \
  --region us-east-1 \
  --user-pool-id us-east-1_2OOoBRhNj \
  --username YOUR_EMAIL_HERE \
  --password 'YourPassword123!' \
  --permanent
```

### Step 3: Visit Portal & Test

1. Open: [http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com](http://tdemy-jit-portal-frontend-935595346298.s3-website-us-east-1.amazonaws.com)
2. Click "Get Token from Cognito Hosted UI"
3. Login with your email/password
4. Submit access request
5. Done!

---

## Option 2: Test via curl (3 minutes)

### Step 1: Get Token via Browser

Open this URL (copy and paste into browser):
```
https://tdemy-jit-portal-935595346298.auth.us-east-1.amazoncognito.com/login?client_id=7ekm0frce3ldhhl0dg9p3ird0r&response_type=token&scope=openid+email+profile&redirect_uri=https://example.com
```

Login, then copy the `id_token` from the redirected URL.

### Step 2: Test API

```bash
TOKEN="PASTE_YOUR_TOKEN_HERE"

curl -X POST https://j0362geq43.execute-api.us-east-1.amazonaws.com/request-access \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "duration_hours": 4,
    "justification": "Testing portal"
  }'
```

You should get back an execution ARN!

---

## Verify It's Working

### Check Step Functions Execution

```bash
aws stepfunctions list-executions \
  --region us-east-1 \
  --state-machine-arn "arn:aws:states:us-east-1:935595346298:stateMachine:tdemy-jit-portal-approval-workflow"
```

### Manually Approve (for testing)

```bash
# Get the task token
TOKEN=$(aws dynamodb scan \
  --region us-east-1 \
  --table-name tdemy-jit-portal-approval-requests \
  --limit 1 \
  --query 'Items[0].TaskToken.S' \
  --output text)

# Approve it
curl -X POST "https://j0362geq43.execute-api.us-east-1.amazonaws.com/process-approval?token=${TOKEN}&decision=approve"
```

### Check if Access Was Granted

```bash
aws dynamodb scan \
  --region us-east-1 \
  --table-name tdemy-jit-portal-sessions
```

You should see an ACTIVE session!

---

## Troubleshooting

**"Network error" in frontend?**
- Make sure you deployed the frontend first
- Check that API URL is correct in the form

**"401 Unauthorized"?**
- Get a fresh token (they expire after 1 hour)
- Make sure you're using the `id_token` not `access_token`

**"User doesn't exist"?**
- The user email must exist in IAM Identity Center
- Create user there or update Lambda to use Cognito user ID

**No approval email?**
- SNS subscription needs to be confirmed
- Or manually approve using the curl command above

---

## Complete Documentation

For detailed guides, see:
- [TESTING_GUIDE.md](TESTING_GUIDE.md) - Complete testing instructions
- [FIXING_STATE_ISSUE.md](FIXING_STATE_ISSUE.md) - Fix Terraform state
- [GET_URLS_MANUAL.md](GET_URLS_MANUAL.md) - Get URLs from AWS Console

---

## Quick Reference

**Create new user:**
```bash
aws cognito-idp admin-create-user \
  --region us-east-1 \
  --user-pool-id us-east-1_2OOoBRhNj \
  --username newuser@example.com \
  --user-attributes \
    Name=email,Value=newuser@example.com \
    Name=email_verified,Value=true \
    Name=custom:manager_email,Value=manager@example.com
```

**Set user password:**
```bash
aws cognito-idp admin-set-user-password \
  --region us-east-1 \
  --user-pool-id us-east-1_2OOoBRhNj \
  --username newuser@example.com \
  --password 'SecurePass123!' \
  --permanent
```

**View logs:**
```bash
aws logs tail /aws/lambda/tdemy-jit-portal-request-access --region us-east-1 --follow
```

**List active sessions:**
```bash
aws dynamodb scan --region us-east-1 --table-name tdemy-jit-portal-sessions
```

---

## Success!

If you got an execution ARN back from the API, your portal is working! 🎉

The workflow is:
1. User requests access → API returns execution ARN
2. Step Functions starts → Sends email to manager
3. Manager approves → Grant Lambda creates SSO assignment
4. After duration → Revoke Lambda removes access automatically

Test it now!
