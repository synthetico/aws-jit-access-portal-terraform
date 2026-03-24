###############################################################################
# Cognito User Pool for Authentication with MFA
###############################################################################

resource "aws_cognito_user_pool" "jit_portal" {
  name = "${var.project_name}-users"

  # Password policy
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # MFA Configuration - Required for all users
  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # User attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = false

    string_attribute_constraints {
      min_length = 5
      max_length = 255
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 255
    }
  }

  # Custom attribute for manager email (for approval workflow)
  schema {
    name                     = "manager_email"
    attribute_data_type      = "String"
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 0
      max_length = 255
    }
  }

  # Email verification
  auto_verified_attributes = ["email"]

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Advanced security
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  # User account settings
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }

  # Verification message templates
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "JIT Access Portal - Verify your email"
    email_message        = "Your verification code is {####}"
  }

  tags = {
    Name = "${var.project_name}-user-pool"
  }
}

###############################################################################
# Cognito User Pool Client
###############################################################################

resource "aws_cognito_user_pool_client" "jit_portal" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.jit_portal.id

  # OAuth settings
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  # Token validity
  refresh_token_validity = 30
  access_token_validity  = 1
  id_token_validity      = 1
  token_validity_units {
    refresh_token = "days"
    access_token  = "hours"
    id_token      = "hours"
  }

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Read and write attributes
  read_attributes = [
    "email",
    "email_verified",
    "name",
    "custom:manager_email"
  ]

  write_attributes = [
    "email",
    "name",
    "custom:manager_email"
  ]
}

###############################################################################
# Cognito User Pool Domain
###############################################################################

resource "aws_cognito_user_pool_domain" "jit_portal" {
  domain       = "${var.project_name}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.jit_portal.id
}

###############################################################################
# Cognito Identity Pool (for AWS credentials if needed)
###############################################################################

resource "aws_cognito_identity_pool" "jit_portal" {
  identity_pool_name               = "${var.project_name}-identity"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.jit_portal.id
    provider_name           = aws_cognito_user_pool.jit_portal.endpoint
    server_side_token_check = true
  }

  tags = {
    Name = "${var.project_name}-identity-pool"
  }
}

###############################################################################
# IAM Roles for Cognito Identity Pool
###############################################################################

resource "aws_iam_role" "authenticated_cognito" {
  name = "${var.project_name}-cognito-authenticated-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.jit_portal.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-cognito-authenticated-role"
  }
}

resource "aws_iam_role_policy" "authenticated_cognito" {
  name = "cognito-authenticated-policy"
  role = aws_iam_role.authenticated_cognito.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAPIInvoke"
        Effect   = "Allow"
        Action   = "execute-api:Invoke"
        Resource = "${aws_apigatewayv2_api.main.execution_arn}/*"
      }
    ]
  })
}

resource "aws_cognito_identity_pool_roles_attachment" "jit_portal" {
  identity_pool_id = aws_cognito_identity_pool.jit_portal.id

  roles = {
    authenticated = aws_iam_role.authenticated_cognito.arn
  }
}
