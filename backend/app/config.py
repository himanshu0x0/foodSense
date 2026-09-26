"""Central configuration for the FoodSense backend.

Configuration is loaded from environment variables and an optional local
backend/.env file. Secrets are never stored directly in application source
code.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Tuple

from dotenv import load_dotenv


# Load backend/.env before Settings is created so all environment-backed
# configuration is available during module initialization.
_BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ENV_FILE = os.path.join(_BACKEND_DIR, ".env")
load_dotenv(_ENV_FILE)


def _env_bool(name: str, default: bool) -> bool:
    """Read a boolean environment variable safely."""
    value = os.getenv(name)

    if value is None:
        return default

    return value.strip().lower() in {
        "1",
        "true",
        "yes",
        "y",
        "on",
    }


def _env_int(name: str, default: int) -> int:
    """Read an integer environment variable with a safe fallback."""
    value = os.getenv(name)

    if value is None or not value.strip():
        return default

    try:
        return int(value)
    except ValueError as exc:
        raise ValueError(
            f"Environment variable {name!r} must be an integer."
        ) from exc


def _env_float(name: str, default: float) -> float:
    """Read a floating-point environment variable with a safe fallback."""
    value = os.getenv(name)

    if value is None or not value.strip():
        return default

    try:
        return float(value)
    except ValueError as exc:
        raise ValueError(
            f"Environment variable {name!r} must be a number."
        ) from exc


def _env_list(name: str, default: Tuple[str, ...]) -> Tuple[str, ...]:
    """Read a comma-separated environment variable."""
    value = os.getenv(name)

    if value is None:
        return default

    items = tuple(
        item.strip()
        for item in value.split(",")
        if item.strip()
    )

    return items or default


@dataclass(frozen=True, slots=True)
class Settings:
    """Application settings used by the FoodSense backend."""

    app_name: str = "FoodSense API"
    app_version: str = "0.1.0"
    environment: str = "development"
    debug: bool = True

    host: str = "127.0.0.1"
    port: int = 8000

    allowed_origins: Tuple[str, ...] = ("*",)

    firebase_project_id: str = ""
    firebase_credentials_path: str = ""

    default_forecast_horizon_days: int = 1
    minimum_training_records: int = 30
    default_safety_buffer_percent: float = 5.0

    model_directory: str = "models"

    log_level: str = "INFO"

    @classmethod
    def from_environment(cls) -> "Settings":
        """Build settings from environment variables."""
        return cls(
            app_name=os.getenv("FOODSENSE_APP_NAME", "FoodSense API"),
            app_version=os.getenv("FOODSENSE_API_VERSION", "0.1.0"),
            environment=os.getenv("FOODSENSE_ENV", "development"),
            debug=_env_bool("FOODSENSE_DEBUG", True),
            host=os.getenv("FOODSENSE_HOST", "127.0.0.1"),
            port=_env_int("FOODSENSE_PORT", 8000),
            allowed_origins=_env_list(
                "FOODSENSE_ALLOWED_ORIGINS",
                ("*",),
            ),
            firebase_project_id=os.getenv(
                "FOODSENSE_FIREBASE_PROJECT_ID",
                "",
            ),
            firebase_credentials_path=os.getenv(
                "GOOGLE_APPLICATION_CREDENTIALS",
                os.getenv(
                    "FOODSENSE_FIREBASE_CREDENTIALS",
                    "",
                ),
            ),
            default_forecast_horizon_days=_env_int(
                "FOODSENSE_FORECAST_HORIZON_DAYS",
                1,
            ),
            minimum_training_records=_env_int(
                "FOODSENSE_MIN_TRAINING_RECORDS",
                30,
            ),
            default_safety_buffer_percent=_env_float(
                "FOODSENSE_SAFETY_BUFFER_PERCENT",
                5.0,
            ),
            model_directory=os.getenv(
                "FOODSENSE_MODEL_DIRECTORY",
                "models",
            ),
            log_level=os.getenv(
                "FOODSENSE_LOG_LEVEL",
                "INFO",
            ).upper(),
        )

    def validate(self) -> None:
        """Validate settings that would make the API unsafe or unusable."""
        if self.port < 1 or self.port > 65535:
            raise ValueError(
                "FOODSENSE_PORT must be between 1 and 65535."
            )

        if self.default_forecast_horizon_days < 1:
            raise ValueError(
                "FOODSENSE_FORECAST_HORIZON_DAYS must be at least 1."
            )

        if self.minimum_training_records < 1:
            raise ValueError(
                "FOODSENSE_MIN_TRAINING_RECORDS must be at least 1."
            )

        if self.default_safety_buffer_percent < 0:
            raise ValueError(
                "FOODSENSE_SAFETY_BUFFER_PERCENT cannot be negative."
            )

        if not self.log_level:
            raise ValueError(
                "FOODSENSE_LOG_LEVEL cannot be empty."
            )

    @property
    def is_production(self) -> bool:
        """Whether the backend is running in production."""
        return self.environment.lower() == "production"

    @property
    def cors_allows_all(self) -> bool:
        """Whether CORS is configured with a wildcard origin."""
        return self.allowed_origins == ("*",)


settings = Settings.from_environment()
settings.validate()
