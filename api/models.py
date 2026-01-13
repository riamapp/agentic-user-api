from typing import Optional
from pydantic import BaseModel, Field


class UserPreferencesBase(BaseModel):
    theme: Optional[str] = Field(default=None, description="Theme: 'light', 'dark', or 'system'")
    displayName: Optional[str] = Field(default=None, max_length=100)
    displayPicture: Optional[str] = Field(default=None, description="S3 key for profile picture")


class UserPreferencesUpdate(BaseModel):
    theme: Optional[str] = Field(default=None, description="Theme: 'light', 'dark', or 'system'")
    displayName: Optional[str] = Field(default=None, max_length=100)
    displayPicture: Optional[str] = Field(default=None, description="S3 key for profile picture")


class UserPreferences(UserPreferencesBase):
    user_id: str


class UploadUrlRequest(BaseModel):
    fileName: str = Field(..., description="Original filename")
    contentType: str = Field(..., description="MIME type (e.g., 'image/png')")


class UploadUrlResponse(BaseModel):
    uploadUrl: str = Field(..., description="Presigned S3 upload URL")
    key: str = Field(..., description="S3 key to use for the uploaded file")


class DownloadUrlResponse(BaseModel):
    downloadUrl: str = Field(..., description="Presigned S3 download URL")
