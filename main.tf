terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.common_tags,
      {
        Environment = var.environment
        Project     = var.project_name
      }
    )
  }
}

###############################################################################
# DynamoDB Table for Session Tracking
###############################################################################

resource "aws_dynamodb_table" "sessions" {
  name           = "${var.project_name}-sessions"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "RequestID"
  stream_enabled = false

  attribute {
    name = "RequestID"
    type = "S"
  }

  attribute {
    name = "UserID"
    type = "S"
  }

  global_secondary_index {
    name            = "UserIDIndex"
    hash_key        = "UserID"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ExpirationTime"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-sessions"
  }
}

###############################################################################
# CloudWatch Log Groups
###############################################################################

resource "aws_cloudwatch_log_group" "grant_lambda" {
  name              = "/aws/lambda/${var.project_name}-grant-access"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-grant-access-logs"
  }
}

resource "aws_cloudwatch_log_group" "revoke_lambda" {
  name              = "/aws/lambda/${var.project_name}-revoke-access"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-revoke-access-logs"
  }
}

###############################################################################
# IAM Role and Policy for Grant Access Lambda
###############################################################################

resource "aws_iam_role" "grant_lambda" {
  name = "${var.project_name}-grant-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-grant-lambda-role"
  }
}

resource "aws_iam_role_policy" "grant_lambda_sso" {
  name = "sso-permissions"
  role = aws_iam_role.grant_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSOAccountAssignment"
        Effect = "Allow"
        Action = [
          "sso:CreateAccountAssignment",
          "sso:DescribeAccountAssignmentCreationStatus"
        ]
        Resource = [
          var.sso_instance_arn,
          var.permission_set_arn,
          "arn:aws:sso:::account/${var.target_account_id}"
        ]
      },
      {
        Sid    = "SSOIdentityStoreRead"
        Effect = "Allow"
        Action = [
          "identitystore:DescribeUser",
          "identitystore:ListUsers"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "grant_lambda_dynamodb" {
  name = "dynamodb-permissions"
  role = aws_iam_role.grant_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.sessions.arn,
          "${aws_dynamodb_table.sessions.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "grant_lambda_scheduler" {
  name = "scheduler-permissions"
  role = aws_iam_role.grant_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EventBridgeSchedulerCreate"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule",
          "scheduler:GetSchedule"
        ]
        Resource = "arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/default/${var.project_name}-revoke-*"
      },
      {
        Sid      = "PassRoleToScheduler"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.scheduler_execution.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "scheduler.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "grant_lambda_dlq" {
  name = "sqs-dlq-permissions"
  role = aws_iam_role.grant_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSDLQAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.grant_dlq.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "grant_lambda_basic" {
  role       = aws_iam_role.grant_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################################################
# IAM Role and Policy for Revoke Access Lambda
###############################################################################

resource "aws_iam_role" "revoke_lambda" {
  name = "${var.project_name}-revoke-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-revoke-lambda-role"
  }
}

resource "aws_iam_role_policy" "revoke_lambda_sso" {
  name = "sso-permissions"
  role = aws_iam_role.revoke_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSOAccountAssignmentDelete"
        Effect = "Allow"
        Action = [
          "sso:DeleteAccountAssignment",
          "sso:DescribeAccountAssignmentDeletionStatus"
        ]
        Resource = [
          var.sso_instance_arn,
          var.permission_set_arn,
          "arn:aws:sso:::account/${var.target_account_id}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "revoke_lambda_dynamodb" {
  name = "dynamodb-permissions"
  role = aws_iam_role.revoke_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.sessions.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "revoke_lambda_scheduler" {
  name = "scheduler-permissions"
  role = aws_iam_role.revoke_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EventBridgeSchedulerDelete"
        Effect = "Allow"
        Action = [
          "scheduler:DeleteSchedule",
          "scheduler:GetSchedule"
        ]
        Resource = "arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/default/${var.project_name}-revoke-*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "revoke_lambda_dlq" {
  name = "sqs-dlq-permissions"
  role = aws_iam_role.revoke_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSDLQAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.revoke_dlq.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "revoke_lambda_basic" {
  role       = aws_iam_role.revoke_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################################################
# IAM Role for EventBridge Scheduler Execution
###############################################################################

resource "aws_iam_role" "scheduler_execution" {
  name = "${var.project_name}-scheduler-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-scheduler-execution-role"
  }
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  name = "invoke-lambda"
  role = aws_iam_role.scheduler_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeRevokeLambda"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.revoke_access.arn
      }
    ]
  })
}

###############################################################################
# Data Source for Current AWS Account
###############################################################################

data "aws_caller_identity" "current" {}

###############################################################################
# Lambda Function - Request Access (Entry Point)
###############################################################################

resource "aws_cloudwatch_log_group" "request_access" {
  name              = "/aws/lambda/${var.project_name}-request-access"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-request-access-logs"
  }
}

resource "aws_iam_role" "request_access" {
  name = "${var.project_name}-request-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-request-access-role"
  }
}

resource "aws_iam_role_policy" "request_access_stepfunctions" {
  name = "stepfunctions-start-execution"
  role = aws_iam_role.request_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartStepFunctions"
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.approval_workflow.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "request_access_cognito" {
  name = "cognito-read"
  role = aws_iam_role.request_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadCognitoUsers"
        Effect = "Allow"
        Action = [
          "cognito-idp:GetUser",
          "cognito-idp:AdminGetUser"
        ]
        Resource = aws_cognito_user_pool.jit_portal.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "request_access_basic" {
  role       = aws_iam_role.request_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "request_access" {
  type        = "zip"
  output_path = "${path.module}/.terraform/archive/request_access.zip"

  source {
    content  = file("${path.module}/lambda/request_access.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "request_access" {
  filename         = data.archive_file.request_access.output_path
  function_name    = "${var.project_name}-request-access"
  role             = aws_iam_role.request_access.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.request_access.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      STEP_FUNCTIONS_ARN = aws_sfn_state_machine.approval_workflow.arn
      MAX_DURATION_HOURS = var.max_session_duration_hours
      USER_POOL_ID       = aws_cognito_user_pool.jit_portal.id
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.request_access.name
  }

  tags = {
    Name = "${var.project_name}-request-access"
  }

  depends_on = [
    aws_cloudwatch_log_group.request_access,
    aws_iam_role_policy.request_access_stepfunctions,
    aws_iam_role_policy.request_access_cognito
  ]
}

###############################################################################
# Lambda Function - Grant Access (Called by Step Functions)
###############################################################################

data "archive_file" "grant_lambda" {
  type        = "zip"
  output_path = "${path.module}/.terraform/archive/grant_lambda.zip"

  source {
    content  = file("${path.module}/lambda/grant_access.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "grant_access" {
  filename         = data.archive_file.grant_lambda.output_path
  function_name    = "${var.project_name}-grant-access"
  role             = aws_iam_role.grant_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.grant_lambda.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.sessions.name
      SSO_INSTANCE_ARN    = var.sso_instance_arn
      TARGET_ACCOUNT_ID   = var.target_account_id
      PERMISSION_SET_ARN  = var.permission_set_arn
      MAX_DURATION_HOURS  = var.max_session_duration_hours
      SCHEDULER_ROLE_ARN  = aws_iam_role.scheduler_execution.arn
      REVOKE_LAMBDA_ARN   = aws_lambda_function.revoke_access.arn
      PROJECT_NAME        = var.project_name
      AWS_REGION          = var.aws_region
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.grant_lambda.name
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.grant_dlq.arn
  }

  tags = {
    Name = "${var.project_name}-grant-access"
  }

  depends_on = [
    aws_cloudwatch_log_group.grant_lambda,
    aws_iam_role_policy.grant_lambda_sso,
    aws_iam_role_policy.grant_lambda_dynamodb,
    aws_iam_role_policy.grant_lambda_scheduler,
    aws_iam_role_policy.grant_lambda_dlq,
    aws_iam_role_policy_attachment.grant_lambda_basic
  ]
}

###############################################################################
# Lambda Function - Revoke Access
###############################################################################

data "archive_file" "revoke_lambda" {
  type        = "zip"
  output_path = "${path.module}/.terraform/archive/revoke_lambda.zip"

  source {
    content  = file("${path.module}/lambda/revoke_access.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "revoke_access" {
  filename         = data.archive_file.revoke_lambda.output_path
  function_name    = "${var.project_name}-revoke-access"
  role             = aws_iam_role.revoke_lambda.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.revoke_lambda.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.sessions.name
      SSO_INSTANCE_ARN    = var.sso_instance_arn
      TARGET_ACCOUNT_ID   = var.target_account_id
      PERMISSION_SET_ARN  = var.permission_set_arn
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.revoke_lambda.name
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.revoke_dlq.arn
  }

  tags = {
    Name = "${var.project_name}-revoke-access"
  }

  depends_on = [
    aws_cloudwatch_log_group.revoke_lambda,
    aws_iam_role_policy.revoke_lambda_sso,
    aws_iam_role_policy.revoke_lambda_dynamodb,
    aws_iam_role_policy.revoke_lambda_dlq,
    aws_iam_role_policy_attachment.revoke_lambda_basic
  ]
}

###############################################################################
# Dead Letter Queues for Lambda Functions
###############################################################################

resource "aws_sqs_queue" "grant_dlq" {
  name                       = "${var.project_name}-grant-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300

  tags = {
    Name = "${var.project_name}-grant-dlq"
  }
}

resource "aws_sqs_queue" "revoke_dlq" {
  name                       = "${var.project_name}-revoke-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300

  tags = {
    Name = "${var.project_name}-revoke-dlq"
  }
}

###############################################################################
# API Gateway (HTTP API)
###############################################################################

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "JIT Access Portal API"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type", "x-amz-date", "authorization", "x-api-key"]
    max_age       = 300
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst_limit
    throttling_rate_limit  = var.api_throttle_rate_limit
  }

  tags = {
    Name = "${var.project_name}-api-stage"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-api-gateway-logs"
  }
}

###############################################################################
# Cognito Authorizer for API Gateway
###############################################################################

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.jit_portal.id]
    issuer   = "https://${aws_cognito_user_pool.jit_portal.endpoint}"
  }
}

###############################################################################
# API Gateway Integrations and Routes
###############################################################################

resource "aws_apigatewayv2_integration" "request_access" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.request_access.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "request_access" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /request-access"
  target             = "integrations/${aws_apigatewayv2_integration.request_access.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "api_gateway_request" {
  statement_id  = "AllowAPIGatewayInvokeRequest"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.request_access.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Process Approval Integration
resource "aws_apigatewayv2_integration" "process_approval" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.process_approval.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "process_approval" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /process-approval"
  target             = "integrations/${aws_apigatewayv2_integration.process_approval.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "api_gateway_process_approval" {
  statement_id  = "AllowAPIGatewayInvokeProcessApproval"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_approval.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

###############################################################################
# S3 Bucket for Static Website Hosting
###############################################################################

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-frontend"
  }
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  content_type = "text/html"
  content = templatefile("${path.module}/frontend/index.html", {
    api_endpoint = "${aws_apigatewayv2_stage.main.invoke_url}/request-access"
  })

  etag = filemd5("${path.module}/frontend/index.html")
}
