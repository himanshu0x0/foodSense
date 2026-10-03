"""
FoodSense Cloudinary API routes.

The Flutter client never receives the Cloudinary API secret. It asks the
authenticated backend for signed upload parameters and can ask the backend
to delete an asset when a linked Firestore record is replacing/removing it.

Endpoints:
    GET  /cloudinary/health
    POST /cloudinary/sign-upload
    POST /cloudinary/delete-asset
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Header, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field

from ..services.cloudinary_service import (
    CloudinaryConfigurationError,
    CloudinaryService,
    CloudinaryValidationError,
)
from ..services.firebase_service import (
    get_firestore_client,
    verify_id_token,
)

router = APIRouter(
    prefix="/cloudinary",
    tags=["Cloudinary"],
)


class CloudinaryHealthResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: str
    configured: bool
    cloud_name: str | None = None
    message: str


class CloudinarySignUploadRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    organization_id: str = Field(min_length=1, max_length=100)
    media_type: str = Field(
        min_length=1,
        max_length=32,
        description="food_records, inventory, or surplus",
    )
    entity_id: str = Field(min_length=1, max_length=100)


class CloudinarySignUploadResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    cloud_name: str
    api_key: str
    timestamp: int
    signature: str
    asset_folder: str
    public_id: str
    resource_type: str


class CloudinaryDeleteAssetRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    organization_id: str = Field(min_length=1, max_length=100)
    media_type: str = Field(
        min_length=1,
        max_length=32,
        description="food_records, inventory, or surplus",
    )
    entity_id: str = Field(min_length=1, max_length=100)
    public_id: str = Field(min_length=1, max_length=255)
    resource_type: str = Field(
        default="image",
        min_length=1,
        max_length=16,
    )


class CloudinaryDeleteAssetResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    deleted: bool
    public_id: str
    resource_type: str
    message: str


_MEDIA_COLLECTIONS = {
    "food_records": "food_records",
    "inventory": "inventory",
    "surplus": "surplus",
}


def _extract_bearer_token(authorization: str | None) -> str:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header is required.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    scheme, separator, token = authorization.partition(" ")

    if scheme.lower() != "bearer" or not separator or not token.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization must use the Bearer scheme.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return token.strip()


def _get_authenticated_uid(authorization: str | None) -> str:
    token = _extract_bearer_token(authorization)

    try:
        decoded_token: dict[str, Any] = verify_id_token(token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase ID token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    uid = decoded_token.get("uid")
    if not isinstance(uid, str) or not uid.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase token did not contain a valid user ID.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return uid.strip()


def _get_organization_ref(organization_id: str):
    organization = organization_id.strip()

    if not organization:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Organization ID cannot be empty.",
        )

    return get_firestore_client().collection("organizations").document(
        organization
    )


def _verify_organization_access(
    *,
    organization_id: str,
    uid: str,
) -> None:
    """
    Verify that the Firebase user belongs to the organization.

    Organization owners may not have a members/{uid} document because the
    owner is represented by organizations/{organizationId}.ownerId, so owners
    are explicitly accepted here.
    """
    organization_ref = _get_organization_ref(organization_id)
    organization_snapshot = organization_ref.get()

    if not organization_snapshot.exists:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Organization does not exist or is not accessible.",
        )

    organization_data = (
        organization_snapshot.to_dict() or {}
    )

    owner_id = organization_data.get("ownerId")

    if isinstance(owner_id, str) and owner_id == uid:
        return

    member_snapshot = organization_ref.collection("members").document(uid).get()

    if not member_snapshot.exists:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User is not a member of this organization.",
        )


def _verify_media_type(media_type: str) -> str:
    normalized = media_type.strip().lower()

    if normalized not in _MEDIA_COLLECTIONS:
        allowed = ", ".join(sorted(_MEDIA_COLLECTIONS))
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"media_type must be one of: {allowed}.",
        )

    return normalized


def _get_media_document(
    *,
    organization_id: str,
    media_type: str,
    entity_id: str,
):
    normalized_media_type = _verify_media_type(media_type)
    normalized_entity_id = entity_id.strip()

    if not normalized_entity_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Entity ID cannot be empty.",
        )

    collection_name = _MEDIA_COLLECTIONS[normalized_media_type]

    return (
        _get_organization_ref(organization_id)
        .collection(collection_name)
        .document(normalized_entity_id)
    )


def _verify_media_write_access(
    *,
    media_document,
    uid: str,
) -> dict[str, Any]:
    snapshot = media_document.get()

    if not snapshot.exists:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="The linked media record does not exist.",
        )

    data: dict[str, Any] = snapshot.to_dict() or {}

    created_by = data.get("createdBy")

    if isinstance(created_by, str) and created_by == uid:
        return data

    organization_ref = media_document.parent.parent
    organization_snapshot = organization_ref.get()

    if not organization_snapshot.exists:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Organization does not exist or is not accessible.",
        )

    organization_data = organization_snapshot.to_dict() or {}
    owner_id = organization_data.get("ownerId")

    if isinstance(owner_id, str) and owner_id == uid:
        return data

    member_snapshot = organization_ref.collection("members").document(uid).get()

    if not member_snapshot.exists:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User is not a member of this organization.",
        )

    role = str(member_snapshot.to_dict().get("role", "")).strip().lower()

    if role not in {"owner", "admin", "manager"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Only the record creator or an organization "
                "owner/manager can delete linked media."
            ),
        )

    return data


def _get_cloudinary_service() -> CloudinaryService:
    try:
        return CloudinaryService.from_environment()
    except CloudinaryConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "Cloudinary is not configured on the backend. "
                "Set the required CLOUDINARY_* environment variables."
            ),
        ) from exc


@router.get(
    "/health",
    response_model=CloudinaryHealthResponse,
    summary="Check Cloudinary configuration",
)
def cloudinary_health() -> CloudinaryHealthResponse:
    try:
        service = CloudinaryService.from_environment()
    except CloudinaryConfigurationError as exc:
        return CloudinaryHealthResponse(
            status="degraded",
            configured=False,
            cloud_name=None,
            message=str(exc),
        )

    return CloudinaryHealthResponse(
        status="ok",
        configured=service.is_configured(),
        cloud_name=service.cloud_name,
        message="Cloudinary backend configuration is ready.",
    )


@router.post(
    "/sign-upload",
    response_model=CloudinarySignUploadResponse,
    summary="Generate a signed Cloudinary upload payload",
)
def sign_upload(
    payload: CloudinarySignUploadRequest,
    authorization: str | None = Header(default=None),
) -> CloudinarySignUploadResponse:
    """
    Verify Firebase authentication + organization membership, then sign an
    image upload for Cloudinary. The API secret is never returned.
    """
    uid = _get_authenticated_uid(authorization)

    _verify_organization_access(
        organization_id=payload.organization_id.strip(),
        uid=uid,
    )

    service = _get_cloudinary_service()

    try:
        signed_upload = service.generate_upload_signature(
            organization_id=payload.organization_id,
            media_type=payload.media_type,
            entity_id=payload.entity_id,
            resource_type="image",
        )
    except CloudinaryValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc

    return CloudinarySignUploadResponse(**signed_upload.to_dict())


@router.post(
    "/delete-asset",
    response_model=CloudinaryDeleteAssetResponse,
    summary="Delete a Cloudinary asset linked to an organization record",
)
def delete_asset(
    payload: CloudinaryDeleteAssetRequest,
    authorization: str | None = Header(default=None),
) -> CloudinaryDeleteAssetResponse:
    """
    Delete a Cloudinary image only when it is currently linked to the
    requested FoodSense Firestore record.

    The endpoint:
    1. Verifies the Firebase user.
    2. Verifies organization access.
    3. Loads the target Firestore record.
    4. Confirms imagePublicId matches the requested Cloudinary public ID.
    5. Verifies record write/delete authority.
    6. Deletes the Cloudinary asset using the backend-only API secret.

    Firestore media references are intentionally left to the repository layer
    so Cloudinary deletion and Firestore state changes remain explicit.
    """
    uid = _get_authenticated_uid(authorization)

    organization_id = payload.organization_id.strip()
    media_type = _verify_media_type(payload.media_type)
    entity_id = payload.entity_id.strip()
    requested_public_id = payload.public_id.strip()
    resource_type = payload.resource_type.strip().lower()

    _verify_organization_access(
        organization_id=organization_id,
        uid=uid,
    )

    media_document = _get_media_document(
        organization_id=organization_id,
        media_type=media_type,
        entity_id=entity_id,
    )

    media_data = _verify_media_write_access(
        media_document=media_document,
        uid=uid,
    )

    stored_public_id = str(media_data.get("imagePublicId", "")).strip()

    if not stored_public_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No Cloudinary image is linked to this record.",
        )

    if stored_public_id != requested_public_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="The requested Cloudinary asset is not linked to this record.",
        )

    service = _get_cloudinary_service()

    try:
        result = service.delete_asset(
            public_id=stored_public_id,
            resource_type=resource_type,
            invalidate=True,
        )
    except CloudinaryValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Cloudinary rejected the asset deletion request.",
        ) from exc

    result_status = str(result.get("result", "")).lower()

    if result_status not in {"ok", "not found"}:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Cloudinary did not confirm the asset deletion.",
        )

    return CloudinaryDeleteAssetResponse(
        deleted=result_status == "ok",
        public_id=stored_public_id,
        resource_type=resource_type,
        message=(
            "Cloudinary asset deleted successfully."
            if result_status == "ok"
            else "Cloudinary asset was already absent."
        ),
    )


__all__ = [
    "router",
    "CloudinaryHealthResponse",
    "CloudinarySignUploadRequest",
    "CloudinarySignUploadResponse",
    "CloudinaryDeleteAssetRequest",
    "CloudinaryDeleteAssetResponse",
]
