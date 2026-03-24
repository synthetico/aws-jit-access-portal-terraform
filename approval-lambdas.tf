###############################################################################
# CloudWatch Log Groups for Approval Lambdas
###############################################################################

resource "aws_cloudwatch_log_group" "send_approval_email" {
  name              = "/aws/lambda/${var.project_name}-send-approval-email"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-send-approval-email-logs"
  }
}

resource "aws_cloudwatch_log_group" "wait_for_approval" {
  name              = "/aws/lambda/${var.project_name}-wait-for-approval"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-wait-for-approval-logs"
  }
}

resource "aws_cloudwatch_log_group" "process_approval" {
  name              = "/aws/lambda/${var.project_name}-process-approval"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-process-approval-logs"
  }
}

###############################################################################
# IAM Roles for Approval Lambdas
###############################################################################

# Send Approval Email Lambda Role
resource "aws_iam_role" "send_approval_email" {
  name = "${var.project_name}-send-approval-email-role"

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
    Name = "${var.project_name}-send-approval-email-role"
  }
}

resource "aws_iam_role_policy" "send_approval_email_sns" {
  name = "sns-publish"
  role = aws_iam_role.send_approval_email.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishToSNS"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.approval_notifications.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "send_approval_email_basic" {
  role       = aws_iam_role.send_approval_email.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Wait For Approval Lambda Role
resource "aws_iam_role" "wait_for_approval" {
  name = "${var.project_name}-wait-for-approval-role"

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
    Name = "${var.project_name}-wait-for-approval-role"
  }
}

resource "aws_iam_role_policy" "wait_for_approval_dynamodb" {
  name = "dynamodb-access"
  role = aws_iam_role.wait_for_approval.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "UpdateApprovalTable"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.approval_requests.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wait_for_approval_basic" {
  role       = aws_iam_role.wait_for_approval.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Process Approval Lambda Role
resource "aws_iam_role" "process_approval" {
  name = "${var.project_name}-process-approval-role"

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
    Name = "${var.project_name}-process-approval-role"
  }
}

resource "aws_iam_role_policy" "process_approval_dynamodb" {
  name = "dynamodb-access"
  role = aws_iam_role.process_approval.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadApprovalTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.approval_requests.arn,
          "${aws_dynamodb_table.approval_requests.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "process_approval_stepfunctions" {
  name = "stepfunctions-callback"
  role = aws_iam_role.process_approval.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendTaskCallback"
        Effect = "Allow"
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure"
        ]
        Resource = aws_sfn_state_machine.approval_workflow.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "process_approval_cognito" {
  name = "cognito-read"
  role = aws_iam_role.process_approval.id

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

resource "aws_iam_role_policy_attachment" "process_approval_basic" {
  role       = aws_iam_role.process_approval.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################################################
# Lambda Functions
###############################################################################

# Send Approval Email Lambda
data "archive_file" "send_approval_email" {
  type        = "zip"
  output_path = "${path.module}/.terraform/archive/send_approval_email.zip"

  source {
    content  = file("${path.module}/lambda/send_approval_email.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "send_approval_email" {
  filename         = data.archive_file.send_approval_email.output_path
  function_name    = "${var.project_name}-send-approval-email"
  role             = aws_iam_role.send_approval_email.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.send_approval_email.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      SNS_TOPIC_ARN     = aws_sns_topic.approval_notifications.arn
      APPROVAL_BASE_URL = "${aws_apigatewayv2_stage.main.invoke_url}/process-approval"
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.send_approval_email.name
  }

  tags = {
    Name = "${var.project_name}-send-approval-email"
  }

  depends_on = [
    aws_cloudwatch_log_group.send_approval_email,
    aws_iam_role_policy.send_approval_email_sns
  ]
}

# Wait For Approval Lambda
data "archive_file" "wait_for_approval" {
  type        = "zip"
  output_path = "${path.module}/.terraform/archive/wait_for_approval.zip"

  source {
    content  = file("${path.module}/lambda/wait_for_approval.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "wait_for_approval" {
  filename         = data.archive_file.wait_for_approval.output_path
  function_name    = "${var.project_name}-wait-for-approval"
  role             = aws_iam_role.wait_for_approval.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.wait_for_approval.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      APPROVAL_TABLE_NAME = aws_dynamodb_table.approval_requests.name
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.wait_for_approval.name
  }

  tags = {
    Name = "${var.project_name}-wait-for-approval"
  }

  depends_on = [
    aws_cloudwatch_log_group.wait_for_approval,
    aws_iam_role_policy.wait_for_approval_dynamodb
  ]
}

# Process Approval Lambda
data "archive_file" "process_approval" {
  type        = "zip"
  output_path = "${path.module}/.terraform/archive/process_approval.zip"

  source {
    content  = file("${path.module}/lambda/process_approval.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "process_approval" {
  filename         = data.archive_file.process_approval.output_path
  function_name    = "${var.project_name}-process-approval"
  role             = aws_iam_role.process_approval.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.process_approval.output_base64sha256
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      APPROVAL_TABLE_NAME = aws_dynamodb_table.approval_requests.name
      USER_POOL_ID        = aws_cognito_user_pool.jit_portal.id
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.process_approval.name
  }

  tags = {
    Name = "${var.project_name}-process-approval"
  }

  depends_on = [
    aws_cloudwatch_log_group.process_approval,
    aws_iam_role_policy.process_approval_dynamodb,
    aws_iam_role_policy.process_approval_stepfunctions,
    aws_iam_role_policy.process_approval_cognito
  ]
}
