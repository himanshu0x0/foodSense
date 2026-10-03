from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, status
from firebase_admin import exceptions as firebase_exceptions

from google.cloud.firestore import Client as FirestoreClient

from ..schemas.delivery_routing_schema import (
    DeliveryRoutingRequest,
    DeliveryRoutingResponse,
)
from ..services.delivery_routing_service import DeliveryRoutingService
from ..services.firebase_service import (
    get_firestore_client,
    verify_id_token,
)


router = APIRouter(
    prefix="/delivery-routing",
    tags=["Delivery Routing"],
)


def get_verified_user(
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
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
    except (ValueError, firebase_exceptions.FirebaseError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase authentication.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase authentication failed.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


def _has_organization_access(
    db: FirestoreClient,
    *,
    user_id: str,
    organization_id: str,
) -> bool:
    org_ref = (
        db.collection("organizations")
        .document(organization_id)
    )

    organization = org_ref.get()

    if not organization.exists:
        return False

    organization_data = organization.to_dict() or {}

    if organization_data.get("ownerId") == user_id:
        return True

    member = (
        org_ref.collection("members")
        .document(user_id)
        .get()
    )

    if member.exists:
        return True

    partner = (
        org_ref.collection("delivery_partners")
        .document(user_id)
        .get()
    )

    partner_data = partner.to_dict() or {}

    return bool(
        partner.exists
        and partner_data.get("active") is True
    )


@router.get(
    "/health",
    summary="Check traffic-aware routing configuration",
)
def delivery_routing_health() -> dict[str, str]:
    service = DeliveryRoutingService()

    return {
        "service": "delivery-routing",
        "status": (
            "available"
            if service.configured
            else "configuration_required"
        ),
        "routingPreference": "TRAFFIC_AWARE_OPTIMAL",
    }


@router.post(
    "/compute",
    response_model=DeliveryRoutingResponse,
    summary="Compute a traffic-aware delivery route",
)
def compute_delivery_route(
    request: DeliveryRoutingRequest,
    user: dict[str, Any] = Depends(get_verified_user),
    db: FirestoreClient = Depends(get_firestore_client),
) -> DeliveryRoutingResponse:
    user_id = str(user.get("uid", "")).strip()

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase token does not contain a user ID.",
        )

    try:
        allowed = _has_organization_access(
            db,
            user_id=user_id,
            organization_id=request.organizationId.strip(),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "FoodSense could not verify organization access. "
                "Check Firebase Admin configuration."
            ),
        ) from exc

    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this organization.",
        )

    try:
        return DeliveryRoutingService().compute(request)
    except RuntimeError as exc:
        message = str(exc)

        if "not configured" in message.lower():
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=message,
            ) from exc

        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=message,
        ) from exc
