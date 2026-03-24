variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "sso_instance_arn" {
  description = "ARN of the IAM Identity Center (SSO) instance"
  type        = string
  validation {
    condition     = can(regex("^arn:aws:sso:::instance/", var.sso_instance_arn))
    error_message = "SSO instance ARN must be valid and start with 'arn:aws:sso:::instance/'"
  }
}

variable "target_account_id" {
  description = "Target AWS account ID where permissions will be assigned"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.target_account_id))
    error_message = "Target account ID must be a 12-digit number"
  }
}

variable "permission_set_arn" {
  description = "ARN of the permission set to assign (e.g., AdministratorAccess)"
  type        = string
  validation {
    condition     = can(regex("^arn:aws:sso:::permissionSet/", var.permission_set_arn))
    error_message = "Permission set ARN must be valid and start with 'arn:aws:sso:::permissionSet/'"
  }
}

variable "max_session_duration_hours" {
  description = "Maximum session duration in hours (max 12 for IAM Identity Center)"
  type        = number
  default     = 12
  validation {
    condition     = var.max_session_duration_hours > 0 && var.max_session_duration_hours <= 12
    error_message = "Session duration must be between 1 and 12 hours"
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "tdemy-jit-portal"
}

variable "environment" {
  description = "Environment (e.g., dev, staging, prod)"
  type        = string
  default     = "prototype"
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 10
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 20
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Project   = "JIT-Access-Portal"
  }
}
