"""Pydantic schemas for FoodSense demand forecasting APIs.

These schemas define the public contract between the Flutter client and the
FastAPI backend. They contain validation only; forecasting logic belongs in
the service layer.
"""

from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


MealType = Literal[
    "Breakfast",
    "Lunch",
    "Dinner",
    "Snack",
    "Other",
]


class ForecastRequest(BaseModel):
    """Input required to generate a demand forecast."""

    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
    )

    organization_id: str = Field(
        ...,
        min_length=1,
        max_length=128,
        description="Firestore organization ID.",
    )
    forecast_date: date = Field(
        ...,
        description="Date for which demand should be forecast.",
    )
    meal_type: MealType = Field(
        ...,
        description="Meal category being forecast.",
    )
    expected_people: int = Field(
        ...,
        ge=0,
        le=1_000_000,
        description="Expected number of people for the meal.",
    )
    special_event: bool = Field(
        default=False,
        description="Whether the forecast date has unusual demand conditions.",
    )
    menu: str | None = Field(
        default=None,
        max_length=500,
        description="Optional menu description.",
    )

    @field_validator("organization_id")
    @classmethod
    def validate_organization_id(cls, value: str) -> str:
        """Reject IDs that are only whitespace."""
        value = value.strip()

        if not value:
            raise ValueError("organization_id cannot be empty.")

        return value

    @field_validator("menu")
    @classmethod
    def normalize_menu(cls, value: str | None) -> str | None:
        """Normalize an optional menu description."""
        if value is None:
            return None

        value = value.strip()

        return value or None


class ForecastResponse(BaseModel):
    """Result returned after generating a demand forecast."""

    model_config = ConfigDict(
        extra="forbid",
    )

    organization_id: str
    forecast_date: date
    meal_type: MealType
    expected_people: int = Field(ge=0)

    predicted_demand: int = Field(
        ge=0,
        description="Predicted meals likely to be consumed.",
    )
    safety_buffer: int = Field(
        ge=0,
        description="Additional meals recommended to absorb forecast uncertainty.",
    )
    recommended_production: int = Field(
        ge=0,
        description="Suggested number of meals to prepare.",
    )

    safety_buffer_percent: float = Field(
        ge=0,
        description="Safety buffer represented as a percentage.",
    )

    confidence: float | None = Field(
        default=None,
        ge=0,
        le=1,
        description="Model confidence score when available.",
    )

    method: str = Field(
        min_length=1,
        max_length=100,
        description="Forecasting method used.",
    )

    training_records: int = Field(
        ge=0,
        description="Number of historical records used by the forecasting service.",
    )

    fallback_used: bool = Field(
        default=False,
        description="Whether a baseline/fallback method was used.",
    )

    generated_at: str = Field(
        min_length=1,
        description="UTC timestamp when the forecast was generated.",
    )


class HistoricalRecord(BaseModel):
    """Normalized historical data point used by the forecasting service."""

    model_config = ConfigDict(
        extra="forbid",
    )

    record_date: date
    meal_type: MealType

    expected_people: int = Field(
        ge=0,
    )
    actual_people: int = Field(
        ge=0,
    )
    meals_prepared: int = Field(
        ge=0,
    )
    meals_consumed: int = Field(
        ge=0,
    )
    meals_remaining: int = Field(
        ge=0,
    )
    waste_kg: float = Field(
        ge=0,
    )
    special_event: bool = False

    @field_validator("actual_people")
    @classmethod
    def validate_actual_people(
        cls,
        value: int,
    ) -> int:
        return value

    @field_validator("meals_consumed")
    @classmethod
    def validate_meals_consumed(
        cls,
        value: int,
    ) -> int:
        return value


class ForecastDataRequest(BaseModel):
    """Request for preparing historical data for a forecast."""

    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
    )

    organization_id: str = Field(
        ...,
        min_length=1,
        max_length=128,
    )
    meal_type: MealType | None = None
    start_date: date | None = None
    end_date: date | None = None
    limit: int = Field(
        default=500,
        ge=1,
        le=5000,
    )

    @field_validator("organization_id")
    @classmethod
    def validate_organization_id(cls, value: str) -> str:
        value = value.strip()

        if not value:
            raise ValueError("organization_id cannot be empty.")

        return value


class ForecastFeatureSummary(BaseModel):
    """Summary of features available to a forecasting request."""

    model_config = ConfigDict(
        extra="forbid",
    )

    historical_records: int = Field(ge=0)
    average_consumption: float = Field(ge=0)
    average_waste_kg: float = Field(ge=0)
    average_expected_people: float = Field(ge=0)
    average_prepared_meals: float = Field(ge=0)
    special_event_records: int = Field(ge=0)
    weekdays_observed: int = Field(ge=0, le=7)
