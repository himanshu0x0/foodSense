"""
FoodSense Cloudinary media service.

This service keeps Cloudinary credentials on the FastAPI backend and
can generate signed upload parameters for the Flutter client.

The client can then upload the actual image directly to Cloudinary.
The API secret stays on the backend and is never returned to the client.

Environment variables:
    CLOUDINARY_CLOUD_NAME
    CLOUDINARY_API_KEY
    CLOUDINARY_API_SECRET
    CLOUDINARY_SECURE=true
    CLOUDINARY_SIGNATURE_ALGORITHM=sha1|sha256
"""

from __future__ import annotations

import os
import re
import time
from dataclasses import dataclass
from typing import Any

from dotenv import load_dotenv

try:
    import cloudinary
    from cloudinary import utils
except ImportError as exc:  # pragma: no cover - setup guard
    raise RuntimeError(
        "Cloudinary is not installed. Run: pip install cloudinary"
    ) from exc


_BACKEND_DIR = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
_ENV_FILE = os.path.join(_BACKEND_DIR, ".env")
load_dotenv(_ENV_FILE)


class CloudinaryConfigurationError(RuntimeError):
    """Raised when the backend Cloudinary configuration is incomplete."""


class CloudinaryValidationError(ValueError):
    """Raised when a Cloudinary parameter is invalid."""


@dataclass(frozen=True)
class CloudinaryUploadSignature:
    """Safe signed-upload information returned to Flutter."""

    cloud_name: str
    api_key: str
    timestamp: int
    signature: str
    asset_folder: str
    public_id: str
    resource_type: str = "image"

    def to_dict(self) -> dict[str, Any]:
        return {
            "cloud_name": self.cloud_name,
            "api_key": self.api_key,
            "timestamp": self.timestamp,
            "signature": self.signature,
            "asset_folder": self.asset_folder,
            "public_id": self.public_id,
            "resource_type": self.resource_type,
        }


class CloudinaryService:
    """
    Backend-only Cloudinary integration for FoodSense.

    Main flow:
        Flutter -> FastAPI signed-upload params
        Flutter -> Cloudinary direct signed upload
        Flutter -> Firestore saves returned URL/public_id
    """

    _IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$")
    _RESOURCE_TYPES = frozenset({"image", "video", "raw"})
    _MEDIA_TYPES = frozenset({"food_records", "inventory", "surplus"})

    def __init__(
        self,
        *,
        cloud_name: str | None = None,
        api_key: str | None = None,
        api_secret: str | None = None,
        secure: bool | None = None,
        signature_algorithm: str | None = None,
    ) -> None:
        self.cloud_name = (
            cloud_name or os.getenv("CLOUDINARY_CLOUD_NAME", "")
        ).strip()
        self.api_key = (
            api_key or os.getenv("CLOUDINARY_API_KEY", "")
        ).strip()
        self.api_secret = (
            api_secret or os.getenv("CLOUDINARY_API_SECRET", "")
        ).strip()

        raw_secure = os.getenv("CLOUDINARY_SECURE", "true")
        self.secure = (
            self._parse_bool(raw_secure)
            if secure is None
            else secure
        )

        configured_algorithm = os.getenv(
            "CLOUDINARY_SIGNATURE_ALGORITHM",
            "sha1",
        )
        self.signature_algorithm = (
            signature_algorithm or configured_algorithm
        ).strip().lower()

        self._validate_configuration()
        self._configure_sdk()

    @classmethod
    def from_environment(cls) -> "CloudinaryService":
        """Build the service using backend environment variables."""
        return cls()

    def is_configured(self) -> bool:
        """Return whether all required Cloudinary credentials exist."""
        return bool(
            self.cloud_name
            and self.api_key
            and self.api_secret
        )

    def generate_upload_signature(
        self,
        *,
        organization_id: str,
        media_type: str,
        entity_id: str,
        resource_type: str = "image",
        public_id: str | None = None,
        timestamp: int | None = None,
    ) -> CloudinaryUploadSignature:
        """Generate signed direct-upload parameters for a FoodSense asset."""
        organization_id = self._validate_identifier(
            organization_id,
            "organization_id",
        )
        entity_id = self._validate_identifier(entity_id, "entity_id")
        media_type = self._validate_media_type(media_type)
        resource_type = self._validate_resource_type(resource_type)

        if public_id is None:
            public_id = entity_id
        else:
            public_id = self._validate_public_id(public_id)

        upload_timestamp = (
            int(time.time()) if timestamp is None else int(timestamp)
        )

        asset_folder = (
            f"foodsense/{organization_id}/{media_type}/{entity_id}"
        )

        params_to_sign: dict[str, Any] = {
            "asset_folder": asset_folder,
            "public_id": public_id,
            "timestamp": upload_timestamp,
        }

        signature = utils.api_sign_request(
            params_to_sign,
            self.api_secret,
        )

        return CloudinaryUploadSignature(
            cloud_name=self.cloud_name,
            api_key=self.api_key,
            timestamp=upload_timestamp,
            signature=signature,
            asset_folder=asset_folder,
            public_id=public_id,
            resource_type=resource_type,
        )

    def generate_upload_signature_for_food_record(
        self,
        *,
        organization_id: str,
        record_id: str,
        timestamp: int | None = None,
    ) -> CloudinaryUploadSignature:
        """Generate a signed image upload for a food record."""
        return self.generate_upload_signature(
            organization_id=organization_id,
            media_type="food_records",
            entity_id=record_id,
            resource_type="image",
            timestamp=timestamp,
        )

    def generate_upload_signature_for_inventory(
        self,
        *,
        organization_id: str,
        item_id: str,
        timestamp: int | None = None,
    ) -> CloudinaryUploadSignature:
        """Generate a signed image upload for an inventory item."""
        return self.generate_upload_signature(
            organization_id=organization_id,
            media_type="inventory",
            entity_id=item_id,
            resource_type="image",
            timestamp=timestamp,
        )

    def generate_upload_signature_for_surplus(
        self,
        *,
        organization_id: str,
        surplus_id: str,
        timestamp: int | None = None,
    ) -> CloudinaryUploadSignature:
        """Generate a signed image upload for surplus evidence."""
        return self.generate_upload_signature(
            organization_id=organization_id,
            media_type="surplus",
            entity_id=surplus_id,
            resource_type="image",
            timestamp=timestamp,
        )

    def build_delivery_url(
        self,
        *,
        public_id: str,
        resource_type: str = "image",
        transformation: str | None = None,
        format: str | None = None,
    ) -> str:
        """Build a secure Cloudinary delivery URL from a public ID."""
        public_id = self._validate_public_id(public_id)
        resource_type = self._validate_resource_type(resource_type)

        resource = cloudinary.CloudinaryResource(
            public_id,
            resource_type=resource_type,
            type="upload",
        )

        options: dict[str, Any] = {"secure": self.secure}

        if transformation:
            options["transformation"] = transformation

        if format:
            options["format"] = format

        return resource.build_url(**options)

    def delete_asset(
        self,
        *,
        public_id: str,
        resource_type: str = "image",
        invalidate: bool = True,
    ) -> dict[str, Any]:
        """Delete a Cloudinary asset from the backend."""
        public_id = self._validate_public_id(public_id)
        resource_type = self._validate_resource_type(resource_type)

        from cloudinary import uploader

        result = uploader.destroy(
            public_id,
            resource_type=resource_type,
            type="upload",
            invalidate=invalidate,
        )

        return dict(result)

    def _configure_sdk(self) -> None:
        cloudinary.config(
            cloud_name=self.cloud_name,
            api_key=self.api_key,
            api_secret=self.api_secret,
            secure=self.secure,
            signature_algorithm=self.signature_algorithm,
        )

    def _validate_configuration(self) -> None:
        missing: list[str] = []

        if not self.cloud_name:
            missing.append("CLOUDINARY_CLOUD_NAME")
        if not self.api_key:
            missing.append("CLOUDINARY_API_KEY")
        if not self.api_secret:
            missing.append("CLOUDINARY_API_SECRET")

        if missing:
            raise CloudinaryConfigurationError(
                "Cloudinary configuration is incomplete. Missing environment "
                "variables: " + ", ".join(missing)
            )

        if self.signature_algorithm not in {"sha1", "sha256"}:
            raise CloudinaryConfigurationError(
                "CLOUDINARY_SIGNATURE_ALGORITHM must be 'sha1' or 'sha256'."
            )

    @classmethod
    def _validate_identifier(cls, value: str, field_name: str) -> str:
        normalized = value.strip()

        if not normalized or not cls._IDENTIFIER_PATTERN.fullmatch(normalized):
            raise CloudinaryValidationError(
                f"{field_name} must contain only letters, numbers, "
                "hyphens, or underscores and be 1-100 characters long."
            )

        return normalized

    @classmethod
    def _validate_media_type(cls, media_type: str) -> str:
        normalized = media_type.strip().lower()

        if normalized not in cls._MEDIA_TYPES:
            allowed = ", ".join(sorted(cls._MEDIA_TYPES))
            raise CloudinaryValidationError(
                f"media_type must be one of: {allowed}."
            )

        return normalized

    @classmethod
    def _validate_resource_type(cls, resource_type: str) -> str:
        normalized = resource_type.strip().lower()

        if normalized not in cls._RESOURCE_TYPES:
            allowed = ", ".join(sorted(cls._RESOURCE_TYPES))
            raise CloudinaryValidationError(
                f"resource_type must be one of: {allowed}."
            )

        return normalized

    @staticmethod
    def _validate_public_id(public_id: str) -> str:
        normalized = public_id.strip().strip("/")

        if not normalized or len(normalized) > 255:
            raise CloudinaryValidationError(
                "public_id must be between 1 and 255 characters."
            )

        if any(char in normalized for char in "?&#\\%<>+"):
            raise CloudinaryValidationError(
                "public_id contains unsupported characters."
            )

        if normalized.endswith(" "):
            raise CloudinaryValidationError(
                "public_id cannot end with a space."
            )

        return normalized

    @staticmethod
    def _parse_bool(value: str) -> bool:
        normalized = value.strip().lower()

        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False

        raise CloudinaryConfigurationError(
            "CLOUDINARY_SECURE must be a boolean value."
        )


__all__ = [
    "CloudinaryConfigurationError",
    "CloudinaryService",
    "CloudinaryUploadSignature",
    "CloudinaryValidationError",
]
