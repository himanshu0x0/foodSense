"""Surplus prediction service for FoodSense.

Phase 2 AI capability:
    demand forecast -> planned production -> predicted surplus -> risk

This service deliberately reuses the existing ForecastService instead of
implementing a second demand model. That keeps demand prediction as the
single source of truth and lets surplus prediction focus on the operational
difference between production and predicted consumption.
"""

from __future__ import annotations

import math
from datetime import datetime, timezone
from typing import Sequence

from ..config import Settings, settings
from ..schemas.forecast_schema import ForecastRequest, HistoricalRecord
from ..schemas.surplus_schema import (
    SurplusRequest,
    SurplusResponse,
    SurplusScenario,
    SurplusScenarioRequest,
)
from .data_service import HistoricalDataService
from .forecast_service import ForecastService


class SurplusService:
    """Estimate food surplus from forecasted demand and production plans."""

    def __init__(
        self,
        data_service: HistoricalDataService,
        forecast_service: ForecastService,
        app_settings: Settings = settings,
    ) -> None:
        self._data_service = data_service
        self._forecast_service = forecast_service
        self._settings = app_settings

    def predict(self, request: SurplusRequest) -> SurplusResponse:
        """Generate a predicted surplus result."""
        self._validate_request(request)

        forecast = self._forecast_service.forecast(
            ForecastRequest(
                organization_id=request.organization_id,
                forecast_date=request.prediction_date,
                meal_type=request.meal_type,
                expected_people=request.expected_people,
                special_event=request.special_event,
                menu=None,
            )
        )

        historical_records = self._load_historical_records(request)

        predicted_surplus = max(
            request.planned_production - forecast.predicted_demand,
            0,
        )

        surplus_percent = self._calculate_surplus_percent(
            predicted_surplus=predicted_surplus,
            planned_production=request.planned_production,
        )

        surplus_risk = self._classify_surplus_risk(
            surplus_percent=surplus_percent,
            predicted_surplus=predicted_surplus,
        )

        estimated_waste_kg = self._estimate_waste_kg(
            predicted_surplus=predicted_surplus,
            historical_records=historical_records,
        )

        method = (
            "forecast_based_surplus"
            if not forecast.fallback_used
            else "forecast_fallback_surplus"
        )

        return SurplusResponse(
            organization_id=request.organization_id,
            prediction_date=request.prediction_date,
            meal_type=request.meal_type,
            expected_people=request.expected_people,
            planned_production=request.planned_production,
            predicted_demand=forecast.predicted_demand,
            predicted_surplus=predicted_surplus,
            surplus_percent=surplus_percent,
            surplus_risk=surplus_risk,
            estimated_waste_kg=estimated_waste_kg,
            method=method,
            training_records=forecast.training_records,
            fallback_used=forecast.fallback_used,
            generated_at=self._utc_now_iso(),
        )

    def compare_scenarios(
        self,
        request: SurplusScenarioRequest,
    ) -> list[SurplusScenario]:
        """Compare several production quantities for the same forecast."""
        self._validate_request(request)

        forecast = self._forecast_service.forecast(
            ForecastRequest(
                organization_id=request.organization_id,
                forecast_date=request.prediction_date,
                meal_type=request.meal_type,
                expected_people=request.expected_people,
                special_event=request.special_event,
                menu=None,
            )
        )

        return [
            self._build_scenario(
                planned_production=production,
                predicted_demand=forecast.predicted_demand,
            )
            for production in request.production_steps
        ]

    def analyze_historical_surplus(
        self,
        *,
        organization_id: str,
        meal_type: str | None = None,
        days: int = 90,
    ) -> dict[str, float | int]:
        """Summarize historical production surplus for analytics.

        This is a Phase 2 analytics helper. It does not replace the future
        waste-analysis service.
        """
        if days < 1 or days > 365:
            raise ValueError("days must be between 1 and 365.")

        from datetime import date, timedelta

        end_date = date.today() - timedelta(days=1)
        start_date = end_date - timedelta(days=days - 1)

        records = self._data_service.fetch_records(
            organization_id=organization_id,
            meal_type=meal_type,  # type: ignore[arg-type]
            start_date=start_date,
            end_date=end_date,
            limit=5000,
        )

        total_prepared = sum(record.meals_prepared for record in records)
        total_consumed = sum(record.meals_consumed for record in records)
        total_remaining = sum(record.meals_remaining for record in records)

        average_surplus_percent = (
            (total_remaining / total_prepared) * 100
            if total_prepared > 0
            else 0.0
        )

        return {
            "records": len(records),
            "total_prepared": total_prepared,
            "total_consumed": total_consumed,
            "total_remaining": total_remaining,
            "average_surplus_percent": round(
                average_surplus_percent,
                2,
            ),
        }

    def _load_historical_records(
        self,
        request: SurplusRequest,
    ) -> list[HistoricalRecord]:
        """Load historical records for waste-per-surplus estimation."""
        from datetime import date, timedelta

        end_date = request.prediction_date - timedelta(days=1)
        start_date = request.prediction_date - timedelta(days=180)

        return self._data_service.fetch_records(
            organization_id=request.organization_id,
            meal_type=request.meal_type,
            start_date=start_date,
            end_date=end_date,
            limit=500,
        )

    def _estimate_waste_kg(
        self,
        *,
        predicted_surplus: int,
        historical_records: Sequence[HistoricalRecord],
    ) -> float:
        """Estimate waste mass associated with predicted surplus.

        Where historical data exists, use the observed ratio:

            waste_kg / meals_remaining

        This keeps the estimate organization/meal specific instead of using
        an arbitrary fixed waste amount.

        With no usable historical ratio, the method returns zero rather than
        pretending to know a weight that the data cannot support.
        """
        if predicted_surplus <= 0:
            return 0.0

        ratios: list[float] = []

        for record in historical_records:
            if record.meals_remaining <= 0 or record.waste_kg <= 0:
                continue

            ratio = record.waste_kg / record.meals_remaining

            if math.isfinite(ratio) and ratio >= 0:
                ratios.append(ratio)

        if not ratios:
            return 0.0

        ratios.sort()

        # Use a median to reduce the influence of unusually large waste days.
        midpoint = len(ratios) // 2

        if len(ratios) % 2 == 0:
            median_ratio = (
                ratios[midpoint - 1] + ratios[midpoint]
            ) / 2
        else:
            median_ratio = ratios[midpoint]

        return round(
            max(0.0, predicted_surplus * median_ratio),
            2,
        )

    def _build_scenario(
        self,
        *,
        planned_production: int,
        predicted_demand: int,
    ) -> SurplusScenario:
        predicted_surplus = max(
            planned_production - predicted_demand,
            0,
        )

        surplus_percent = self._calculate_surplus_percent(
            predicted_surplus=predicted_surplus,
            planned_production=planned_production,
        )

        return SurplusScenario(
            planned_production=planned_production,
            predicted_demand=predicted_demand,
            predicted_surplus=predicted_surplus,
            surplus_percent=surplus_percent,
            surplus_risk=self._classify_surplus_risk(
                surplus_percent=surplus_percent,
                predicted_surplus=predicted_surplus,
            ),
        )

    @staticmethod
    def _calculate_surplus_percent(
        *,
        predicted_surplus: int,
        planned_production: int,
    ) -> float:
        """Calculate predicted surplus as a percentage of production."""
        if planned_production <= 0:
            return 0.0

        return round(
            (predicted_surplus / planned_production) * 100,
            2,
        )

    @staticmethod
    def _classify_surplus_risk(
        *,
        surplus_percent: float,
        predicted_surplus: int,
    ) -> str:
        """Classify predicted surplus using transparent thresholds.

        Thresholds:
        - none: no predicted surplus
        - low: >0% to <5%
        - medium: 5% to <15%
        - high: >=15%
        """
        if predicted_surplus <= 0:
            return "none"

        if surplus_percent < 5:
            return "low"

        if surplus_percent < 15:
            return "medium"

        return "high"

    @staticmethod
    def _validate_request(request: SurplusRequest) -> None:
        """Validate operational constraints not covered by the schema."""
        if request.prediction_date < datetime.now().date():
            raise ValueError(
                "prediction_date cannot be earlier than today."
            )

        if request.planned_production < 0:
            raise ValueError(
                "planned_production cannot be negative."
            )

    @staticmethod
    def _utc_now_iso() -> str:
        """Return the current UTC timestamp."""
        return datetime.now(timezone.utc).isoformat()
