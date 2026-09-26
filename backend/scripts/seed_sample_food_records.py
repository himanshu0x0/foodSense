"""Development-only Firestore seed script for FoodSense.

Creates synthetic historical food records for one existing organization so the
Phase 2 forecasting pipeline can be tested before real historical data exists.

Run from backend/ with the virtual environment active:

    python scripts/seed_sample_food_records.py --organization-id YOUR_ORG_ID

Optional:
    --days 60
    --start-date 2026-07-28
    --clear-existing

IMPORTANT:
- Development/testing tool only.
- Uses Firebase Admin credentials from backend/.env.
- Never expose this script as a public API.
- Do not use --clear-existing against production data.
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.firebase_service import get_firestore_client  # noqa: E402


MEAL_TYPES = ("Breakfast", "Lunch", "Dinner", "Snack")

MENUS = {
    "Breakfast": (
        "Poha, Banana, Tea",
        "Aloo Paratha, Curd, Tea",
        "Idli, Sambar, Chutney",
        "Upma, Fruit, Tea",
    ),
    "Lunch": (
        "Rice, Dal, Paneer, Salad",
        "Rice, Rajma, Vegetables, Roti",
        "Rice, Chole, Roti, Salad",
        "Dal, Rice, Mix Veg, Roti",
    ),
    "Dinner": (
        "Rice, Dal, Paneer, Roti",
        "Khichdi, Curd, Salad",
        "Rice, Chole, Vegetable, Roti",
        "Dal, Rice, Seasonal Veg, Roti",
    ),
    "Snack": (
        "Samosa, Tea",
        "Sandwich, Juice",
        "Biscuits, Tea",
        "Fruit, Tea",
    ),
}

BASE_DEMAND_RATES = {
    "Breakfast": 0.86,
    "Lunch": 0.93,
    "Dinner": 0.88,
    "Snack": 0.72,
}


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(
        description="Seed synthetic FoodSense food records into Firestore."
    )
    parser.add_argument(
        "--organization-id",
        required=True,
        help="Existing Firestore organization document ID.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=60,
        help="Number of historical days to generate.",
    )
    parser.add_argument(
        "--start-date",
        type=date.fromisoformat,
        default=None,
        help="First historical date in YYYY-MM-DD format.",
    )
    parser.add_argument(
        "--clear-existing",
        action="store_true",
        help="Delete existing food_records before seeding.",
    )
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    """Validate CLI input."""
    if not args.organization_id.strip():
        raise ValueError("organization ID cannot be empty.")

    if args.days < 30:
        raise ValueError("days must be at least 30.")

    if args.days > 365:
        raise ValueError("days cannot exceed 365.")

    if args.start_date is not None:
        end_date = args.start_date + timedelta(days=args.days - 1)
        if end_date >= date.today():
            raise ValueError(
                "Generated seed data must remain historical; "
                "the end date must be before today."
            )


def get_organization(
    db: Any,
    organization_id: str,
) -> dict[str, Any]:
    """Load and validate the target organization."""
    snapshot = (
        db.collection("organizations")
        .document(organization_id)
        .get()
    )

    if not snapshot.exists:
        raise ValueError(
            f"Organization {organization_id!r} does not exist."
        )

    data = snapshot.to_dict() or {}

    owner_id = str(data.get("ownerId", "")).strip()
    if not owner_id:
        raise ValueError("Target organization has no ownerId.")

    return data


def delete_existing_records(
    db: Any,
    organization_id: str,
) -> int:
    """Delete all existing food records in the target organization."""
    collection = (
        db.collection("organizations")
        .document(organization_id)
        .collection("food_records")
    )

    deleted = 0

    while True:
        snapshots = list(collection.limit(400).stream())
        if not snapshots:
            break

        batch = db.batch()

        for snapshot in snapshots:
            batch.delete(snapshot.reference)

        batch.commit()
        deleted += len(snapshots)

    return deleted


def seeded_people_served(organization_data: dict[str, Any]) -> int:
    """Read configured organization population with a safe default."""
    raw = organization_data.get("peopleServed", 1200)

    try:
        value = int(float(raw))
    except (TypeError, ValueError):
        value = 1200

    return max(value, 100)


def create_record(
    *,
    organization_id: str,
    owner_id: str,
    record_date: date,
    meal_type: str,
    people_served: int,
    rng: random.Random,
    record_index: int,
) -> dict[str, Any]:
    """Generate one realistic synthetic food-operation record."""
    weekday = record_date.weekday()
    weekday_multiplier = 1.0 if weekday < 5 else 0.78

    base_expected = people_served * weekday_multiplier

    meal_fraction = {
        "Breakfast": 0.82,
        "Lunch": 1.00,
        "Dinner": 0.78,
        "Snack": 0.64,
    }[meal_type]

    expected_people = max(
        1,
        int(
            round(
                base_expected
                * meal_fraction
                * rng.uniform(0.96, 1.04)
            )
        ),
    )

    special_event = (
        record_index % 17 == 0
        or (
            weekday == 4
            and meal_type == "Lunch"
            and record_index % 9 == 0
        )
    )

    if special_event:
        expected_people = int(
            round(expected_people * rng.uniform(1.08, 1.18))
        )

    attendance_rate = rng.uniform(0.94, 1.00)

    actual_people = max(
        0,
        min(
            expected_people,
            int(round(expected_people * attendance_rate)),
        ),
    )

    demand_rate = BASE_DEMAND_RATES[meal_type]

    trend = 1.0 + 0.025 * math.sin(record_index / 8.0)

    if special_event:
        demand_rate += 0.025

    consumption_rate = min(
        max(
            demand_rate * trend + rng.uniform(-0.025, 0.02),
            0.50,
        ),
        1.05,
    )

    meals_consumed = max(
        0,
        min(
            expected_people,
            int(round(actual_people * consumption_rate)),
        ),
    )

    overproduction_buffer = rng.uniform(0.015, 0.075)

    if special_event:
        overproduction_buffer += rng.uniform(0.015, 0.04)

    meals_prepared = max(
        meals_consumed,
        int(round(expected_people * (1.0 + overproduction_buffer))),
    )

    meals_remaining = max(
        0,
        meals_prepared - meals_consumed,
    )

    waste_ratio = rng.uniform(0.07, 0.16)

    waste_kg = round(
        max(
            0.5,
            meals_remaining
            * waste_ratio
            * rng.uniform(0.08, 0.15),
        ),
        2,
    )

    created_at = datetime.now(timezone.utc)

    return {
        "organizationId": organization_id,
        "recordDate": datetime(
            record_date.year,
            record_date.month,
            record_date.day,
            tzinfo=timezone.utc,
        ),
        "mealType": meal_type,
        "menu": rng.choice(MENUS[meal_type]),
        "expectedPeople": expected_people,
        "actualPeople": actual_people,
        "mealsPrepared": meals_prepared,
        "mealsConsumed": meals_consumed,
        "mealsRemaining": meals_remaining,
        "wasteKg": waste_kg,
        "specialEvent": special_event,
        "createdBy": owner_id,
        "createdAt": created_at,
        "updatedBy": owner_id,
        "updatedAt": created_at,
        "source": "development_seed",
    }


def seed_records(
    *,
    db: Any,
    organization_id: str,
    organization_data: dict[str, Any],
    start_date: date,
    days: int,
) -> int:
    """Create synthetic historical records in Firestore batches."""
    people_served = seeded_people_served(organization_data)
    owner_id = str(organization_data["ownerId"]).strip()

    collection = (
        db.collection("organizations")
        .document(organization_id)
        .collection("food_records")
    )

    rng = random.Random(
        f"foodsense:{organization_id}:{start_date.isoformat()}:{days}"
    )

    records_created = 0
    batch = db.batch()
    batch_count = 0

    for day_index in range(days):
        record_date = start_date + timedelta(days=day_index)

        for meal_type in MEAL_TYPES:
            record = create_record(
                organization_id=organization_id,
                owner_id=owner_id,
                record_date=record_date,
                meal_type=meal_type,
                people_served=people_served,
                rng=rng,
                record_index=day_index,
            )

            document_id = (
                f"seed_{record_date.isoformat()}_{meal_type.lower()}"
            )

            batch.set(
                collection.document(document_id),
                record,
            )

            records_created += 1
            batch_count += 1

            if batch_count >= 400:
                batch.commit()
                batch = db.batch()
                batch_count = 0

    if batch_count:
        batch.commit()

    return records_created


def main() -> int:
    """Run the Firestore seed operation."""
    args = parse_args()
    validate_args(args)

    organization_id = args.organization_id.strip()

    start_date = args.start_date
    if start_date is None:
        start_date = date.today() - timedelta(days=args.days)

    db = get_firestore_client()
    organization_data = get_organization(
        db,
        organization_id,
    )

    print("FoodSense development data seeder")
    print("-" * 40)
    print(f"Organization : {organization_id}")
    print(f"Start date   : {start_date.isoformat()}")
    print(f"Days         : {args.days}")
    print(f"Records      : {args.days * len(MEAL_TYPES)}")
    print()

    if args.clear_existing:
        deleted = delete_existing_records(
            db,
            organization_id,
        )
        print(f"Deleted existing records: {deleted}")

    created = seed_records(
        db=db,
        organization_id=organization_id,
        organization_data=organization_data,
        start_date=start_date,
        days=args.days,
    )

    print(f"Created records          : {created}")
    print()
    print("RESULT: DEVELOPMENT DATA SEEDED")
    print(
        "The forecasting pipeline now has historical records to analyze."
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
