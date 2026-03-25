#!/bin/bash

# Script to retrieve JIT Access Portal URLs
# Run this after the infrastructure has been deployed

set -e

REGION="us-east-1"
PROJECT_NAME="tdemy-jit-portal"

echo "=================================="
echo "JIT Access Portal - URLs & Info"
echo "=================================="
echo ""

# Get API Gateway URL
echo "🌐 API Gateway Endpoint:"
API_ID=$(aws apigatewayv2 get-apis --region $REGION \
  --query "Items[?Name=='${PROJECT_NAME}-api'].ApiId" \
  --output text)

if [ -n "$API_ID" ]; then
  API_ENDPOINT="https://${API_ID}.execute-api.${REGION}.amazonaws.com"
  echo "   $API_ENDPOINT"
else
  echo "   ⚠️  API Gateway not found"
fi
echo ""

# Get S3 Website URL
echo "🌐 S3 Website Endpoint:"
BUCKET_NAME="${PROJECT_NAME}-frontend-935595346298"
WEBSITE_URL=$(aws s3api get-bucket-website --region $REGION \
  --bucket $BUCKET_NAME \
  --query "''" --output text 2>/dev/null || echo "")

if [ -n "$WEBSITE_URL" ]; then
  echo "   http://${BUCKET_NAME}.s3-website-${REGION}.amazonaws.com"
else
  echo "   ⚠️  S3 website hosting not configured yet"
fi
echo ""

# Get CloudFront Distribution (if exists)
echo "🌐 CloudFront Distribution:"
CF_DOMAIN=$(aws cloudfront list-distributions --region $REGION \
  --query "DistributionList.Items[?Comment=='${PROJECT_NAME}'].DomainName" \
  --output text 2>/dev/null || echo "")

if [ -n "$CF_DOMAIN" ]; then
  echo "   https://${CF_DOMAIN}"
else
  echo "   ℹ️  CloudFront not configured (optional)"
fi
echo ""

# Get Cognito User Pool details
echo "👤 Cognito User Pool:"
USER_POOL_ID=$(aws cognito-idp list-user-pools --region $REGION \
  --max-results 20 \
  --query "UserPools[?Name=='${PROJECT_NAME}-user-pool'].Id" \
  --output text)

if [ -n "$USER_POOL_ID" ]; then
  echo "   Pool ID: $USER_POOL_ID"

  # Get App Client ID
  APP_CLIENT_ID=$(aws cognito-idp list-user-pool-clients --region $REGION \
    --user-pool-id $USER_POOL_ID \
    --query "UserPoolClients[0].ClientId" \
    --output text)

  echo "   App Client ID: $APP_CLIENT_ID"

  # Get Cognito Domain
  COGNITO_DOMAIN=$(aws cognito-idp describe-user-pool --region $REGION \
    --user-pool-id $USER_POOL_ID \
    --query "UserPool.Domain" \
    --output text 2>/dev/null || echo "${PROJECT_NAME}-935595346298")

  echo "   Hosted UI: https://${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com"
else
  echo "   ⚠️  User Pool not found"
fi
echo ""

# Get DynamoDB Tables
echo "📊 DynamoDB Tables:"
SESSIONS_TABLE=$(aws dynamodb describe-table --region $REGION \
  --table-name "${PROJECT_NAME}-sessions" \
  --query "Table.TableName" \
  --output text 2>/dev/null || echo "Not found")
echo "   Sessions: $SESSIONS_TABLE"

APPROVALS_TABLE=$(aws dynamodb describe-table --region $REGION \
  --table-name "${PROJECT_NAME}-approval-requests" \
  --query "Table.TableName" \
  --output text 2>/dev/null || echo "Not found")
echo "   Approvals: $APPROVALS_TABLE"
echo ""

# Get Step Functions State Machine
echo "⚙️  Step Functions State Machine:"
STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines --region $REGION \
  --query "stateMachines[?name=='${PROJECT_NAME}-approval-workflow'].stateMachineArn" \
  --output text)

if [ -n "$STATE_MACHINE_ARN" ]; then
  echo "   $STATE_MACHINE_ARN"
else
  echo "   ⚠️  State machine not found"
fi
echo ""

echo "=================================="
echo "Next Steps:"
echo "=================================="
echo ""
echo "1. Access the Portal:"
echo "   Visit the S3 or CloudFront URL above"
echo ""
echo "2. Create a User:"
echo "   aws cognito-idp admin-create-user \\"
echo "     --region $REGION \\"
echo "     --user-pool-id $USER_POOL_ID \\"
echo "     --username your-email@example.com \\"
echo "     --user-attributes Name=email,Value=your-email@example.com \\"
echo "                        Name=email_verified,Value=true \\"
echo "                        Name=custom:manager_email,Value=manager@example.com"
echo ""
echo "3. Test the API:"
echo "   curl -X POST $API_ENDPOINT/request-access \\"
echo "     -H 'Authorization: Bearer <COGNITO_JWT_TOKEN>' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"duration_hours\": 4, \"justification\": \"Test access\"}'"
echo ""
