## agentic-user-api

User preferences and profile management API for the Agentic platform.

Responsibilities:

- DynamoDB-backed user preferences store (theme, displayName, displayPicture)
- S3-backed profile image storage with presigned URLs
- HTTP API (API Gateway v2 HTTP) exposing:
  - `GET /user/preferences` – get user preferences
  - `PUT /user/preferences` – update user preferences
  - `POST /upload-url` – get presigned S3 upload URL
  - `GET /download-url/{key}` – get presigned S3 download URL
  - `DELETE /delete-image/{key}` – delete image from S3
- JWT auth via the shared Cognito User Pool from `agentic-auth`.

### Deploy

Build the Lambda package:

```bash
make lambda-zip
```

Then deploy with Terraform:

```bash
cd terraform

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with:
#  - aws_region
#  - cognito_issuer_url (from agentic-auth outputs - construct from user_pool_id)
#  - cognito_allowed_client_ids (from agentic-auth outputs)

terraform init
terraform apply
```

After deploy, note the `user_api_base_url` output and plug it into `agentic-frontend/.env` as `VITE_USER_API_GATEWAY_URL`.
