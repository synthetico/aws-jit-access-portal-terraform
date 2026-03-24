output "website_url" {
  description = "URL of the static website"
  value       = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
}

output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = aws_apigatewayv2_stage.main.invoke_url
}

output "api_endpoint_request_access" {
  description = "Full API endpoint for requesting access"
  value       = "${aws_apigatewayv2_stage.main.invoke_url}/request-access"
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing active sessions"
  value       = aws_dynamodb_table.sessions.name
}

output "grant_lambda_function_name" {
  description = "Name of the Lambda function that grants access"
  value       = aws_lambda_function.grant_access.function_name
}

output "revoke_lambda_function_name" {
  description = "Name of the Lambda function that revokes access"
  value       = aws_lambda_function.revoke_access.function_name
}

output "grant_lambda_log_group" {
  description = "CloudWatch Log Group for grant Lambda function"
  value       = aws_cloudwatch_log_group.grant_lambda.name
}

output "revoke_lambda_log_group" {
  description = "CloudWatch Log Group for revoke Lambda function"
  value       = aws_cloudwatch_log_group.revoke_lambda.name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket hosting the frontend"
  value       = aws_s3_bucket.frontend.id
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.jit_portal.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.jit_portal.arn
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.jit_portal.id
}

output "cognito_domain" {
  description = "Cognito User Pool Domain"
  value       = aws_cognito_user_pool_domain.jit_portal.domain
}

output "sns_topic_arn" {
  description = "SNS Topic ARN for approval notifications"
  value       = aws_sns_topic.approval_notifications.arn
}

output "step_functions_arn" {
  description = "Step Functions State Machine ARN for approval workflow"
  value       = aws_sfn_state_machine.approval_workflow.arn
}

output "approval_requests_table_name" {
  description = "DynamoDB table name for approval requests"
  value       = aws_dynamodb_table.approval_requests.name
}
