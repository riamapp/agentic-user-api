from typing import Dict, Optional


def get_user_id_from_event(event: Dict) -> Optional[str]:
    """
    Extracts the user id from a Cognito JWT authorizer (HTTP API v2 event).
    Uses the 'sub' claim from the JWT token.
    """
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
    )
    # Usually `sub` or a custom claim such as `username`
    return claims.get("sub")
