variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Logical project name"
  type        = string
  default     = "agentic-user-api"
}

variable "stage" {
  description = "Deployment stage (e.g. dev, prod)"
  type        = string
  default     = "dev"
}

variable "preferences_table_name" {
  description = "DynamoDB table name for user preferences"
  type        = string
  default     = "agentic-user-preferences"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for profile images"
  type        = string
  default     = "agentic-user-images"
}

variable "cognito_issuer_url" {
  description = "Cognito User Pool issuer URL for JWT auth (e.g., https://cognito-idp.region.amazonaws.com/pool-id)"
  type        = string
}

variable "cognito_allowed_client_ids" {
  description = "Allowed Cognito app client IDs (audiences)"
  type        = list(string)
}

# Note: lambda_zip_path variable removed - Lambda package is now built automatically via Makefile
