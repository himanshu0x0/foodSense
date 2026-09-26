"""Waste-analysis service for FoodSense.

Phase 2 AI capability:
    historical food records
        -> waste metrics
        -> surplus/excess-production indicators
        -> waste trend
        -> operational insights

The service is intentionally data-driven and transparent. It does not invent
waste categories that are not present in the current FoodSense food-record
schema.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from statistics import mean
from typing import Sequence

from ..schemas.forecast_schema import HistoricalRecord, MealType
from ..schemas.waste_schema import (
    WasteAnalysisRequest,
    WasteAnalysisResponse,
    WasteDailyMetric,
    WasteTrend,
    WasteTrendResponse,
)
from .data_service import HistoricalDataService


class WasteService:
    """Analyze historical food waste and operational surplus."""

    def __init__(
        self,
        data_service: HistoricalDataService,
    ) -> None:
        self._data_service = data_service

    def analyze(
        self,
        request: WasteAnalysisRequest,
    ) -> WasteAnalysisResponse:
        """Analyze waste for an organization and date range."""
        self._validate_request(request)

        records = self._load_records(request)

        return self._build_analysis_response(
            request=request,
            records=records,
        )

    def analyze_trend(
        self,
        request: WasteAnalysisRequest,
    ) -> WasteTrendResponse:
        """Build a daily waste time series for the requested period."""
        self._validate_request(request)

        records = self._load_records(request)

        daily_metrics = self._build_daily_metrics(records)
        trend = self._calculate_trend(daily_metrics)

        return WasteTrendResponse(
            organization_id=request.organization_id,
            start_date=request.start_date,
            end_date=request.end_date,
            meal_type=request.meal_type,
            trend=trend,
            daily_metrics=daily_metrics,
            generated_at=self._utc_now_iso(),
        )

    def analyze_records(
        self,
        records: Sequence[HistoricalRecord],
    ) -> dict[str, float | int]:
        """Analyze an already-loaded record collection.

        This helper is useful for unit tests and for future batch-processing
        jobs where Firestore access is handled outside the service.
        """
        total_prepared = sum(
            record.meals_prepared
            for record in records
        )
        total_consumed = sum(
            record.meals_consumed
            for record in records
        )
        total_remaining = sum(
            record.meals_remaining
            for record in records
        )
        total_waste_kg = sum(
            record.waste_kg
            for record in records
        )

        return self._calculate_metrics(
            records_count=len(records),
            total_prepared=total_prepared,
            total_consumed=total_consumed,
            total_remaining=total_remaining,
            total_waste_kg=total_waste_kg,
        )

    def _load_records(
        self,
        request: WasteAnalysisRequest,
    ) -> list[HistoricalRecord]:
        """Load organization-scoped historical records."""
        return self._data_service.fetch_records(
            organization_id=request.organization_id,
            meal_type=request.meal_type,
            start_date=request.start_date,
            end_date=request.end_date,
            limit=5000,
        )

    def _build_analysis_response(
        self,
        *,
        request: WasteAnalysisRequest,
        records: Sequence[HistoricalRecord],
    ) -> WasteAnalysisResponse:
        """Create the aggregate waste-analysis response."""
        metrics = self.analyze_records(records)

        daily_metrics = self._build_daily_metrics(records)
        trend = self._calculate_trend(daily_metrics)

        insight = self._build_insight(
            records_count=len(records),
            waste_rate_percent=float(
                metrics["waste_rate_percent"]
            ),
            surplus_rate_percent=float(
                metrics["surplus_rate_percent"]
            ),
            excess_production_meals=int(
                metrics["excess_production_meals"]
            ),
            average_daily_waste_kg=float(
                metrics["average_daily_waste_kg"]
            ),
            trend=trend,
        )

        recommendations = self._build_recommendations(
            waste_rate_percent=float(
                metrics["waste_rate_percent"]
            ),
            surplus_rate_percent=float(
                metrics["surplus_rate_percent"]
            ),
            excess_production_meals=int(
                metrics["excess_production_meals"]
            ),
            trend=trend,
        )

        return WasteAnalysisResponse(
            organization_id=request.organization_id,
            start_date=request.start_date,
            end_date=request.end_date,
            meal_type=request.meal_type,
            records_analyzed=len(records),
            total_meals_prepared=int(metrics["total_meals_prepared"]),
            total_meals_consumed=int(metrics["total_meals_consumed"]),
            total_meals_remaining=int(metrics["total_meals_remaining"]),
            total_waste_kg=float(metrics["total_waste_kg"]),
            average_daily_waste_kg=float(
                metrics["average_daily_waste_kg"]
            ),
            waste_rate_percent=float(
                metrics["waste_rate_percent"]
            ),
            surplus_rate_percent=float(
                metrics["surplus_rate_percent"]
            ),
            excess_production_meals=int(
                metrics["excess_production_meals"]
            ),
            average_waste_per_remaining_meal_kg=float(
                metrics["average_waste_per_remaining_meal_kg"]
            ),
            trend=trend,
            insight=insight,
            recommendations=recommendations,
            method="historical_food_record_analysis",
            generated_at=self._utc_now_iso(),
        )

    @staticmethod
    def _calculate_metrics(
        *,
        records_count: int,
        total_prepared: int,
        total_consumed: int,
        total_remaining: int,
        total_waste_kg: float,
    ) -> dict[str, float | int]:
        """Calculate aggregate operational waste metrics.

        `waste_rate_percent` uses waste kilograms divided by the number of
        prepared meals as a normalized operational indicator. It is not a
        physical percentage of food mass because the current schema does not
        store the mass of meals prepared.

        `surplus_rate_percent` is the actual meal-count surplus percentage.
        """
        average_daily_waste = (
            total_waste_kg / records_count
            if records_count > 0
            else 0.0
        )

        waste_rate_percent = (
            (total_waste_kg / total_prepared) * 100
            if total_prepared > 0
            else 0.0
        )

        surplus_rate_percent = (
            (total_remaining / total_prepared) * 100
            if total_prepared > 0
            else 0.0
        )

        average_waste_per_remaining_meal = (
            total_waste_kg / total_remaining
            if total_remaining > 0
            else 0.0
        )

        excess_production = max(
            total_prepared - total_consumed,
            0,
        )

        return {
            "total_meals_prepared": total_prepared,
            "total_meals_consumed": total_consumed,
            "total_meals_remaining": total_remaining,
            "total_waste_kg": round(total_waste_kg, 2),
            "average_daily_waste_kg": round(
                average_daily_waste,
                2,
            ),
            "waste_rate_percent": round(
                max(waste_rate_percent, 0.0),
                2,
            ),
            "surplus_rate_percent": round(
                max(surplus_rate_percent, 0.0),
                2,
            ),
            "excess_production_meals": excess_production,
            "average_waste_per_remaining_meal_kg": round(
                max(average_waste_per_remaining_meal, 0.0),
                4,
            ),
        }

    @staticmethod
    def _build_daily_metrics(
        records: Sequence[HistoricalRecord],
    ) -> list[WasteDailyMetric]:
        """Aggregate records into one metric per calendar day."""
        if not records:
            return []

        daily: dict[date, dict[str, float | int]] = {}

        for record in records:
            metrics = daily.setdefault(
                record.record_date,
                {
                    "meals_prepared": 0,
                    "meals_consumed": 0,
                    "meals_remaining": 0,
                    "waste_kg": 0.0,
                },
            )

            metrics["meals_prepared"] = (
                int(metrics["meals_prepared"])
                + record.meals_prepared
            )
            metrics["meals_consumed"] = (
                int(metrics["meals_consumed"])
                + record.meals_consumed
            )
            metrics["meals_remaining"] = (
                int(metrics["meals_remaining"])
                + record.meals_remaining
            )
            metrics["waste_kg"] = (
                float(metrics["waste_kg"])
                + record.waste_kg
            )

        result: list[WasteDailyMetric] = []

        for record_date in sorted(daily):
            metrics = daily[record_date]

            prepared = int(metrics["meals_prepared"])
            remaining = int(metrics["meals_remaining"])
            waste_kg = float(metrics["waste_kg"])

            waste_rate = (
                (waste_kg / prepared) * 100
                if prepared > 0
                else 0.0
            )

            surplus_rate = (
                (remaining / prepared) * 100
                if prepared > 0
                else 0.0
            )

            result.append(
                WasteDailyMetric(
                    record_date=record_date,
                    meals_prepared=prepared,
                    meals_consumed=int(metrics["meals_consumed"]),
                    meals_remaining=remaining,
                    waste_kg=round(waste_kg, 2),
                    waste_rate_percent=round(
                        max(waste_rate, 0.0),
                        2,
                    ),
                    surplus_rate_percent=round(
                        max(surplus_rate, 0.0),
                        2,
                    ),
                )
            )

        return result

    @staticmethod
    def _calculate_trend(
        daily_metrics: Sequence[WasteDailyMetric],
    ) -> WasteTrend:
        """Classify waste trend from the first and second halves."""
        if len(daily_metrics) < 6:
            return "insufficient_data"

        midpoint = len(daily_metrics) // 2

        first_half = daily_metrics[:midpoint]
        second_half = daily_metrics[midpoint:]

        first_average = mean(
            metric.waste_kg
            for metric in first_half
        )
        second_average = mean(
            metric.waste_kg
            for metric in second_half
        )

        if first_average <= 0:
            if second_average <= 0:
                return "stable"

            return "worsening"

        change_ratio = (
            second_average - first_average
        ) / first_average

        if change_ratio <= -0.10:
            return "improving"

        if change_ratio >= 0.10:
            return "worsening"

        return "stable"

    @staticmethod
    def _build_insight(
        *,
        records_count: int,
        waste_rate_percent: float,
        surplus_rate_percent: float,
        excess_production_meals: int,
        average_daily_waste_kg: float,
        trend: WasteTrend,
    ) -> str:
        """Create a concise operational interpretation."""
        if records_count == 0:
            return (
                "No historical food records were found for this analysis "
                "period, so FoodSense cannot identify a waste pattern yet."
            )

        if trend == "improving":
            trend_text = "Waste is trending downward"
        elif trend == "worsening":
            trend_text = "Waste is trending upward"
        elif trend == "stable":
            trend_text = "Waste is relatively stable"
        else:
            trend_text = "There is not enough daily history to determine a trend"

        return (
            f"{trend_text}. The analysis found an average of "
            f"{average_daily_waste_kg:.2f} kg waste per recorded meal "
            f"operation, with a {surplus_rate_percent:.1f}% meal surplus "
            f"rate and {excess_production_meals:,} excess meals across "
            f"{records_count} records."
        )

    @staticmethod
    def _build_recommendations(
        *,
        waste_rate_percent: float,
        surplus_rate_percent: float,
        excess_production_meals: int,
        trend: WasteTrend,
    ) -> list[str]:
        """Build data-driven operational recommendations."""
        recommendations: list[str] = []

        if surplus_rate_percent >= 15:
            recommendations.append(
                "Review production quantities for recurring overproduction "
                "and compare them with demand forecasts."
            )
        elif surplus_rate_percent >= 5:
            recommendations.append(
                "Monitor meals prepared versus consumed and gradually "
                "adjust production toward observed demand."
            )

        if waste_rate_percent >= 0.01:
            recommendations.append(
                "Track the source of waste during preparation and service "
                "to identify preventable loss."
            )

        if excess_production_meals > 0:
            recommendations.append(
                "Use predicted demand and planned-production scenarios "
                "before finalizing meal quantities."
            )

        if trend == "worsening":
            recommendations.append(
                "Investigate recent operational changes because the "
                "waste trend is increasing."
            )
        elif trend == "improving":
            recommendations.append(
                "Continue the practices associated with the recent "
                "reduction in waste."
            )

        if not recommendations:
            recommendations.append(
                "Continue collecting daily records so FoodSense can "
                "build a stronger organization-specific waste baseline."
            )

        return recommendations[:10]

    @staticmethod
    def _validate_request(
        request: WasteAnalysisRequest,
    ) -> None:
        """Validate analysis constraints."""
        if request.end_date < request.start_date:
            raise ValueError(
                "end_date cannot be earlier than start_date."
            )

        period_days = (
            request.end_date - request.start_date
        ).days + 1

        if period_days > 365:
            raise ValueError(
                "Waste analysis cannot span more than 365 days."
            )

    @staticmethod
    def _utc_now_iso() -> str:
        """Return the current UTC timestamp."""
        return datetime.now(timezone.utc).isoformat()
