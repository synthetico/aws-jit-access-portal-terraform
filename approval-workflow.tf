###############################################################################
# DynamoDB Table for Approval Requests
###############################################################################

resource "aws_dynamodb_table" "approval_requests" {
  name         = "${var.project_name}-approval-requests"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ApprovalID"

  attribute {
    name = "ApprovalID"
    type = "S"
  }

  attribute {
    name = "RequesterEmail"
    type = "S"
  }

  attribute {
    name = "Status"
    type = "S"
  }

  global_secondary_index {
    name            = "RequesterIndex"
    hash_key        = "RequesterEmail"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "Status"
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
    Name = "${var.project_name}-approval-requests"
  }
}

###############################################################################
# SNS Topic for Approval Notifications
###############################################################################

resource "aws_sns_topic" "approval_notifications" {
  name              = "${var.project_name}-approval-notifications"
  display_name      = "JIT Access Approval Notifications"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name = "${var.project_name}-approval-notifications"
  }
}

resource "aws_sns_topic_policy" "approval_notifications" {
  arn = aws_sns_topic.approval_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.approval_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

###############################################################################
# Step Functions State Machine for Approval Workflow
###############################################################################

resource "aws_sfn_state_machine" "approval_workflow" {
  name     = "${var.project_name}-approval-workflow"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "JIT Access Approval Workflow"
    StartAt = "SaveApprovalRequest"
    States = {
      SaveApprovalRequest = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.approval_requests.name
          Item = {
            "ApprovalID.$"     = "$.approval_id"
            "RequesterEmail.$" = "$.requester_email"
            "RequesterName.$"  = "$.requester_name"
            "ManagerEmail.$"   = "$.manager_email"
            "UserID.$"         = "$.user_id"
            "DurationHours.$"  = "$.duration_hours"
            "Justification.$"  = "$.justification"
            "Status"           = { S = "PENDING" }
            "RequestedAt.$"    = "$.requested_at"
            "ExpirationTime.$" = "$.expiration_time"
          }
        }
        Next = "SendApprovalEmail"
      }

      SendApprovalEmail = {
        Type     = "Task"
        Resource = aws_lambda_function.send_approval_email.arn
        Next     = "WaitForApproval"
        Retry = [
          {
            ErrorEquals = [
              "Lambda.ServiceException",
              "Lambda.AWSLambdaException",
              "Lambda.SdkClientException"
            ]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
      }

      WaitForApproval = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        Parameters = {
          FunctionName = aws_lambda_function.wait_for_approval.arn
          Payload = {
            "approval_id.$"     = "$.approval_id"
            "task_token.$"      = "$$.Task.Token"
            "requester_email.$" = "$.requester_email"
            "manager_email.$"   = "$.manager_email"
          }
        }
        TimeoutSeconds = 86400
        Next           = "CheckApprovalDecision"
        Catch = [
          {
            ErrorEquals = ["States.Timeout"]
            Next        = "ApprovalTimeout"
          }
        ]
      }

      CheckApprovalDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.decision"
            StringEquals = "APPROVED"
            Next         = "GrantAccess"
          }
        ]
        Default = "ApprovalDenied"
      }

      GrantAccess = {
        Type     = "Task"
        Resource = aws_lambda_function.grant_access.arn
        Next     = "UpdateApprovalStatusGranted"
        Retry = [
          {
            ErrorEquals = [
              "Lambda.ServiceException",
              "Lambda.AWSLambdaException"
            ]
            IntervalSeconds = 2
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
      }

      UpdateApprovalStatusGranted = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.approval_requests.name
          Key = {
            "ApprovalID.$" = "$.approval_id"
          }
          UpdateExpression = "SET #status = :status, ApprovedAt = :approved_at, ApprovedBy = :approved_by"
          ExpressionAttributeNames = {
            "#status" = "Status"
          }
          ExpressionAttributeValues = {
            ":status"        = { S = "APPROVED" }
            ":approved_at.$" = "$.approved_at"
            ":approved_by.$" = "$.approved_by"
          }
        }
        Next = "SuccessState"
      }

      ApprovalDenied = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.approval_requests.name
          Key = {
            "ApprovalID.$" = "$.approval_id"
          }
          UpdateExpression = "SET #status = :status, DeniedAt = :denied_at, DeniedBy = :denied_by, DenialReason = :reason"
          ExpressionAttributeNames = {
            "#status" = "Status"
          }
          ExpressionAttributeValues = {
            ":status"      = { S = "DENIED" }
            ":denied_at.$" = "$.denied_at"
            ":denied_by.$" = "$.denied_by"
            ":reason.$"    = "$.denial_reason"
          }
        }
        Next = "FailureState"
      }

      ApprovalTimeout = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.approval_requests.name
          Key = {
            "ApprovalID.$" = "$.approval_id"
          }
          UpdateExpression = "SET #status = :status"
          ExpressionAttributeNames = {
            "#status" = "Status"
          }
          ExpressionAttributeValues = {
            ":status" = { S = "TIMEOUT" }
          }
        }
        Next = "FailureState"
      }

      SuccessState = {
        Type = "Succeed"
      }

      FailureState = {
        Type  = "Fail"
        Error = "ApprovalDeniedOrTimeout"
        Cause = "Access request was denied or timed out"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Name = "${var.project_name}-approval-workflow"
  }
}

###############################################################################
# CloudWatch Log Group for Step Functions
###############################################################################

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/vendedlogs/states/${var.project_name}-approval-workflow"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-step-functions-logs"
  }
}

###############################################################################
# IAM Role for Step Functions
###############################################################################

resource "aws_iam_role" "step_functions" {
  name = "${var.project_name}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-step-functions-role"
  }
}

resource "aws_iam_role_policy" "step_functions" {
  name = "step-functions-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.grant_access.arn,
          aws_lambda_function.send_approval_email.arn,
          aws_lambda_function.wait_for_approval.arn
        ]
      },
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = [
          aws_dynamodb_table.approval_requests.arn,
          "${aws_dynamodb_table.approval_requests.arn}/index/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}
