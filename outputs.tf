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
