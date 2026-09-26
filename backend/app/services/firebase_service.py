"""Firebase Admin integration for the FoodSense backend.

This module centralizes trusted-server Firebase access.

Responsibilities:
- Initialize the Firebase Admin SDK once.
- Obtain the Admin Authentication client.
- Obtain the Admin Firestore client.
- Verify Firebase ID tokens.
- Keep service-account credentials out of application source code.

For local development, the recommended credential mechanism is the
GOOGLE_APPLICATION_CREDENTIALS environment variable pointing to a service
account JSON file. Firebase's documentation recommends this approach for
service-account authentication outside Google-managed environments.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Any

import firebase_admin
from firebase_admin import auth, credentials, firestore
from google.cloud.firestore import Client as FirestoreClient
from dotenv import load_dotenv

from ..config import settings


# Load a local .env file when present. Values already supplied by the process
# environment are not overwritten by python-dotenv's default behavior.
load_dotenv()


@lru_cache(maxsize=1)
def get_firebase_app() -> firebase_admin.App:
    """Initialize and return the default Firebase Admin application.

    Credential resolution order:
    1. Explicit service-account path from settings.
    2. Application Default Credentials.

    On a developer machine, settings.firebase_credentials_path is normally
    populated through GOOGLE_APPLICATION_CREDENTIALS. In Google-managed
    environments, Application Default Credentials can be used without a
    service-account file.
    """
    try:
        return firebase_admin.get_app()
    except ValueError:
        pass

    credentials_path = settings.firebase_credentials_path.strip()

    if credentials_path:
        path = Path(credentials_path).expanduser()

        if not path.is_file():
            raise FileNotFoundError(
                "Firebase service-account file was not found: "
                f"{path}"
            )

        credential = credentials.Certificate(str(path))

        options: dict[str, Any] = {}

        if settings.firebase_project_id.strip():
            options["projectId"] = settings.firebase_project_id.strip()

        return firebase_admin.initialize_app(
            credential,
            options=options or None,
        )

    options = {}

    if settings.firebase_project_id.strip():
        options["projectId"] = settings.firebase_project_id.strip()

    # Uses Application Default Credentials. This is suitable for Google
    # managed environments and for local environments configured for ADC.
    return firebase_admin.initialize_app(
        options=options or None,
    )


@lru_cache(maxsize=1)
def get_auth_client() -> auth.Client:
    """Return the Firebase Admin Authentication client."""
    app = get_firebase_app()
    return auth.Client(app)


@lru_cache(maxsize=1)
def get_firestore_client() -> FirestoreClient:
    """Return the Firebase Admin Firestore client."""
    app = get_firebase_app()
    return firestore.client(app)


def verify_id_token(
    id_token: str,
    *,
    check_revoked: bool = True,
) -> dict[str, Any]:
    """Verify a Firebase ID token and return its decoded claims.

    Args:
        id_token: Raw Firebase ID token received from the trusted client.
        check_revoked: Whether Firebase should also reject revoked tokens.

    Raises:
        ValueError: If the token is empty.
        firebase_admin.exceptions.FirebaseError: If Firebase rejects the token.
    """
    token = id_token.strip()

    if not token:
        raise ValueError("Firebase ID token cannot be empty.")

    get_auth_client()

    return auth.verify_id_token(
        token,
        app=get_firebase_app(),
        check_revoked=check_revoked,
    )


def get_user_record(uid: str) -> auth.UserRecord:
    """Get a Firebase Authentication user by UID."""
    normalized_uid = uid.strip()

    if not normalized_uid:
        raise ValueError("Firebase UID cannot be empty.")

    return get_auth_client().get_user(normalized_uid)


def clear_cached_clients() -> None:
    """Clear cached Firebase clients.

    This is primarily useful for tests where Firebase needs to be reconfigured
    between test cases. It should not normally be called by application code.
    """
    get_auth_client.cache_clear()
    get_firestore_client.cache_clear()
    get_firebase_app.cache_clear()
