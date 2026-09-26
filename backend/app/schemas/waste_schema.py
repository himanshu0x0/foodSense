"""Pydantic schemas for FoodSense waste analysis.

Waste analysis is the third Phase 2 AI capability:

    historical food records
        -> waste metrics
        -> waste rate
        -> excess production indicators
        -> trend/insights

This module contains API contracts and validation only. Calculation logic
belongs in services/waste_service.py.
"""

from __future__ import annotations

from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .forecast_schema import MealType


WasteTrend = Literal[
    "improving",
    "stable",
    "worsening",
    "insufficient_data",
]


class WasteAnalysisRequest(BaseModel):
    """Request for analyzing historical food waste."""

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

    start_date: date = Field(
        ...,
        description="First date included in the analysis.",
    )

    end_date: date = Field(
        ...,
        description="Last date included in the analysis.",
    )

    meal_type: MealType | None = Field(
        default=None,
        description="Optional meal-type filter.",
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

    @field_validator("end_date")
    @classmethod
    def validate_date_range(
        cls,
        value: date,
        info,
    ) -> date:
        """Ensure the analysis range is valid."""
        start_date = info.data.get("start_date")

        if start_date is not None and value < start_date:
            raise ValueError(
                "end_date cannot be earlier than start_date."
            )

        return value


class WasteAnalysisResponse(BaseModel):
    """Aggregated waste-analysis result."""

    model_config = ConfigDict(
        extra="forbid",
    )

    organization_id: str
    start_date: date
    end_date: date
    meal_type: MealType | None

    records_analyzed: int = Field(
        ge=0,
        description="Number of historical food records analyzed.",
    )

    total_meals_prepared: int = Field(
        ge=0,
    )

    total_meals_consumed: int = Field(
        ge=0,
    )

    total_meals_remaining: int = Field(
        ge=0,
    )

    total_waste_kg: float = Field(
        ge=0,
    )

    average_daily_waste_kg: float = Field(
        ge=0,
    )

    waste_rate_percent: float = Field(
        ge=0,
        description="Waste mass relative to a normalized production scale.",
    )

    surplus_rate_percent: float = Field(
        ge=0,
        description="Remaining meals as a percentage of prepared meals.",
    )

    excess_production_meals: int = Field(
        ge=0,
        description="Meals prepared beyond historical consumption.",
    )

    average_waste_per_remaining_meal_kg: float = Field(
        ge=0,
        description="Average observed waste mass per remaining meal.",
    )

    trend: WasteTrend

    insight: str = Field(
        min_length=1,
        max_length=1000,
        description="Human-readable operational insight.",
    )

    recommendations: list[str] = Field(
        default_factory=list,
        max_length=10,
        description="Potential operational actions based on the analysis.",
    )

    method: str = Field(
        min_length=1,
        max_length=100,
        description="Analysis method used.",
    )

    generated_at: str = Field(
        min_length=1,
        description="UTC timestamp when the analysis was generated.",
    )


class WasteDailyMetric(BaseModel):
    """Waste metric for one calendar day."""

    model_config = ConfigDict(
        extra="forbid",
    )

    record_date: date

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

    waste_rate_percent: float = Field(
        ge=0,
    )

    surplus_rate_percent: float = Field(
        ge=0,
    )


class WasteTrendResponse(BaseModel):
    """Time-series waste analysis result."""

    model_config = ConfigDict(
        extra="forbid",
    )

    organization_id: str
    start_date: date
    end_date: date
    meal_type: MealType | None

    trend: WasteTrend

    daily_metrics: list[WasteDailyMetric] = Field(
        default_factory=list,
        max_length=500,
    )

    generated_at: str = Field(
        min_length=1,
    )


class WasteCategory(BaseModel):
    """Categorized waste contribution."""

    model_config = ConfigDict(
        extra="forbid",
    )

    category: str = Field(
        min_length=1,
        max_length=100,
    )

    waste_kg: float = Field(
        ge=0,
    )

    percentage_of_total: float = Field(
        ge=0,
        le=100,
    )


class WasteCategoryResponse(BaseModel):
    """Waste contribution breakdown."""

    model_config = ConfigDict(
        extra="forbid",
    )

    organization_id: str
    start_date: date
    end_date: date

    total_waste_kg: float = Field(
        ge=0,
    )

    categories: list[WasteCategory] = Field(
        default_factory=list,
        max_length=50,
    )

    generated_at: str = Field(
        min_length=1,
    )
