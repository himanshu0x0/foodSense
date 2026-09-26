"""Authenticated end-to-end forecast test for FoodSense.

This script verifies the complete Phase 2 path:

    Email/password Firebase login
        -> Firebase ID token
        -> POST /forecast
        -> backend token verification
        -> organization authorization
        -> Firestore historical-data read
        -> ForecastService
        -> ForecastResponse

Run from the backend directory with the virtual environment active:

    python test_authenticated_forecast.py

Requirements:
- backend/.env contains GOOGLE_APPLICATION_CREDENTIALS.
- backend/.env contains FOODSENSE_FIREBASE_PROJECT_ID or the project is
  discoverable from the service account.
- backend/.env contains FOODSENSE_FIREBASE_WEB_API_KEY.
- The test account must already exist in Firebase Authentication.
- That account must have users/{uid}.organizationId pointing to an existing
  organization the user owns or belongs to.

The password is entered interactively and is never printed or stored by this
script.
"""

from __future__ import annotations

import getpass
import os
import sys
from datetime import date, timedelta
from typing import Any

import requests
from dotenv import load_dotenv

from app.config import settings
from app.services.firebase_service import get_firestore_client


load_dotenv(
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        ".env",
    )
)


def _require_env(name: str) -> str:
    """Return a required environment variable."""
    value = os.getenv(name, "").strip()

    if not value:
        raise RuntimeError(
            f"{name} is missing from backend/.env."
        )

    return value


def _firebase_email_password_sign_in(
    *,
    email: str,
    password: str,
    api_key: str,
) -> dict[str, Any]:
    """Sign in through Firebase Authentication REST API.

    Firebase Auth ID tokens are issued by the Authentication API. The Admin
    SDK can then verify the returned ID token on the FastAPI side.
    """
    url = (
        "https://identitytoolkit.googleapis.com/v1/"
        f"accounts:signInWithPassword?key={api_key}"
    )

    response = requests.post(
        url,
        json={
            "email": email,
            "password": password,
            "returnSecureToken": True,
        },
        timeout=20,
    )

    if response.ok:
        return response.json()

    try:
        error_payload = response.json()
        firebase_error = (
            error_payload
            .get("error", {})
            .get("message", "Authentication failed.")
        )
    except ValueError:
        firebase_error = response.text or "Authentication failed."

    raise RuntimeError(
        f"Firebase Authentication failed: {firebase_error}"
    )


def _get_user_organization(
    *,
    uid: str,
) -> tuple[str, dict[str, Any]]:
    """Read the test user's organization ID and organization data."""
    db = get_firestore_client()

    user_snapshot = (
        db.collection("users")
        .document(uid)
        .get()
    )

    if not user_snapshot.exists:
        raise RuntimeError(
            f"Firestore users/{uid} does not exist."
        )

    user_data = user_snapshot.to_dict() or {}
    organization_id = str(
        user_data.get("organizationId", "")
    ).strip()

    if not organization_id:
        raise RuntimeError(
            f"users/{uid} does not contain organizationId."
        )

    organization_snapshot = (
        db.collection("organizations")
        .document(organization_id)
        .get()
    )

    if not organization_snapshot.exists:
        raise RuntimeError(
            f"Organization {organization_id!r} does not exist."
        )

    organization_data = (
        organization_snapshot.to_dict() or {}
    )

    return organization_id, organization_data


def _test_forecast_endpoint(
    *,
    id_token: str,
    organization_id: str,
    expected_people: int,
) -> dict[str, Any]:
    """Call the local FastAPI forecast endpoint."""
    forecast_url = "http://127.0.0.1:8000/forecast"

    forecast_date = date.today() + timedelta(days=1)

    payload: dict[str, Any] = {
        "organization_id": organization_id,
        "forecast_date": forecast_date.isoformat(),
        "meal_type": "Lunch",
        "expected_people": max(expected_people, 0),
        "special_event": False,
        "menu": "Test forecast",
    }

    response = requests.post(
        forecast_url,
        json=payload,
        headers={
            "Authorization": f"Bearer {id_token}",
            "Content-Type": "application/json",
        },
        timeout=30,
    )

    if not response.ok:
        try:
            details = response.json()
        except ValueError:
            details = response.text

        raise RuntimeError(
            f"POST /forecast returned HTTP {response.status_code}: "
            f"{details}"
        )

    return response.json()


def main() -> int:
    """Run the complete authenticated forecast test."""
    print("FoodSense authenticated forecast test")
    print("=" * 45)

    try:
        api_key = _require_env(
            "FOODSENSE_FIREBASE_WEB_API_KEY"
        )
    except RuntimeError as exc:
        print(f"Configuration error: {exc}")
        print()
        print(
            "Add the Firebase Web API key to backend/.env as "
            "FOODSENSE_FIREBASE_WEB_API_KEY=..."
        )
        return 2

    print(f"Backend project: {settings.firebase_project_id or '(from credentials)'}")
    print("Firebase Admin : configured")
    print("FastAPI target : http://127.0.0.1:8000/forecast")
    print()

    email = input("Firebase email: ").strip()

    if not email:
        print("Email cannot be empty.")
        return 2

    password = getpass.getpass("Firebase password: ")

    if not password:
        print("Password cannot be empty.")
        return 2

    try:
        print()
        print("1/4 Signing in with Firebase Authentication...")

        auth_result = _firebase_email_password_sign_in(
            email=email,
            password=password,
            api_key=api_key,
        )

        id_token = str(
            auth_result.get("idToken", "")
        ).strip()
        uid = str(
            auth_result.get("localId", "")
        ).strip()

        if not id_token or not uid:
            raise RuntimeError(
                "Firebase Authentication response did not contain "
                "an ID token and UID."
            )

        print("   PASS")

        print("2/4 Reading the user's organization...")
        organization_id, organization_data = _get_user_organization(
            uid=uid,
        )

        print(f"   PASS - organization: {organization_id}")

        people_served_raw = organization_data.get(
            "peopleServed",
            0,
        )

        try:
            expected_people = int(
                float(people_served_raw or 0)
            )
        except (TypeError, ValueError):
            expected_people = 0

        print("3/4 Calling authenticated POST /forecast...")
        result = _test_forecast_endpoint(
            id_token=id_token,
            organization_id=organization_id,
            expected_people=expected_people,
        )

        print("   PASS")
        print()
        print("4/4 Forecast response")
        print("-" * 45)

        fields_to_show = (
            "organization_id",
            "forecast_date",
            "meal_type",
            "expected_people",
            "predicted_demand",
            "safety_buffer",
            "recommended_production",
            "safety_buffer_percent",
            "confidence",
            "method",
            "training_records",
            "fallback_used",
            "generated_at",
        )

        for field in fields_to_show:
            print(f"{field:25}: {result.get(field)}")

        print()
        print("RESULT: END-TO-END FORECAST TEST PASSED")
        print()
        print(
            "This confirms Firebase login, ID-token verification, "
            "organization authorization, Firestore access, and the "
            "forecast service are connected."
        )

        return 0

    except requests.RequestException as exc:
        print()
        print(f"Network error: {exc}")
        print(
            "Make sure the FastAPI server is running and internet access "
            "is available for Firebase Authentication."
        )
        return 3

    except RuntimeError as exc:
        print()
        print(f"TEST FAILED: {exc}")
        return 4

    except Exception as exc:
        print()
        print(
            f"TEST FAILED: {type(exc).__name__}: {exc}"
        )
        print(
            "No passwords, ID tokens, or service-account contents were "
            "printed by this test."
        )
        return 5


if __name__ == "__main__":
    sys.exit(main())
