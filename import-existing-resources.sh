#!/bin/bash

# Script to import existing AWS resources into Terraform state
# Run this when resources already exist but Terraform state is missing

set -e

REGION="us-east-1"
PROJECT_NAME="tdemy-jit-portal"
ACCOUNT_ID="935595346298"

echo "=================================="
echo "Importing Existing Resources"
echo "=================================="
echo ""

# Function to import if resource exists
import_if_exists() {
  local resource_type=$1
  local resource_name=$2
  local resource_id=$3

  echo "Importing: $resource_name"
  terraform import "$resource_type.$resource_name" "$resource_id" 2>/dev/null || echo "  ⚠️  Failed or already imported"
}

# DynamoDB Tables
echo "📊 Importing DynamoDB Tables..."
import_if_exists "aws_dynamodb_table" "sessions" "${PROJECT_NAME}-sessions"
import_if_exists "aws_dynamodb_table" "approval_requests" "${PROJECT_NAME}-approval-requests"
echo ""

# CloudWatch Log Groups
echo "📝 Importing CloudWatch Log Groups..."
import_if_exists "aws_cloudwatch_log_group" "grant_lambda" "/aws/lambda/${PROJECT_NAME}-grant-access"
import_if_exists "aws_cloudwatch_log_group" "revoke_lambda" "/aws/lambda/${PROJECT_NAME}-revoke-access"
import_if_exists "aws_cloudwatch_log_group" "request_access" "/aws/lambda/${PROJECT_NAME}-request-access"
import_if_exists "aws_cloudwatch_log_group" "send_approval_email" "/aws/lambda/${PROJECT_NAME}-send-approval-email"
import_if_exists "aws_cloudwatch_log_group" "wait_for_approval" "/aws/lambda/${PROJECT_NAME}-wait-for-approval"
import_if_exists "aws_cloudwatch_log_group" "process_approval" "/aws/lambda/${PROJECT_NAME}-process-approval"
import_if_exists "aws_cloudwatch_log_group" "step_functions" "/aws/vendedlogs/states/${PROJECT_NAME}-approval-workflow"
import_if_exists "aws_cloudwatch_log_group" "api_gateway" "/aws/apigateway/${PROJECT_NAME}"
echo ""

# IAM Roles
echo "🔐 Importing IAM Roles..."
import_if_exists "aws_iam_role" "grant_lambda" "${PROJECT_NAME}-grant-lambda-role"
import_if_exists "aws_iam_role" "revoke_lambda" "${PROJECT_NAME}-revoke-lambda-role"
import_if_exists "aws_iam_role" "scheduler_execution" "${PROJECT_NAME}-scheduler-execution-role"
import_if_exists "aws_iam_role" "request_access" "${PROJECT_NAME}-request-access-role"
import_if_exists "aws_iam_role" "send_approval_email" "${PROJECT_NAME}-send-approval-email-role"
import_if_exists "aws_iam_role" "wait_for_approval" "${PROJECT_NAME}-wait-for-approval-role"
import_if_exists "aws_iam_role" "process_approval" "${PROJECT_NAME}-process-approval-role"
import_if_exists "aws_iam_role" "step_functions" "${PROJECT_NAME}-step-functions-role"
import_if_exists "aws_iam_role" "authenticated_cognito" "${PROJECT_NAME}-cognito-authenticated-role"
echo ""

# S3 Bucket
echo "🪣 Importing S3 Bucket..."
import_if_exists "aws_s3_bucket" "frontend" "${PROJECT_NAME}-frontend-${ACCOUNT_ID}"
echo ""

# Cognito User Pool Domain
echo "👤 Importing Cognito Resources..."
# Note: Cognito domain import requires the domain name, not the full resource name
import_if_exists "aws_cognito_user_pool_domain" "jit_portal" "${PROJECT_NAME}-${ACCOUNT_ID}"
echo ""

echo "=================================="
echo "Import Complete!"
echo "=================================="
echo ""
echo "⚠️  IMPORTANT: Some resources may have failed to import if they don't exist"
echo "              or if the resource ID format is different."
echo ""
echo "Next steps:"
echo "1. Run 'terraform plan' to see remaining differences"
echo "2. Run 'terraform apply' to update any changed resources"
echo ""
