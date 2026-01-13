terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "default"
}

locals {
  name_prefix = "${var.project_name}-${var.stage}"
}

# DynamoDB table for user preferences
resource "aws_dynamodb_table" "preferences" {
  name         = var.preferences_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  tags = {
    Project = var.project_name
    Stage   = var.stage
  }
}

# S3 bucket for profile images
resource "aws_s3_bucket" "images" {
  bucket = "${var.s3_bucket_name}-${var.stage}"

  tags = {
    Project = var.project_name
    Stage   = var.stage
  }
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = [
      "Content-Type",
      "x-amz-date",
      "x-amz-content-sha256",
      "x-amz-security-token",
      "x-amz-user-agent",
      "x-amz-sdk-checksum-algorithm",
    ]
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = ["*"] # In production, restrict this to your frontend domain
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${local.name_prefix}-dynamodb"
  role = aws_iam_role.lambda_exec.id

  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]

    resources = [
      aws_dynamodb_table.preferences.arn
    ]
  }
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "${local.name_prefix}-s3"
  role = aws_iam_role.lambda_exec.id

  policy = data.aws_iam_policy_document.lambda_s3.json
}

data "aws_iam_policy_document" "lambda_s3" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = [
      "${aws_s3_bucket.images.arn}/*"
    ]
  }

  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.images.arn
    ]
  }
}

# Package Lambda function with dependencies using Makefile (ensures Linux-compatible builds)
resource "null_resource" "lambda_package" {
  triggers = {
    # Trigger rebuild if source files or requirements change
    # This checks pyproject.toml and all Python files in api/
    pyproject_hash = filemd5("${path.module}/../pyproject.toml")
    api_files_hash = sha256(join("", [
      for f in fileset("${path.module}/../api", "**/*.py") :
      filesha256("${path.module}/../api/${f}")
    ]))
  }

  provisioner "local-exec" {
    command     = "cd ${path.module}/.. && make lambda-zip"
    interpreter = ["/bin/bash", "-c"]
  }
}

locals {
  lambda_zip_path = "${path.module}/../user_lambda.zip"
  # Use a combination of source file hashes to ensure Lambda updates when code changes
  lambda_source_hash = base64sha256(join("", [
    filemd5("${path.module}/../pyproject.toml"),
    join("", [
      for f in fileset("${path.module}/../api", "**/*.py") :
      filesha256("${path.module}/../api/${f}")
    ])
  ]))
}

# Lambda function
resource "aws_lambda_function" "user_api" {
  function_name = "${local.name_prefix}-user-handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "api.user_handler.lambda_handler"
  runtime       = "python3.12"

  filename         = local.lambda_zip_path
  source_code_hash = local.lambda_source_hash

  depends_on = [null_resource.lambda_package]

  environment {
    variables = {
      PREFERENCES_TABLE_NAME = aws_dynamodb_table.preferences.name
      S3_BUCKET_NAME         = aws_s3_bucket.images.id
    }
  }

  timeout = 30
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "user_api" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"] # Allow all origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Amz-Date", "X-Amz-Security-Token"]
    allow_credentials = false
    max_age       = 300
  }
}

# Cognito JWT authorizer
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.user_api.id
  name             = "${local.name_prefix}-cognito-auth"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = var.cognito_allowed_client_ids
    issuer   = var.cognito_issuer_url
  }
}

# Lambda integration
resource "aws_apigatewayv2_integration" "user_lambda" {
  api_id                 = aws_apigatewayv2_api.user_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.user_api.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}


# Routes
resource "aws_apigatewayv2_route" "get_preferences" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "GET /user/preferences"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "put_preferences" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "PUT /user/preferences"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "post_upload_url" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "POST /upload-url"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "get_download_url" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "GET /download-url/{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "delete_image" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "DELETE /delete-image/{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

# OPTIONS routes for CORS preflight (bypass authorization, route to Lambda)
resource "aws_apigatewayv2_route" "options_preferences" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "OPTIONS /user/preferences"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "options_upload_url" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "OPTIONS /upload-url"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "options_download_url" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "OPTIONS /download-url/{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "options_delete_image" {
  api_id    = aws_apigatewayv2_api.user_api.id
  route_key = "OPTIONS /delete-image/{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.user_lambda.id}"
  authorization_type = "NONE"
}

# Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.user_api.id
  name        = var.stage
  auto_deploy = true
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.user_api.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.user_api.execution_arn}/*/*"
}
