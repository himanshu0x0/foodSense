"""Pydantic schemas for FoodSense surplus prediction.

Surplus prediction estimates food likely to remain after a planned meal
service. It is intentionally separated from demand forecasting:

    Demand prediction
        -> expected consumption

    Surplus prediction
        -> planned/current production - expected consumption

This module defines request/response contracts only. Calculation logic belongs
in services/surplus_service.py.
"""

from __future__ import annotations

from datetime import date

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .forecast_schema import MealType


class SurplusRequest(BaseModel):
    """Input used to estimate expected meal surplus."""

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

    prediction_date: date = Field(
        ...,
        description="Date for which surplus should be estimated.",
    )

    meal_type: MealType = Field(
        ...,
        description="Meal category.",
    )

    planned_production: int = Field(
        ...,
        ge=0,
        le=1_000_000,
        description="Number of meals planned/prepared.",
    )

    expected_people: int = Field(
        ...,
        ge=0,
        le=1_000_000,
        description="Expected people for the meal.",
    )

    special_event: bool = Field(
        default=False,
        description="Whether unusual demand conditions are expected.",
    )

    @field_validator("organization_id")
    @classmethod
    def validate_organization_id(cls, value: str) -> str:
        """Reject empty organization IDs."""
        value = value.strip()

        if not value:
            raise ValueError(
                "organization_id cannot be empty."
            )

        return value


class SurplusResponse(BaseModel):
    """Predicted meal surplus result."""

    model_config = ConfigDict(
        extra="forbid",
    )

    organization_id: str
    prediction_date: date
    meal_type: MealType

    expected_people: int = Field(
        ge=0,
    )

    planned_production: int = Field(
        ge=0,
    )

    predicted_demand: int = Field(
        ge=0,
        description="Predicted meals likely to be consumed.",
    )

    predicted_surplus: int = Field(
        ge=0,
        description="Estimated meals remaining after predicted consumption.",
    )

    surplus_percent: float = Field(
        ge=0,
        description="Predicted surplus as a percentage of planned production.",
    )

    surplus_risk: str = Field(
        min_length=1,
        description="Human-readable surplus risk category.",
    )

    estimated_waste_kg: float = Field(
        ge=0,
        description="Approximate waste mass associated with predicted surplus.",
    )

    method: str = Field(
        min_length=1,
        max_length=100,
        description="Method used to estimate surplus.",
    )

    training_records: int = Field(
        ge=0,
        description="Historical records supporting the estimate.",
    )

    fallback_used: bool = Field(
        default=False,
        description="Whether a fallback demand estimate was used.",
    )

    generated_at: str = Field(
        min_length=1,
        description="UTC timestamp when the result was generated.",
    )


class SurplusScenario(BaseModel):
    """Scenario result for comparing different production plans."""

    model_config = ConfigDict(
        extra="forbid",
    )

    planned_production: int = Field(
        ge=0,
    )

    predicted_demand: int = Field(
        ge=0,
    )

    predicted_surplus: int = Field(
        ge=0,
    )

    surplus_percent: float = Field(
        ge=0,
    )

    surplus_risk: str = Field(
        min_length=1,
    )


class SurplusScenarioRequest(SurplusRequest):
    """Request for evaluating multiple production scenarios."""

    production_steps: list[int] = Field(
        ...,
        min_length=1,
        max_length=10,
        description="Alternative production quantities to compare.",
    )

    @field_validator("production_steps")
    @classmethod
    def validate_production_steps(
        cls,
        value: list[int],
    ) -> list[int]:
        """Validate and normalize scenario quantities."""
        normalized = sorted(set(value))

        if any(quantity < 0 for quantity in normalized):
            raise ValueError(
                "Production quantities cannot be negative."
            )

        if any(quantity > 1_000_000 for quantity in normalized):
            raise ValueError(
                "Production quantities cannot exceed 1,000,000."
            )

        if not normalized:
            raise ValueError(
                "At least one production scenario is required."
            )

        return normalized
