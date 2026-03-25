#!/bin/bash

# Deploy frontend to S3

BUCKET_NAME="tdemy-jit-portal-frontend-935595346298"
REGION="us-east-1"

echo "=================================="
echo "Deploying Frontend to S3"
echo "=================================="
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity --region $REGION &>/dev/null; then
  echo "❌ AWS CLI credentials not configured"
  echo ""
  echo "Please configure AWS CLI first:"
  echo "  aws configure"
  echo ""
  exit 1
fi

# Upload files to S3
echo "📤 Uploading index.html to S3..."
aws s3 cp frontend/index.html s3://$BUCKET_NAME/ \
  --region $REGION \
  --content-type "text/html" \
  --cache-control "no-cache"

if [ $? -eq 0 ]; then
  echo "✅ Upload successful!"
else
  echo "❌ Upload failed!"
  exit 1
fi

# Configure S3 bucket for static website hosting
echo ""
echo "🌐 Configuring S3 static website hosting..."
aws s3 website s3://$BUCKET_NAME/ \
  --index-document index.html \
  --region $REGION

# Make bucket public (for website hosting)
echo ""
echo "🔓 Setting bucket policy for public read access..."
aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --region $REGION \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"PublicReadGetObject\",
        \"Effect\": \"Allow\",
        \"Principal\": \"*\",
        \"Action\": \"s3:GetObject\",
        \"Resource\": \"arn:aws:s3:::$BUCKET_NAME/*\"
      }
    ]
  }"

echo ""
echo "=================================="
echo "Deployment Complete!"
echo "=================================="
echo ""
echo "🌐 Your portal is now live at:"
echo "   http://$BUCKET_NAME.s3-website-$REGION.amazonaws.com"
echo ""
echo "Next steps:"
echo "1. Visit the URL above"
echo "2. Click 'Get Token from Cognito Hosted UI'"
echo "3. Log in with your Cognito credentials"
echo "4. You'll be redirected back with a token"
echo "5. Fill in the access request form and submit"
echo ""
