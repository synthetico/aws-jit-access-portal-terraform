#!/bin/bash

# Configuration
API_URL="https://j0362geq43.execute-api.us-east-1.amazonaws.com"
USER_POOL_ID="us-east-1_2OOoBRhNj"
CLIENT_ID="7ekm0frce3ldhhl0dg9p3ird0r"
REGION="us-east-1"

echo "=================================="
echo "JIT Access Portal - Testing Guide"
echo "=================================="
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity --region $REGION &>/dev/null; then
  echo "⚠️  AWS CLI credentials not configured"
  echo ""
  echo "Please configure AWS CLI first:"
  echo "  aws configure"
  echo ""
  exit 1
fi

echo "Your Configuration:"
echo "  API URL: $API_URL"
echo "  User Pool: $USER_POOL_ID"
echo "  Client ID: $CLIENT_ID"
echo ""

# Ask for username and password
read -p "Enter your Cognito username (email): " USERNAME
read -sp "Enter your password: " PASSWORD
echo ""
echo ""

echo "🔐 Authenticating with Cognito..."

# Attempt to authenticate
AUTH_RESPONSE=$(aws cognito-idp initiate-auth \
  --region $REGION \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=$USERNAME,PASSWORD=$PASSWORD \
  2>&1)

# Check if MFA is required
if echo "$AUTH_RESPONSE" | grep -q "SOFTWARE_TOKEN_MFA"; then
  echo "📱 MFA Required"
  echo ""

  SESSION=$(echo "$AUTH_RESPONSE" | jq -r '.Session')

  read -p "Enter your MFA code from authenticator app: " MFA_CODE

  AUTH_RESPONSE=$(aws cognito-idp respond-to-auth-challenge \
    --region $REGION \
    --client-id $CLIENT_ID \
    --challenge-name SOFTWARE_TOKEN_MFA \
    --session "$SESSION" \
    --challenge-responses USERNAME=$USERNAME,SOFTWARE_TOKEN_MFA_CODE=$MFA_CODE \
    2>&1)
fi

# Extract tokens
ID_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.AuthenticationResult.IdToken // empty')
ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.AuthenticationResult.AccessToken // empty')

if [ -z "$ID_TOKEN" ]; then
  echo "❌ Authentication failed!"
  echo ""
  echo "Response:"
  echo "$AUTH_RESPONSE"
  exit 1
fi

echo "✅ Authentication successful!"
echo ""

# Test the API
echo "=================================="
echo "Testing API Endpoints"
echo "=================================="
echo ""

# Test 1: Request Access
echo "1️⃣  Testing /request-access endpoint..."
echo ""

read -p "Duration in hours (1-12) [default: 4]: " DURATION
DURATION=${DURATION:-4}

read -p "Justification: " JUSTIFICATION
JUSTIFICATION=${JUSTIFICATION:-"Testing JIT access portal"}

REQUEST_RESPONSE=$(curl -s -X POST "${API_URL}/request-access" \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"duration_hours\": $DURATION,
    \"justification\": \"$JUSTIFICATION\"
  }")

echo "Response:"
echo "$REQUEST_RESPONSE" | jq '.' 2>/dev/null || echo "$REQUEST_RESPONSE"
echo ""

# Extract execution ARN
EXECUTION_ARN=$(echo "$REQUEST_RESPONSE" | jq -r '.execution_arn // empty')

if [ -n "$EXECUTION_ARN" ]; then
  echo "✅ Request submitted successfully!"
  echo ""
  echo "Step Functions Execution:"
  echo "  ARN: $EXECUTION_ARN"
  echo ""

  # Get execution status
  echo "📊 Checking execution status..."
  aws stepfunctions describe-execution \
    --region $REGION \
    --execution-arn "$EXECUTION_ARN" \
    --query '{Status: status, StartTime: startDate}' \
    --output table

  echo ""
  echo "💡 The approval workflow has started!"
  echo "   Manager should receive an email with approve/deny links."
  echo ""

  # Extract task token from DynamoDB (if we can)
  echo "📧 Checking for approval request in DynamoDB..."

  # Get the request ID from the execution name
  REQUEST_ID=$(echo "$EXECUTION_ARN" | grep -o '[^:]*$')

  APPROVAL_ITEM=$(aws dynamodb get-item \
    --region $REGION \
    --table-name tdemy-jit-portal-approval-requests \
    --key "{\"RequestID\": {\"S\": \"$REQUEST_ID\"}}" \
    --output json 2>/dev/null)

  if [ -n "$APPROVAL_ITEM" ]; then
    TASK_TOKEN=$(echo "$APPROVAL_ITEM" | jq -r '.Item.TaskToken.S // empty')

    if [ -n "$TASK_TOKEN" ]; then
      echo "✅ Approval request found in database"
      echo ""
      echo "🧪 You can manually approve/deny this request:"
      echo ""
      echo "To APPROVE:"
      echo "  curl -X POST '${API_URL}/process-approval?token=${TASK_TOKEN}&decision=approve'"
      echo ""
      echo "To DENY:"
      echo "  curl -X POST '${API_URL}/process-approval?token=${TASK_TOKEN}&decision=deny'"
      echo ""
    fi
  fi
else
  echo "❌ Request failed"
  echo ""
  echo "Troubleshooting:"
  echo "1. Check CloudWatch Logs:"
  echo "   aws logs tail /aws/lambda/tdemy-jit-portal-request-access --region $REGION --follow"
  echo ""
  echo "2. Check API Gateway logs:"
  echo "   aws logs tail /aws/apigateway/tdemy-jit-portal --region $REGION --follow"
  echo ""
fi

echo "=================================="
echo "Testing Complete!"
echo "=================================="
echo ""
echo "Next steps:"
echo "1. Check your manager's email for approval link"
echo "2. Or use the manual approval curl command above"
echo "3. After approval, check DynamoDB for the session:"
echo "   aws dynamodb scan --region $REGION --table-name tdemy-jit-portal-sessions"
echo ""
