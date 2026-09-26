"""Historical food-record data service for FoodSense forecasting.

This service is responsible for reading raw Firestore food records and
converting them into validated, normalized forecasting data.

Forecasting algorithms do not belong in this module. Keeping ingestion and
normalization separate makes the model layer easier to test and replace.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any, Iterable

from ..schemas.forecast_schema import (
    ForecastFeatureSummary,
    HistoricalRecord,
    MealType,
)


class HistoricalDataService:
    """Loads and normalizes FoodSense historical food records."""

    def __init__(self, firestore_client: Any) -> None:
        """Create the service with a Firestore client.

        The client is injected rather than constructed here. This keeps
        Firebase credentials and application initialization outside the data
        service and makes the service straightforward to unit test.
        """
        if firestore_client is None:
            raise ValueError("A Firestore client is required.")

        self._db = firestore_client

    def _records_collection(self, organization_id: str) -> Any:
        """Return the organization-scoped food_records collection."""
        organization_id = self._validate_organization_id(organization_id)

        return (
            self._db
            .collection("organizations")
            .document(organization_id)
            .collection("food_records")
        )

    def fetch_records(
        self,
        *,
        organization_id: str,
        meal_type: MealType | None = None,
        start_date: date | None = None,
        end_date: date | None = None,
        limit: int = 500,
    ) -> list[HistoricalRecord]:
        """Fetch and normalize historical records from Firestore.

        Filtering by meal type is performed after the Firestore read. This
        deliberately avoids requiring a composite Firestore index at this
        stage of the project. Date filtering is pushed to Firestore because
        recordDate is already the primary time-series field.
        """
        if limit < 1 or limit > 5000:
            raise ValueError("limit must be between 1 and 5000.")

        if start_date is not None and end_date is not None:
            if start_date > end_date:
                raise ValueError(
                    "start_date cannot be later than end_date."
                )

        collection = self._records_collection(organization_id)

        query: Any = (
            collection
            .order_by("recordDate", direction="DESCENDING")
            .limit(limit)
        )

        if start_date is not None:
            query = query.where(
                "recordDate",
                ">=",
                self._day_start_timestamp(start_date),
            )

        if end_date is not None:
            # Make end_date inclusive by using the beginning of the next day.
            query = query.where(
                "recordDate",
                "<",
                self._day_start_timestamp(
                    end_date.fromordinal(end_date.toordinal() + 1)
                ),
            )

        snapshots: Iterable[Any] = query.stream()

        records: list[HistoricalRecord] = []

        for snapshot in snapshots:
            data = snapshot.to_dict() or {}

            # Ignore malformed/cross-organization documents rather than
            # feeding them silently into the forecasting dataset.
            record_organization_id = str(
                data.get("organizationId", "")
            ).strip()

            if record_organization_id != organization_id:
                continue

            record = self.normalize_record(data)

            if meal_type is not None and record.meal_type != meal_type:
                continue

            records.append(record)

        return records

    def normalize_record(
        self,
        raw: dict[str, Any],
    ) -> HistoricalRecord:
        """Convert one raw Firestore record into the forecasting schema."""
        if not isinstance(raw, dict):
            raise TypeError("A food record must be a dictionary.")

        record_date = self._parse_record_date(raw.get("recordDate"))

        meal_type = self._parse_meal_type(raw.get("mealType"))

        expected_people = self._non_negative_int(
            raw.get("expectedPeople")
        )
        actual_people = self._non_negative_int(
            raw.get("actualPeople")
        )
        meals_prepared = self._non_negative_int(
            raw.get("mealsPrepared")
        )
        meals_consumed = self._non_negative_int(
            raw.get("mealsConsumed")
        )
        waste_kg = self._non_negative_float(
            raw.get("wasteKg")
        )

        # mealsRemaining is derived from prepared/consumed whenever possible.
        # This protects the training dataset from stale or manually edited
        # derived values.
        meals_remaining = max(
            meals_prepared - meals_consumed,
            0,
        )

        return HistoricalRecord(
            record_date=record_date,
            meal_type=meal_type,
            expected_people=expected_people,
            actual_people=actual_people,
            meals_prepared=meals_prepared,
            meals_consumed=meals_consumed,
            meals_remaining=meals_remaining,
            waste_kg=waste_kg,
            special_event=bool(raw.get("specialEvent", False)),
        )

    def build_feature_summary(
        self,
        records: list[HistoricalRecord],
    ) -> ForecastFeatureSummary:
        """Build basic statistics used for data-quality and model decisions."""
        if not records:
            return ForecastFeatureSummary(
                historical_records=0,
                average_consumption=0.0,
                average_waste_kg=0.0,
                average_expected_people=0.0,
                average_prepared_meals=0.0,
                special_event_records=0,
                weekdays_observed=0,
            )

        average_consumption = self._average(
            record.meals_consumed for record in records
        )

        average_waste = self._average(
            record.waste_kg for record in records
        )

        average_expected = self._average(
            record.expected_people for record in records
        )

        average_prepared = self._average(
            record.meals_prepared for record in records
        )

        special_event_records = sum(
            1 for record in records if record.special_event
        )

        weekdays_observed = len(
            {
                record.record_date.weekday()
                for record in records
                if record.record_date.weekday() < 5
            }
        )

        return ForecastFeatureSummary(
            historical_records=len(records),
            average_consumption=average_consumption,
            average_waste_kg=average_waste,
            average_expected_people=average_expected,
            average_prepared_meals=average_prepared,
            special_event_records=special_event_records,
            weekdays_observed=weekdays_observed,
        )

    def sort_for_training(
        self,
        records: list[HistoricalRecord],
    ) -> list[HistoricalRecord]:
        """Return records in chronological order."""
        return sorted(
            records,
            key=lambda record: (
                record.record_date,
                record.meal_type,
            ),
        )

    def filter_valid_training_records(
        self,
        records: list[HistoricalRecord],
        *,
        minimum_consumption: int = 0,
    ) -> list[HistoricalRecord]:
        """Remove records that should not enter model training."""
        if minimum_consumption < 0:
            raise ValueError(
                "minimum_consumption cannot be negative."
            )

        return [
            record
            for record in records
            if record.meals_consumed >= minimum_consumption
            and record.expected_people >= 0
            and record.actual_people >= 0
            and record.meals_prepared >= 0
            and record.waste_kg >= 0
        ]

    @staticmethod
    def _validate_organization_id(organization_id: str) -> str:
        """Validate and normalize the organization identifier."""
        if not isinstance(organization_id, str):
            raise TypeError("organization_id must be a string.")

        organization_id = organization_id.strip()

        if not organization_id:
            raise ValueError("organization_id cannot be empty.")

        if len(organization_id) > 128:
            raise ValueError(
                "organization_id cannot exceed 128 characters."
            )

        return organization_id

    @staticmethod
    def _parse_record_date(value: Any) -> date:
        """Convert Firestore/date/string values into a calendar date."""
        if value is None:
            raise ValueError("recordDate is required.")

        if hasattr(value, "to_datetime"):
            value = value.to_datetime()

        if hasattr(value, "to_date"):
            converted = value.to_date()

            if isinstance(converted, datetime):
                return converted.date()

            if isinstance(converted, date):
                return converted

        if isinstance(value, datetime):
            return value.date()

        if isinstance(value, date):
            return value

        if isinstance(value, str):
            try:
                return datetime.fromisoformat(
                    value.replace("Z", "+00:00")
                ).date()
            except ValueError:
                try:
                    return date.fromisoformat(value)
                except ValueError as exc:
                    raise ValueError(
                        "recordDate must be a valid ISO date/datetime."
                    ) from exc

        raise TypeError(
            "recordDate must be a Firestore timestamp, date, "
            "datetime, or ISO string."
        )

    @staticmethod
    def _parse_meal_type(value: Any) -> MealType:
        """Normalize and validate the stored meal type."""
        if not isinstance(value, str):
            raise ValueError("mealType is required.")

        normalized = value.strip()

        allowed: tuple[str, ...] = (
            "Breakfast",
            "Lunch",
            "Dinner",
            "Snack",
            "Other",
        )

        if normalized not in allowed:
            raise ValueError(
                f"Unsupported mealType: {normalized!r}."
            )

        return normalized  # type: ignore[return-value]

    @staticmethod
    def _non_negative_int(value: Any) -> int:
        """Convert a numeric Firestore value into a non-negative integer."""
        if isinstance(value, bool):
            raise ValueError("Boolean values are not valid integer fields.")

        if isinstance(value, int):
            number = value
        elif isinstance(value, float):
            number = int(value)
        elif isinstance(value, str):
            try:
                number = int(value.strip())
            except ValueError as exc:
                raise ValueError(
                    f"Invalid integer value: {value!r}."
                ) from exc
        elif isinstance(value, (bytes, bytearray)):
            try:
                number = int(value.decode().strip())
            except (ValueError, UnicodeDecodeError) as exc:
                raise ValueError(
                    "Invalid byte value for integer field."
                ) from exc
        else:
            raise TypeError(
                f"Unsupported integer field type: {type(value).__name__}."
            )

        if number < 0:
            raise ValueError("Numeric values cannot be negative.")

        return number

    @staticmethod
    def _non_negative_float(value: Any) -> float:
        """Convert a numeric Firestore value into a non-negative float."""
        if isinstance(value, bool):
            raise ValueError("Boolean values are not valid numeric fields.")

        if isinstance(value, (int, float)):
            number = float(value)
        elif isinstance(value, str):
            try:
                number = float(value.strip())
            except ValueError as exc:
                raise ValueError(
                    f"Invalid numeric value: {value!r}."
                ) from exc
        else:
            raise TypeError(
                f"Unsupported numeric field type: {type(value).__name__}."
            )

        if number < 0:
            raise ValueError("Numeric values cannot be negative.")

        return number

    @staticmethod
    def _average(values: Iterable[int | float]) -> float:
        """Calculate an arithmetic mean without external dependencies."""
        values_list = list(values)

        if not values_list:
            return 0.0

        return sum(values_list) / len(values_list)

    @staticmethod
    def _day_start_timestamp(value: date) -> Any:
        """Create a UTC datetime suitable for Firestore timestamp filters."""
        return datetime(
            value.year,
            value.month,
            value.day,
            tzinfo=timezone.utc,
        )
