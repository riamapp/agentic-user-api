import json
import os
from typing import Any, Dict
from urllib.parse import unquote

from .auth import get_user_id_from_event
from .dynamodb_client import PreferencesRepository
from .models import (
    UserPreferencesUpdate,
    UploadUrlRequest,
    UploadUrlResponse,
    DownloadUrlResponse,
)
from .s3_client import S3ImageService

# Initialize repositories lazily to avoid errors during module import
_preferences_repo = None
_s3_service = None


def _get_preferences_repo():
    """Get or initialize preferences repository."""
    global _preferences_repo
    if _preferences_repo is None:
        table_name = os.environ.get("PREFERENCES_TABLE_NAME")
        if not table_name:
            raise ValueError("PREFERENCES_TABLE_NAME environment variable is not set")
        _preferences_repo = PreferencesRepository(table_name=table_name)
    return _preferences_repo


def _get_s3_service():
    """Get or initialize S3 service."""
    global _s3_service
    if _s3_service is None:
        bucket_name = os.environ.get("S3_BUCKET_NAME")
        if not bucket_name:
            raise ValueError("S3_BUCKET_NAME environment variable is not set")
        _s3_service = S3ImageService(bucket_name=bucket_name)
    return _s3_service


def _response(status_code: int, body: Any) -> Dict[str, Any]:
    """Generate a standard API Gateway HTTP API response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
        "body": json.dumps(body),
    }


def lambda_handler(event, context):
    """Lambda handler for user API requests."""
    try:
        method = event["requestContext"]["http"]["method"]
        raw_path = event["rawPath"]
        path_params = event.get("pathParameters") or {}
        
        # Strip stage prefix from path if present (e.g., "/dev/user/preferences" -> "/user/preferences")
        # API Gateway HTTP API v2 includes the stage name in rawPath
        if raw_path.startswith("/dev/") or raw_path.startswith("/prod/") or raw_path.startswith("/staging/"):
            path = raw_path.split("/", 2)[2]  # Remove first two segments (empty string and stage)
            path = "/" + path if path else "/"
        else:
            path = raw_path

        # Handle OPTIONS for CORS preflight (before auth check)
        if method == "OPTIONS":
            return _response(200, {})

        # Extract user ID from JWT token
        user_id = get_user_id_from_event(event)
        if not user_id:
            return _response(401, {"message": "Unauthorized"})

        # GET /user/preferences
        if path == "/user/preferences" and method == "GET":
            prefs = _get_preferences_repo().get_all_preferences(user_id=user_id)
            if not prefs:
                # Return default/empty preferences
                return _response(200, {"theme": None, "displayName": None, "displayPicture": None})
            # Return all attributes except user_id
            prefs_dict = {k: v for k, v in prefs.items() if k != "user_id"}
            return _response(200, prefs_dict)

        # PUT /user/preferences
        if path == "/user/preferences" and method == "PUT":
            body = json.loads(event.get("body") or "{}")
            prefs_in = UserPreferencesUpdate(**body)
            prefs = _get_preferences_repo().create_or_update_preferences(
                user_id=user_id, prefs_in=prefs_in
            )
            return _response(200, prefs.model_dump(exclude={"user_id"}))

        # POST /upload-url
        if path == "/upload-url" and method == "POST":
            body = json.loads(event.get("body") or "{}")
            upload_req = UploadUrlRequest(**body)

            upload_url, s3_key = _get_s3_service().generate_upload_url(
                user_id=user_id,
                file_name=upload_req.fileName,
                content_type=upload_req.contentType,
            )

            return _response(
                200, UploadUrlResponse(uploadUrl=upload_url, key=s3_key).model_dump()
            )

        # GET /download-url/{key}
        if path.startswith("/download-url/") and method == "GET":
            # Extract the key from the path (everything after "/download-url/")
            # This handles keys with slashes that API Gateway path parameters can't handle
            s3_key = unquote(path[len("/download-url/"):])

            # Validate user owns this key
            if not _get_s3_service().validate_user_owns_key(s3_key, user_id):
                return _response(403, {"message": "Forbidden: You don't own this image"})

            download_url = _get_s3_service().generate_download_url(s3_key)
            return _response(200, DownloadUrlResponse(downloadUrl=download_url).model_dump())

        # DELETE /delete-image/{key}
        if path.startswith("/delete-image/") and method == "DELETE":
            # Extract the key from the path (everything after "/delete-image/")
            # This handles keys with slashes that API Gateway path parameters can't handle
            s3_key = unquote(path[len("/delete-image/"):])

            # Validate user owns this key
            if not _get_s3_service().validate_user_owns_key(s3_key, user_id):
                return _response(403, {"message": "Forbidden: You don't own this image"})

            success = _get_s3_service().delete_image(s3_key)
            if success:
                return _response(204, {})
            return _response(500, {"message": "Failed to delete image"})

        return _response(404, {"message": "Not found"})
    
    except Exception as e:
        # Log the error for debugging
        error_message = str(e)
        error_type = type(e).__name__
        print(f"Error in user_handler: {error_type}: {error_message}")
        import traceback
        traceback_str = traceback.format_exc()
        print(traceback_str)
        
        # Return error details (in production, you might want to hide these)
        return _response(500, {
            "message": "Internal Server Error",
            "error": error_type,
            "details": error_message
        })
