"""Automated Phase 2 backend test for FoodSense.

Run from backend/ with the virtual environment active:
    python test_phase2_auto.py

The script performs HTTP integration checks for Forecast, Surplus, Surplus
Scenarios, Waste, and Waste Trend, plus Firebase authentication, Firestore
data checks, security/validation checks, and a local cold-start forecast test.

Passwords and Firebase ID tokens are never printed.
"""

from __future__ import annotations

import getpass
import json
import math
import os
import sys
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent
load_dotenv(BACKEND_DIR / ".env")

from app.config import settings
from app.schemas.forecast_schema import ForecastRequest
from app.services.forecast_service import ForecastService
from app.services.firebase_service import get_firestore_client

BASE_URL = f"http://{settings.host}:{settings.port}"
MEALS = ("Breakfast", "Lunch", "Dinner", "Snack")


class TestFailure(RuntimeError):
    """Raised when a Phase 2 assertion fails."""


def request_json(
    method: str,
    url: str,
    *,
    payload: dict[str, Any] | None = None,
    token: str | None = None,
) -> tuple[int, Any]:
    """Perform an HTTP JSON request without extra dependencies."""
    headers = {"Accept": "application/json"}
    body = None

    if payload is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(payload).encode("utf-8")

    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = Request(url, data=body, headers=headers, method=method)

    try:
        with urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return response.status, decode_json(raw)
    except HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        return exc.code, decode_json(raw)
    except (URLError, TimeoutError, OSError) as exc:
        raise TestFailure(
            f"Cannot reach {url}: {exc}"
        ) from exc


def decode_json(raw: str) -> Any:
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise TestFailure(message)


def firebase_sign_in(email: str, password: str, api_key: str) -> dict[str, Any]:
    """Sign in through Firebase Authentication REST API."""
    url = (
        "https://identitytoolkit.googleapis.com/v1/"
        f"accounts:signInWithPassword?key={api_key}"
    )
    status, body = request_json(
        "POST",
        url,
        payload={
            "email": email,
            "password": password,
            "returnSecureToken": True,
        },
    )

    if not 200 <= status < 300:
        message = "Firebase Authentication failed."
        if isinstance(body, dict):
            message = body.get("error", {}).get("message", message)
        raise TestFailure(message)

    assert_true(isinstance(body, dict), "Unexpected Firebase Auth response.")
    return body


def organization_context(uid: str) -> dict[str, Any]:
    """Read the authenticated user's organization and its records."""
    db = get_firestore_client()

    user_snapshot = db.collection("users").document(uid).get()
    assert_true(user_snapshot.exists, "Authenticated user document was not found.")

    user_data = user_snapshot.to_dict() or {}
    organization_id = str(user_data.get("organizationId", "")).strip()
    assert_true(organization_id, "Authenticated user has no organizationId.")

    organization_snapshot = (
        db.collection("organizations").document(organization_id).get()
    )
    assert_true(
        organization_snapshot.exists,
        f"Organization {organization_id!r} was not found.",
    )

    records = list(
        db.collection("organizations")
        .document(organization_id)
        .collection("food_records")
        .stream()
    )

    meal_counts: Counter[str] = Counter()
    record_dates: list[date] = []

    for snapshot in records:
        data = snapshot.to_dict() or {}
        meal = data.get("mealType") or data.get("meal_type")
        if isinstance(meal, str) and meal.strip():
            meal_counts[meal.strip()] += 1

        raw_date = data.get("recordDate") or data.get("record_date")
        if isinstance(raw_date, datetime):
            record_dates.append(raw_date.date())
        elif isinstance(raw_date, date):
            record_dates.append(raw_date)

    return {
        "organization_id": organization_id,
        "organization_data": organization_snapshot.to_dict() or {},
        "record_count": len(records),
        "meal_counts": meal_counts,
        "record_dates": record_dates,
    }


def tomorrow() -> date:
    return date.today() + timedelta(days=1)


def forecast_payload(
    organization_id: str,
    *,
    expected_people: int,
    meal_type: str = "Lunch",
    special_event: bool = False,
) -> dict[str, Any]:
    return {
        "organization_id": organization_id,
        "forecast_date": tomorrow().isoformat(),
        "meal_type": meal_type,
        "expected_people": expected_people,
        "special_event": special_event,
        "menu": "Phase 2 automated test",
    }


def test_basic_health() -> None:
    for path in ("/", "/health", "/forecast/health", "/surplus/health", "/waste/health"):
        status, body = request_json("GET", BASE_URL + path)
        assert_true(status == 200, f"{path} returned {status}: {body}")
    print("[PASS] API/system health")


def test_firestore(context: dict[str, Any]) -> None:
    count = context["record_count"]
    meal_counts: Counter[str] = context["meal_counts"]

    assert_true(count > 0, "No food_records found.")
    for meal in MEALS:
        assert_true(meal_counts[meal] > 0, f"No {meal} records found.")

    dist = ", ".join(f"{m}={meal_counts[m]}" for m in MEALS)
    print(f"[PASS] Firestore historical data: {count} records ({dist})")


def test_security(
    organization_id: str,
    expected_people: int,
    token: str,
) -> None:
    payload = forecast_payload(
        organization_id,
        expected_people=expected_people,
    )

    status, body = request_json(
        "POST",
        BASE_URL + "/forecast",
        payload=payload,
    )
    assert_true(status == 401, f"Missing-token test expected 401, got {status}: {body}")
    print("[PASS] Missing token -> 401")

    wrong = dict(payload)
    wrong["organization_id"] = "foodsense_org_not_allowed_test"

    status, body = request_json(
        "POST",
        BASE_URL + "/forecast",
        payload=wrong,
        token=token,
    )
    assert_true(status == 403, f"Wrong-org test expected 403, got {status}: {body}")
    print("[PASS] Wrong organization -> 403")

    invalid = dict(payload)
    invalid["meal_type"] = "InvalidMeal"

    status, body = request_json(
        "POST",
        BASE_URL + "/forecast",
        payload=invalid,
        token=token,
    )
    assert_true(status == 422, f"Invalid-input test expected 422, got {status}: {body}")
    print("[PASS] Invalid payload -> 422")


def test_forecast(
    organization_id: str,
    expected_people: int,
    token: str,
    context: dict[str, Any],
) -> dict[str, Any]:
    status, body = request_json(
        "POST",
        BASE_URL + "/forecast",
        payload=forecast_payload(
            organization_id,
            expected_people=expected_people,
        ),
        token=token,
    )
    assert_true(status == 200 and isinstance(body, dict), f"/forecast failed: {status}: {body}")

    predicted = int(body["predicted_demand"])
    safety = int(body["safety_buffer"])
    recommended = int(body["recommended_production"])
    training = int(body["training_records"])

    assert_true(predicted >= 0, "Predicted demand is negative.")
    assert_true(safety >= 0, "Safety buffer is negative.")
    assert_true(recommended == predicted + safety, "Production calculation is inconsistent.")
    assert_true(training > 0, "Forecast did not use historical records.")
    assert_true(body.get("fallback_used") is False, "Forecast unexpectedly used fallback.")
    assert_true(training <= context["meal_counts"]["Lunch"], "Training count exceeds stored Lunch history.")

    configured = float(body["safety_buffer_percent"])
    expected_safety = math.ceil(predicted * configured / 100.0)
    assert_true(safety == expected_safety, "Safety buffer does not match configuration.")

    print(
        "[PASS] Demand forecast: "
        f"demand={predicted}, buffer={safety}, production={recommended}, "
        f"training={training}, fallback={body.get('fallback_used')}"
    )
    return body


def test_meals(
    organization_id: str,
    expected_people: int,
    token: str,
    context: dict[str, Any],
) -> None:
    results: dict[str, int] = {}

    for meal in MEALS:
        status, body = request_json(
            "POST",
            BASE_URL + "/forecast",
            payload=forecast_payload(
                organization_id,
                expected_people=expected_people,
                meal_type=meal,
            ),
            token=token,
        )
        assert_true(status == 200 and isinstance(body, dict), f"{meal} forecast failed: {status}: {body}")

        training = int(body["training_records"])
        assert_true(training > 0, f"{meal} has no historical training records.")
        assert_true(training <= context["meal_counts"][meal], f"{meal} training count exceeds history.")
        results[meal] = training

    print("[PASS] Meal filtering: " + ", ".join(f"{m}={v}" for m, v in results.items()))


def test_attendance(
    organization_id: str,
    token: str,
) -> None:
    values: list[int] = []

    for people in (1000, 1800, 2500):
        status, body = request_json(
            "POST",
            BASE_URL + "/forecast",
            payload=forecast_payload(
                organization_id,
                expected_people=people,
            ),
            token=token,
        )
        assert_true(status == 200, f"Attendance test failed: {status}: {body}")
        values.append(int(body["predicted_demand"]))

    assert_true(len(set(values)) > 1, "Forecast did not respond to attendance changes.")
    print(f"[PASS] Attendance sensitivity: 1000->{values[0]}, 1800->{values[1]}, 2500->{values[2]}")


def test_special_event(
    organization_id: str,
    expected_people: int,
    token: str,
) -> None:
    status, body = request_json(
        "POST",
        BASE_URL + "/forecast",
        payload=forecast_payload(
            organization_id,
            expected_people=expected_people,
            special_event=True,
        ),
        token=token,
    )
    assert_true(status == 200 and isinstance(body, dict), f"Special-event forecast failed: {status}: {body}")
    assert_true(int(body["training_records"]) > 0, "Special-event forecast has no training records.")
    print(f"[PASS] Special-event forecast: training={body['training_records']}")


def test_surplus(
    organization_id: str,
    expected_people: int,
    token: str,
    forecast: dict[str, Any],
) -> None:
    demand = int(forecast["predicted_demand"])
    production = demand + 100

    payload = {
        "organization_id": organization_id,
        "prediction_date": tomorrow().isoformat(),
        "meal_type": "Lunch",
        "planned_production": production,
        "expected_people": expected_people,
        "special_event": False,
    }

    status, body = request_json(
        "POST",
        BASE_URL + "/surplus",
        payload=payload,
        token=token,
    )
    assert_true(status == 200 and isinstance(body, dict), f"/surplus failed: {status}: {body}")

    returned_demand = int(body["predicted_demand"])
    surplus = int(body["predicted_surplus"])
    percent = float(body["surplus_percent"])

    assert_true(returned_demand == demand, "Surplus demand differs from Forecast demand.")
    assert_true(surplus == max(production - demand, 0), "Surplus calculation is inconsistent.")

    expected_percent = round((surplus / production * 100) if production else 0.0, 2)
    assert_true(abs(percent - expected_percent) < 0.01, "Surplus percentage is inconsistent.")
    assert_true(body["surplus_risk"] in {"none", "low", "medium", "high"}, "Invalid surplus risk.")

    print(
        "[PASS] Surplus prediction: "
        f"demand={returned_demand}, surplus={surplus}, risk={body['surplus_risk']}"
    )


def test_surplus_scenarios(
    organization_id: str,
    expected_people: int,
    token: str,
    forecast: dict[str, Any],
) -> None:
    demand = int(forecast["predicted_demand"])
    steps = sorted(
        {
            demand,
            demand + max(1, math.ceil(demand * 0.03)),
            demand + max(1, math.ceil(demand * 0.10)),
            demand + max(1, math.ceil(demand * 0.20)),
        }
    )

    payload = {
        "organization_id": organization_id,
        "prediction_date": tomorrow().isoformat(),
        "meal_type": "Lunch",
        "planned_production": demand,
        "expected_people": expected_people,
        "special_event": False,
        "production_steps": steps,
    }

    status, body = request_json(
        "POST",
        BASE_URL + "/surplus/scenarios",
        payload=payload,
        token=token,
    )
    assert_true(status == 200 and isinstance(body, list), f"Scenarios failed: {status}: {body}")
    assert_true(len(body) == len(steps), "Unexpected scenario count.")

    for item in body:
        planned = int(item["planned_production"])
        scenario_demand = int(item["predicted_demand"])
        surplus = int(item["predicted_surplus"])

        assert_true(scenario_demand == demand, "Scenario demand differs from Forecast.")
        assert_true(surplus == max(planned - demand, 0), "Scenario surplus is inconsistent.")

    print(f"[PASS] Surplus scenarios: {len(body)} scenarios")


def test_waste(
    organization_id: str,
    token: str,
    context: dict[str, Any],
) -> None:
    dates = context["record_dates"]
    assert_true(bool(dates), "No dated records available for waste test.")

    start_date = min(dates)
    end_date = min(max(dates), date.today() - timedelta(days=1))

    payload = {
        "organization_id": organization_id,
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
    }

    status, body = request_json(
        "POST",
        BASE_URL + "/waste",
        payload=payload,
        token=token,
    )
    assert_true(status == 200 and isinstance(body, dict), f"/waste failed: {status}: {body}")

    prepared = int(body["total_meals_prepared"])
    consumed = int(body["total_meals_consumed"])
    remaining = int(body["total_meals_remaining"])
    waste = float(body["total_waste_kg"])
    surplus_rate = float(body["surplus_rate_percent"])

    assert_true(int(body["records_analyzed"]) > 0, "Waste analysis returned zero records.")
    assert_true(min(prepared, consumed, remaining) >= 0, "Negative meal metric.")
    assert_true(waste >= 0, "Negative waste.")
    assert_true(consumed <= prepared, "Consumed meals exceed prepared meals.")

    expected_surplus_rate = (remaining / prepared * 100) if prepared else 0.0
    assert_true(abs(surplus_rate - expected_surplus_rate) < 0.01, "Surplus rate is inconsistent.")

    print(
        "[PASS] Waste analysis: "
        f"records={body['records_analyzed']}, waste={waste:.2f} kg, trend={body['trend']}"
    )


def test_waste_by_meal(
    organization_id: str,
    token: str,
) -> None:
    end_date = date.today() - timedelta(days=1)
    start_date = end_date - timedelta(days=29)

    counts: dict[str, int] = {}

    for meal in MEALS:
        payload = {
            "organization_id": organization_id,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "meal_type": meal,
        }

        status, body = request_json(
            "POST",
            BASE_URL + "/waste",
            payload=payload,
            token=token,
        )
        assert_true(status == 200 and isinstance(body, dict), f"{meal} waste failed: {status}: {body}")
        count = int(body["records_analyzed"])
        assert_true(count > 0, f"No {meal} waste records.")
        counts[meal] = count

    print("[PASS] Waste meal filtering: " + ", ".join(f"{m}={v}" for m, v in counts.items()))


def test_waste_trend(
    organization_id: str,
    token: str,
    context: dict[str, Any],
) -> None:
    dates = context["record_dates"]
    start_date = min(dates)
    end_date = min(max(dates), date.today() - timedelta(days=1))

    payload = {
        "organization_id": organization_id,
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
    }

    status, body = request_json(
        "POST",
        BASE_URL + "/waste/trend",
        payload=payload,
        token=token,
    )
    assert_true(status == 200 and isinstance(body, dict), f"/waste/trend failed: {status}: {body}")

    metrics = body.get("daily_metrics")
    assert_true(isinstance(metrics, list) and len(metrics) > 0, "No daily waste metrics returned.")
    assert_true(
        body.get("trend") in {"improving", "stable", "worsening", "insufficient_data"},
        f"Invalid waste trend: {body.get('trend')}",
    )

    print(f"[PASS] Waste trend: {len(metrics)} daily points, trend={body['trend']}")


def test_waste_insufficient_data(
    organization_id: str,
    token: str,
) -> None:
    day = date.today() - timedelta(days=1)

    payload = {
        "organization_id": organization_id,
        "start_date": day.isoformat(),
        "end_date": day.isoformat(),
    }

    status, body = request_json(
        "POST",
        BASE_URL + "/waste/trend",
        payload=payload,
        token=token,
    )
    assert_true(status == 200 and isinstance(body, dict), f"Single-day trend failed: {status}: {body}")
    assert_true(body.get("trend") == "insufficient_data", "Single-day trend should be insufficient_data.")

    print("[PASS] Waste insufficient-data behavior")


class EmptyDataService:
    """Fake data service for the local cold-start forecast check."""

    def fetch_records(self, **_: Any) -> list[Any]:
        return []

    def filter_valid_training_records(self, records: list[Any]) -> list[Any]:
        return []


def test_cold_start() -> None:
    service = ForecastService(
        data_service=EmptyDataService(),  # type: ignore[arg-type]
    )

    expected = 1800
    request = ForecastRequest(
        organization_id="cold_start_test",
        forecast_date=tomorrow(),
        meal_type="Lunch",
        expected_people=expected,
        special_event=False,
        menu=None,
    )

    result = service.forecast(request)

    assert_true(result.fallback_used is True, "Cold-start fallback was not used.")
    assert_true(result.training_records == 0, "Cold-start reported training records.")
    assert_true(result.predicted_demand == expected, "Cold-start did not use expected_people.")

    expected_buffer = math.ceil(
        expected * settings.default_safety_buffer_percent / 100.0
    )
    assert_true(
        result.safety_buffer == expected_buffer,
        "Cold-start safety buffer is inconsistent.",
    )

    print(
        "[PASS] Cold-start fallback: "
        f"demand={result.predicted_demand}, buffer={result.safety_buffer}"
    )


def main() -> int:
    print("=" * 72)
    print("FoodSense Phase 2 Automated Backend Test")
    print("=" * 72)
    print(f"Target: {BASE_URL}")
    print()

    try:
        test_basic_health()

        api_key = os.getenv("FOODSENSE_FIREBASE_WEB_API_KEY", "").strip()
        assert_true(api_key, "FOODSENSE_FIREBASE_WEB_API_KEY is missing from backend/.env.")

        email = input("Firebase email: ").strip()
        password = getpass.getpass("Firebase password: ")

        auth_result = firebase_sign_in(email, password, api_key)
        token = str(auth_result.get("idToken", "")).strip()
        uid = str(auth_result.get("localId", "")).strip()

        assert_true(token and uid, "Firebase login did not return token/UID.")
        print("[PASS] Firebase Authentication")

        context = organization_context(uid)
        organization_id = context["organization_id"]

        print(f"[PASS] Organization access: {organization_id}")
        test_firestore(context)

        raw_people = context["organization_data"].get("peopleServed", 1800)
        try:
            expected_people = max(0, int(float(raw_people)))
        except (TypeError, ValueError):
            expected_people = 1800
        if expected_people == 0:
            expected_people = 1800

        base = forecast_payload(
            organization_id,
            expected_people=expected_people,
        )

        test_security(organization_id, expected_people, token)
        forecast = test_forecast(
            organization_id,
            expected_people,
            token,
            context,
        )
        test_meals(
            organization_id,
            expected_people,
            token,
            context,
        )
        test_attendance(organization_id, token)
        test_special_event(
            organization_id,
            expected_people,
            token,
        )

        test_surplus(
            organization_id,
            expected_people,
            token,
            forecast,
        )
        test_surplus_scenarios(
            organization_id,
            expected_people,
            token,
            forecast,
        )

        test_waste(
            organization_id,
            token,
            context,
        )
        test_waste_by_meal(
            organization_id,
            token,
        )
        test_waste_trend(
            organization_id,
            token,
            context,
        )
        test_waste_insufficient_data(
            organization_id,
            token,
        )
        test_cold_start()

        print()
        print("=" * 72)
        print("RESULT: PHASE 2 AUTOMATED TESTS PASSED")
        print("=" * 72)
        return 0

    except TestFailure as exc:
        print()
        print("=" * 72)
        print("RESULT: PHASE 2 AUTOMATED TEST FAILED")
        print("=" * 72)
        print(str(exc))
        return 1
    except KeyboardInterrupt:
        print("\nTest cancelled.")
        return 130
    except Exception as exc:
        print()
        print("=" * 72)
        print("RESULT: PHASE 2 AUTOMATED TEST FAILED")
        print("=" * 72)
        print(f"{type(exc).__name__}: {exc}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
