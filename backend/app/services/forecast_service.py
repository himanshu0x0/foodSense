"""Baseline demand-forecasting service for FoodSense.

Phase 2 begins with a transparent, deterministic forecasting baseline instead
of jumping directly to a complex ML model.

The service uses historical consumption and attendance relationships to
estimate future demand, then adds a configurable safety buffer to produce a
recommended production quantity.

This implementation is intentionally replaceable. A trained XGBoost,
Gradient Boosting, or another validated model can later implement the same
service contract without changing the API layer.
"""

from __future__ import annotations

import math
from datetime import date, timedelta
from typing import Sequence

from ..config import Settings, settings
from ..schemas.forecast_schema import (
    ForecastRequest,
    ForecastResponse,
    HistoricalRecord,
)
from .data_service import HistoricalDataService


class ForecastService:
    """Generate FoodSense demand forecasts from historical food records."""

    def __init__(
        self,
        data_service: HistoricalDataService,
        app_settings: Settings = settings,
    ) -> None:
        self._data_service = data_service
        self._settings = app_settings

    def forecast(self, request: ForecastRequest) -> ForecastResponse:
        """Generate one forecast for a requested organization/date/meal."""
        self._validate_request_date(request)

        historical_records = self._load_historical_records(request)

        valid_records = self._data_service.filter_valid_training_records(
            historical_records
        )

        if not valid_records:
            return self._fallback_response(request)

        predicted_demand, method = self._predict_demand(
            request,
            valid_records,
        )

        safety_buffer = self._calculate_safety_buffer(
            predicted_demand
        )

        recommended_production = predicted_demand + safety_buffer

        return ForecastResponse(
            organization_id=request.organization_id,
            forecast_date=request.forecast_date,
            meal_type=request.meal_type,
            expected_people=request.expected_people,
            predicted_demand=predicted_demand,
            safety_buffer=safety_buffer,
            recommended_production=recommended_production,
            safety_buffer_percent=self._settings.default_safety_buffer_percent,
            confidence=None,
            method=method,
            training_records=len(valid_records),
            fallback_used=False,
            generated_at=self._utc_now_iso(),
        )

    def _load_historical_records(
        self,
        request: ForecastRequest,
    ) -> list[HistoricalRecord]:
        """Load only records available before the forecast date.

        The forecast must never use future records, which would introduce
        target leakage during later model development.
        """
        end_date = request.forecast_date - timedelta(days=1)

        # A bounded history window keeps development/testing predictable and
        # avoids unnecessarily large Firestore reads.
        history_days = 180
        start_date = request.forecast_date - timedelta(days=history_days)

        return self._data_service.fetch_records(
            organization_id=request.organization_id,
            meal_type=request.meal_type,
            start_date=start_date,
            end_date=end_date,
            limit=500,
        )

    def _predict_demand(
        self,
        request: ForecastRequest,
        records: Sequence[HistoricalRecord],
    ) -> tuple[int, str]:
        """Estimate consumed meals using recent historical behavior."""
        if not records:
            return self._fallback_prediction(request), "fallback_expected_people"

        # For special-event forecasts, prefer historical special-event
        # observations when enough comparable observations exist.
        comparable_records = list(records)

        if request.special_event:
            event_records = [
                record
                for record in records
                if record.special_event
            ]

            if len(event_records) >= 3:
                comparable_records = event_records

        comparable_records = sorted(
            comparable_records,
            key=lambda record: record.record_date,
        )

        weighted_consumption = self._weighted_average_consumption(
            comparable_records
        )
        weighted_rate = self._weighted_consumption_rate(
            comparable_records
        )

        rate_based_prediction = (
            request.expected_people * weighted_rate
        )

        # Blend direct consumption history with attendance-adjusted demand.
        # This produces a stable baseline while still reacting to changes in
        # expected attendance.
        blended_prediction = (
            (0.4 * weighted_consumption)
            + (0.6 * rate_based_prediction)
        )

        if blended_prediction <= 0:
            return self._fallback_prediction(request), "fallback_expected_people"

        predicted = self._round_non_negative(blended_prediction)

        return predicted, (
            "recency_weighted_baseline"
            if len(records) >= self._settings.minimum_training_records
            else "recency_weighted_baseline_low_history"
        )

    def _weighted_average_consumption(
        self,
        records: Sequence[HistoricalRecord],
    ) -> float:
        """Calculate a recency-weighted average of consumed meals."""
        if not records:
            return 0.0

        total_weight = 0.0
        weighted_sum = 0.0

        for index, record in enumerate(records, start=1):
            # More recent records receive larger weights.
            weight = float(index)
            weighted_sum += record.meals_consumed * weight
            total_weight += weight

        return weighted_sum / total_weight if total_weight else 0.0

    def _weighted_consumption_rate(
        self,
        records: Sequence[HistoricalRecord],
    ) -> float:
        """Calculate the weighted historical meal-consumption rate."""
        if not records:
            return 0.0

        total_weight = 0.0
        weighted_rate = 0.0

        for index, record in enumerate(records, start=1):
            # Actual attendance is the preferred denominator. When it is not
            # available, expected attendance is used as a conservative proxy.
            attendance = (
                record.actual_people
                if record.actual_people > 0
                else record.expected_people
            )

            if attendance <= 0:
                continue

            rate = min(
                max(record.meals_consumed / attendance, 0.0),
                1.5,
            )

            weight = float(index)
            weighted_rate += rate * weight
            total_weight += weight

        if total_weight == 0:
            return 0.0

        return weighted_rate / total_weight

    def _calculate_safety_buffer(self, predicted_demand: int) -> int:
        """Convert the configured safety-buffer percentage into meals."""
        percentage = self._settings.default_safety_buffer_percent

        if predicted_demand <= 0 or percentage <= 0:
            return 0

        return max(
            0,
            math.ceil(predicted_demand * percentage / 100.0),
        )

    def _fallback_prediction(
        self,
        request: ForecastRequest,
    ) -> int:
        """Provide a deterministic cold-start prediction."""
        # During cold start there is no historical signal. Expected attendance
        # is therefore used as the transparent baseline rather than inventing
        # an unsupported learned estimate.
        return max(request.expected_people, 0)

    def _fallback_response(
        self,
        request: ForecastRequest,
    ) -> ForecastResponse:
        """Build a forecast response when no historical records exist."""
        predicted_demand = self._fallback_prediction(request)
        safety_buffer = self._calculate_safety_buffer(
            predicted_demand
        )
        recommended_production = predicted_demand + safety_buffer

        return ForecastResponse(
            organization_id=request.organization_id,
            forecast_date=request.forecast_date,
            meal_type=request.meal_type,
            expected_people=request.expected_people,
            predicted_demand=predicted_demand,
            safety_buffer=safety_buffer,
            recommended_production=recommended_production,
            safety_buffer_percent=self._settings.default_safety_buffer_percent,
            confidence=None,
            method="fallback_expected_people",
            training_records=0,
            fallback_used=True,
            generated_at=self._utc_now_iso(),
        )

    @staticmethod
    def _round_non_negative(value: float) -> int:
        """Round a prediction to a non-negative whole meal count."""
        if not math.isfinite(value):
            return 0

        return max(0, int(round(value)))

    @staticmethod
    def _utc_now_iso() -> str:
        """Return a UTC ISO-8601 timestamp."""
        from datetime import datetime, timezone

        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _validate_request_date(request: ForecastRequest) -> None:
        """Reject forecast requests dated in the past."""
        today = date.today()

        if request.forecast_date < today:
            raise ValueError(
                "forecast_date cannot be earlier than today."
            )
