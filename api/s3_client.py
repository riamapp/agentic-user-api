import os
import uuid
from datetime import timedelta
from typing import Optional

import boto3
from botocore.config import Config


class S3ImageService:
    """Service for managing S3 image operations with presigned URLs."""

    def __init__(self, bucket_name: str, expiration_seconds: int = 3600):
        """
        Initialize S3 image service.

        Args:
            bucket_name: Name of the S3 bucket
            expiration_seconds: Expiration time for presigned URLs in seconds (default 1 hour)
        """
        self.bucket_name = bucket_name
        self.expiration = timedelta(seconds=expiration_seconds)
        # Get region from environment or default to us-east-1
        region = os.environ.get("AWS_REGION", "us-east-1")
        # Use s3v4 signature and ensure region is set to prevent redirects
        # that can disrupt CORS preflight requests
        self.s3_client = boto3.client(
            "s3",
            region_name=region,
            config=Config(
                signature_version="s3v4",
                s3={"addressing_style": "virtual"}
            )
        )

    def generate_upload_url(
        self, user_id: str, file_name: str, content_type: str
    ) -> tuple[str, str]:
        """
        Generate a presigned URL for uploading an image to S3 using PUT.

        Args:
            user_id: User ID to organize images by user
            file_name: Original file name
            content_type: MIME type (e.g., 'image/png')

        Returns:
            Tuple of (presigned_upload_url, s3_key)
        """
        # Generate a unique key for the image
        file_extension = file_name.split(".")[-1] if "." in file_name else "jpg"
        s3_key = f"users/{user_id}/images/{uuid.uuid4()}.{file_extension}"

        # Generate presigned URL for PUT operation
        upload_url = self.s3_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self.bucket_name,
                "Key": s3_key,
                "ContentType": content_type,
            },
            ExpiresIn=int(self.expiration.total_seconds()),
        )

        return upload_url, s3_key

    def generate_download_url(self, s3_key: str) -> str:
        """
        Generate a presigned URL for downloading an image from S3.

        Args:
            s3_key: S3 key of the image

        Returns:
            Presigned download URL
        """
        download_url = self.s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket_name, "Key": s3_key},
            ExpiresIn=int(self.expiration.total_seconds()),
        )

        return download_url

    def delete_image(self, s3_key: str) -> bool:
        """
        Delete an image from S3.

        Args:
            s3_key: S3 key of the image to delete

        Returns:
            True if successful, False otherwise
        """
        try:
            self.s3_client.delete_object(Bucket=self.bucket_name, Key=s3_key)
            return True
        except Exception:
            return False

    def validate_user_owns_key(self, s3_key: str, user_id: str) -> bool:
        """
        Validate that an S3 key belongs to a specific user.

        Args:
            s3_key: S3 key to validate
            user_id: User ID to check ownership

        Returns:
            True if the key belongs to the user, False otherwise
        """
        expected_prefix = f"users/{user_id}/"
        return s3_key.startswith(expected_prefix)
