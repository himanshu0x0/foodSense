"""Local Firebase Admin connectivity test for FoodSense.

Run this file from the backend directory with the virtual environment active:

    python test_firebase_connection.py

The test:
1. Loads backend/.env through app.config.
2. Initializes Firebase Admin.
3. Connects to Cloud Firestore.
4. Performs a minimal read from organizations.

It never prints the service-account JSON contents, private key, or tokens.
"""

from __future__ import annotations

import sys

from firebase_admin import exceptions as firebase_exceptions

from app.config import settings
from app.services.firebase_service import (
    get_firebase_app,
    get_firestore_client,
)


def main() -> int:
    """Run a minimal Firebase Admin + Firestore connectivity test."""
    print("FoodSense Firebase Admin connectivity test")
    print("-" * 45)
    print(f"Environment : {settings.environment}")
    print(
        "Project ID  : "
        f"{settings.firebase_project_id or '(from credentials/ADC)'}"
    )

    if settings.firebase_credentials_path.strip():
        print("Credentials : service-account path configured")
    else:
        print("Credentials : Application Default Credentials")

    print()

    try:
        app = get_firebase_app()
        db = get_firestore_client()

        # Minimal Firestore read. This verifies that the Admin SDK can
        # authenticate and reach the configured Firestore project.
        documents = list(
            db.collection("organizations")
            .limit(1)
            .stream()
        )

        print("Firebase Admin : PASS")
        print(
            f"Firebase project: "
            f"{app.project_id or '(not reported by SDK)'}"
        )
        print("Firestore read  : PASS")

        if documents:
            print(
                "Data check      : An organization document is accessible."
            )
        else:
            print(
                "Data check      : Connection works; no organization "
                "documents were returned."
            )

        print()
        print("Result          : Firebase backend connection is ready.")
        return 0

    except FileNotFoundError as exc:
        print("Firebase Admin : NOT READY")
        print(f"Configuration  : {exc}")
        print()
        print(
            "Check GOOGLE_APPLICATION_CREDENTIALS in backend/.env "
            "and make sure the JSON file exists at that path."
        )
        return 2

    except ValueError as exc:
        print("Firebase Admin : NOT READY")
        print(f"Configuration  : {exc}")
        return 2

    except firebase_exceptions.FirebaseError as exc:
        print("Firebase Admin : FAILED")
        print(f"Firebase error : {exc}")
        print()
        print(
            "Check the service-account credentials, Firebase project, "
            "Firestore access, and network connection."
        )
        return 3

    except Exception as exc:
        print("Firebase Admin : FAILED")
        print(f"Connection error: {type(exc).__name__}: {exc}")
        print()
        print(
            "No credential contents were printed. Check backend/.env "
            "and Firebase configuration."
        )
        return 3


if __name__ == "__main__":
    sys.exit(main())
