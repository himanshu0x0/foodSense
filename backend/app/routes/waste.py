"""Waste-analysis API routes for FoodSense.

The route layer handles:
- Firebase ID-token authentication
- Organization authorization
- Request validation
- Waste-service orchestration
- HTTP error mapping

Waste calculations remain in services/waste_service.py.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, status
from firebase_admin import auth
from google.cloud.firestore import Client as FirestoreClient

from ..schemas.waste_schema import (
    WasteAnalysisRequest,
    WasteAnalysisResponse,
    WasteTrendResponse,
)
from ..services.data_service import HistoricalDataService
from ..services.firebase_service import (
    get_firestore_client,
    verify_id_token,
)
from ..services.waste_service import WasteService


router = APIRouter(
    prefix="/waste",
    tags=["Waste Analysis"],
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


def get_waste_service(
    db: FirestoreClient = Depends(get_firestore_client),
) -> WasteService:
    """Build a waste-analysis service using the trusted Firestore client."""
    return WasteService(
        data_service=HistoricalDataService(db),
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
    """Raise an HTTP error when organization access is not allowed."""
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
    summary="Check waste-analysis service availability",
)
def waste_health() -> dict[str, str]:
    """Return a lightweight waste-analysis service status."""
    return {
        "service": "waste",
        "status": "available",
        "method": "historical_food_record_analysis",
    }


@router.post(
    "",
    response_model=WasteAnalysisResponse,
    summary="Analyze historical food waste",
)
def analyze_waste(
    request: WasteAnalysisRequest,
    user: dict[str, Any] = Depends(get_verified_user),
    db: FirestoreClient = Depends(get_firestore_client),
    waste_service: WasteService = Depends(get_waste_service),
) -> WasteAnalysisResponse:
    """Analyze organization-scoped food waste for a date range."""
    _authorize_organization(
        db,
        user,
        request.organization_id,
    )

    try:
        return waste_service.analyze(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to analyze food waste.",
        ) from exc


@router.post(
    "/trend",
    response_model=WasteTrendResponse,
    summary="Analyze daily waste trend",
)
def analyze_waste_trend(
    request: WasteAnalysisRequest,
    user: dict[str, Any] = Depends(get_verified_user),
    db: FirestoreClient = Depends(get_firestore_client),
    waste_service: WasteService = Depends(get_waste_service),
) -> WasteTrendResponse:
    """Return daily waste metrics and an overall trend."""
    _authorize_organization(
        db,
        user,
        request.organization_id,
    )

    try:
        return waste_service.analyze_trend(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to analyze the waste trend.",
        ) from exc
