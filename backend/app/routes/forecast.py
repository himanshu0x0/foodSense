"""Forecast API routes for FoodSense.

The route layer handles:
- Firebase ID-token authentication
- Organization authorization
- Request validation
- Forecast service orchestration
- HTTP error mapping

Firebase initialization and trusted Firebase clients are centralized in
services/firebase_service.py.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, status
from firebase_admin import auth
from google.cloud.firestore import Client as FirestoreClient

from ..schemas.forecast_schema import ForecastRequest, ForecastResponse
from ..services.data_service import HistoricalDataService
from ..services.firebase_service import (
    get_auth_client,
    get_firestore_client,
    verify_id_token,
)
from ..services.forecast_service import ForecastService


router = APIRouter(
    prefix="/forecast",
    tags=["Forecast"],
)


def get_verified_user(
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    """Verify the Firebase Bearer token and return decoded claims."""
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    scheme, _, token = authorization.partition(" ")

    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization must use a Firebase Bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        return verify_id_token(
            token.strip(),
            check_revoked=True,
        )
    except auth.RevokedIdTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase ID token has been revoked.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except auth.ExpiredIdTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase ID token has expired.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except auth.InvalidIdTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Firebase ID token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase authentication failed.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


def get_forecast_service(
    db: FirestoreClient = Depends(get_firestore_client),
) -> ForecastService:
    """Build the forecasting service using the trusted Firestore client."""
    data_service = HistoricalDataService(db)

    return ForecastService(
        data_service=data_service,
    )


def _user_has_organization_access(
    db: FirestoreClient,
    *,
    user_id: str,
    organization_id: str,
) -> bool:
    """Check whether a Firebase user owns or belongs to an organization."""
    organization_ref = (
        db.collection("organizations")
        .document(organization_id)
    )

    organization_snapshot = organization_ref.get()

    if not organization_snapshot.exists:
        return False

    organization_data = organization_snapshot.to_dict() or {}

    if organization_data.get("ownerId") == user_id:
        return True

    member_snapshot = (
        organization_ref
        .collection("members")
        .document(user_id)
        .get()
    )

    return member_snapshot.exists


@router.get(
    "/health",
    summary="Check forecasting service availability",
)
def forecast_health() -> dict[str, str]:
    """Return a lightweight forecast-service status."""
    return {
        "service": "forecast",
        "status": "available",
        "method": "recency_weighted_baseline",
    }


@router.post(
    "",
    response_model=ForecastResponse,
    summary="Generate a food-demand forecast",
)
def generate_forecast(
    request: ForecastRequest,
    user: dict[str, Any] = Depends(get_verified_user),
    db: FirestoreClient = Depends(get_firestore_client),
    forecast_service: ForecastService = Depends(get_forecast_service),
) -> ForecastResponse:
    """Generate an organization-scoped demand forecast."""
    user_id = str(user.get("uid", "")).strip()

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase token does not contain a user ID.",
        )

    try:
        allowed = _user_has_organization_access(
            db,
            user_id=user_id,
            organization_id=request.organization_id,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "FoodSense could not verify organization access. "
                "Check Firebase Admin configuration and Firestore access."
            ),
        ) from exc

    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this organization.",
        )

    try:
        return forecast_service.forecast(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to generate the forecast.",
        ) from exc


# Keep the Firebase Auth dependency reachable through this route module so
# startup/import tooling can verify the Admin SDK dependency is available.
_ = get_auth_client
