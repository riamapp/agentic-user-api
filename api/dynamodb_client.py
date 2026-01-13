from typing import Optional

import boto3
from .models import UserPreferences, UserPreferencesUpdate


class PreferencesRepository:
    def __init__(self, table_name: str):
        self._table = boto3.resource("dynamodb").Table(table_name)

    def get_preferences(self, user_id: str) -> Optional[UserPreferences]:
        """Get user preferences, returns None if not found."""
        resp = self._table.get_item(Key={"user_id": user_id})
        raw = resp.get("Item")
        if not raw:
            return None
        
        # Convert DynamoDB format to our model
        prefs = {
            "user_id": raw.get("user_id"),
            "theme": raw.get("theme"),
            "displayName": raw.get("displayName"),
            "displayPicture": raw.get("displayPicture"),
        }
        return UserPreferences(**prefs)

    def create_or_update_preferences(
        self, user_id: str, prefs_in: UserPreferencesUpdate
    ) -> UserPreferences:
        """Create or update user preferences."""
        existing = self.get_preferences(user_id)
        
        # Merge with existing preferences
        data = existing.model_dump() if existing else {"user_id": user_id}
        
        # Update only provided fields
        for key, value in prefs_in.model_dump(exclude_unset=True).items():
            if value is not None:
                data[key] = value
            elif key in data:
                # Allow explicit None to clear fields
                del data[key]
        
        # Ensure user_id is set
        data["user_id"] = user_id
        
        # Write to DynamoDB
        item = {k: v for k, v in data.items() if v is not None}
        self._table.put_item(Item=item)
        
        return UserPreferences(**data)
