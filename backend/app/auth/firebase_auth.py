import os
import logging
from typing import Dict, Any, Optional
import firebase_admin
from firebase_admin import credentials, auth
from fastapi import HTTPException, status
from app.config import settings

logger = logging.getLogger(__name__)

# Initialize Firebase Admin SDK once
_firebase_initialized = False


def initialize_firebase_admin() -> None:
    global _firebase_initialized
    if _firebase_initialized:
        return

    try:
        if settings.FIREBASE_SERVICE_ACCOUNT_PATH and os.path.exists(
            settings.FIREBASE_SERVICE_ACCOUNT_PATH
        ):
            cred = credentials.Certificate(settings.FIREBASE_SERVICE_ACCOUNT_PATH)
            firebase_admin.initialize_app(cred, {"projectId": settings.FIREBASE_PROJECT_ID})
            logger.info("Firebase Admin SDK initialized with service account certificate.")
        else:
            # Fall back to default application credentials or project ID
            firebase_admin.initialize_app(options={"projectId": settings.FIREBASE_PROJECT_ID})
            logger.info("Firebase Admin SDK initialized with default credentials.")
        _firebase_initialized = True
    except Exception as e:
        logger.warning("Firebase Admin initialization note: %s", e)
        _firebase_initialized = True


initialize_firebase_admin()


def verify_firebase_id_token(token: str) -> Dict[str, Any]:
    """
    Verifies a Firebase ID token using firebase-admin SDK.
    Strictly checks that the token is not revoked and email is verified.
    """
    if not token or not token.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication credentials.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        # Check revocation and decode token
        decoded_token = auth.verify_id_token(token, check_revoked=True)
    except auth.RevokedIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session has been revoked. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except auth.ExpiredIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication token has expired.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid authentication token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Enforce institutional email verification
    if not decoded_token.get("email_verified", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Institutional email address has not been verified.",
        )

    return decoded_token
