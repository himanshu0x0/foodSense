"""Surplus prediction API routes for FoodSense.

The route layer handles:
- Firebase ID-token authentication
- Organization authorization
- Request validation
- Surplus-service orchestration
- HTTP error mapping

Surplus calculations remain in services/surplus_service.py.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, status
from firebase_admin import auth
from google.cloud.firestore import Client as FirestoreClient

from ..schemas.surplus_schema import (
    SurplusRequest,
    SurplusResponse,
    SurplusScenario,
    SurplusScenarioRequest,
)
from ..services.firebase_service import (
    get_firestore_client,
    verify_id_token,
)
from ..services.data_service import HistoricalDataService
from ..services.forecast_service import ForecastService
from ..services.surplus_service import SurplusService


router = APIRouter(
    prefix="/surplus",
    tags=["Surplus"],
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


def get_surplus_service(
    db: FirestoreClient = Depends(get_firestore_client),
) -> SurplusService:
    """Build a surplus service using trusted Firebase clients."""
    data_service = HistoricalDataService(db)
    forecast_service = ForecastService(
        data_service=data_service,
    )

    return SurplusService(
        data_service=data_service,
        forecast_service=forecast_service,
    )


def _user_has_organization_access(
    db: FirestoreClient,
    *,
    user_id: str,
    organization_id: str,
) -> bool:
    """Check whether the authenticated user owns or belongs to an organization."""
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


def _authorize_organization(
    db: FirestoreClient,
    user: dict[str, Any],
    organization_id: str,
) -> None:
    """Raise an HTTP error when the user lacks organization access."""
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
            organization_id=organization_id,
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


@router.get(
    "/health",
    summary="Check surplus service availability",
)
def surplus_health() -> dict[str, str]:
    """Return a lightweight surplus-service status."""
    return {
        "service": "surplus",
        "status": "available",
        "method": "forecast_based_surplus",
    }


@router.post(
    "",
    response_model=SurplusResponse,
    summary="Predict meal surplus",
)
def predict_surplus(
    request: SurplusRequest,
    user: dict[str, Any] = Depends(get_verified_user),
    db: FirestoreClient = Depends(get_firestore_client),
    surplus_service: SurplusService = Depends(get_surplus_service),
) -> SurplusResponse:
    """Generate an organization-scoped surplus prediction."""
    _authorize_organization(
        db,
        user,
        request.organization_id,
    )

    try:
        return surplus_service.predict(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to generate the surplus prediction.",
        ) from exc


@router.post(
    "/scenarios",
    response_model=list[SurplusScenario],
    summary="Compare surplus across production scenarios",
)
def compare_surplus_scenarios(
    request: SurplusScenarioRequest,
    user: dict[str, Any] = Depends(get_verified_user),
    db: FirestoreClient = Depends(get_firestore_client),
    surplus_service: SurplusService = Depends(get_surplus_service),
) -> list[SurplusScenario]:
    """Compare multiple production quantities for the same demand forecast."""
    _authorize_organization(
        db,
        user,
        request.organization_id,
    )

    try:
        return surplus_service.compare_scenarios(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to compare surplus scenarios.",
        ) from exc
