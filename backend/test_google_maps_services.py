from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone

import httpx
from dotenv import load_dotenv

load_dotenv(".env")

KEY = os.getenv("FOODSENSE_GOOGLE_ROUTES_API_KEY", "").strip()

if not KEY:
    raise SystemExit(
        "FOODSENSE_GOOGLE_ROUTES_API_KEY is missing from backend/.env"
    )

print(f"Server key loaded: {KEY[:6]}... ({len(KEY)} chars)")


def print_result(name: str, response: httpx.Response) -> None:
    print(f"\n{name}: HTTP {response.status_code}")

    try:
        body = response.json()
    except ValueError:
        print(response.text[:1000])
        return

    if response.is_success:
        if name == "Routes API":
            routes = body.get("routes") or []
            print(f"Routes returned: {len(routes)}")
            if routes:
                route = routes[0]
                print("Distance meters:", route.get("distanceMeters"))
                print("Duration:", route.get("duration"))
                print("Static duration:", route.get("staticDuration"))
                print(
                    "Polyline returned:",
                    bool((route.get("polyline") or {}).get("encodedPolyline")),
                )
        else:
            places = body.get("places") or []
            print(f"Places returned: {len(places)}")
            if places:
                place = places[0]
                print(
                    "First place:",
                    (place.get("displayName") or {}).get("text"),
                )
                print("Address:", place.get("formattedAddress"))
        return

    error = body.get("error", {})
    if isinstance(error, dict):
        print("Google error code:", error.get("code"))
        print("Google error status:", error.get("status"))
        print("Google error message:", error.get("message"))
    else:
        print(json.dumps(body, indent=2)[:1500])


routes_url = "https://routes.googleapis.com/directions/v2:computeRoutes"

departure = (
    datetime.now(timezone.utc) + timedelta(minutes=1)
).isoformat().replace("+00:00", "Z")

routes_payload = {
    "origin": {
        "location": {
            "latLng": {
                "latitude": 28.9845,
                "longitude": 77.7064,
            }
        }
    },
    "destination": {
        "location": {
            "latLng": {
                "latitude": 28.9700,
                "longitude": 77.7000,
            }
        }
    },
    "travelMode": "DRIVE",
    "routingPreference": "TRAFFIC_AWARE_OPTIMAL",
    "trafficModel": "BEST_GUESS",
    "computeAlternativeRoutes": True,
    "extraComputations": ["TRAFFIC_ON_POLYLINE"],
    "departureTime": departure,
    "units": "METRIC",
    "polylineQuality": "HIGH_QUALITY",
    "polylineEncoding": "ENCODED_POLYLINE",
}

routes_headers = {
    "Content-Type": "application/json",
    "X-Goog-Api-Key": KEY,
    "X-Goog-FieldMask": (
        "routes.duration,"
        "routes.staticDuration,"
        "routes.distanceMeters,"
        "routes.polyline.encodedPolyline,"
        "routes.routeLabels,"
        "routes.travelAdvisory.speedReadingIntervals"
    ),
}

places_url = "https://places.googleapis.com/v1/places:searchText"

places_payload = {
    "textQuery": "Sai Sweets, Meerut, Uttar Pradesh, India",
    "pageSize": 5,
    "languageCode": "en",
    "regionCode": "IN",
}

places_headers = {
    "Content-Type": "application/json",
    "X-Goog-Api-Key": KEY,
    "X-Goog-FieldMask": (
        "places.id,"
        "places.displayName,"
        "places.formattedAddress,"
        "places.location"
    ),
}

try:
    with httpx.Client(timeout=30.0) as client:
        routes_response = client.post(
            routes_url,
            headers=routes_headers,
            json=routes_payload,
        )
        print_result("Routes API", routes_response)

        places_response = client.post(
            places_url,
            headers=places_headers,
            json=places_payload,
        )
        print_result("Places API (New)", places_response)

except httpx.HTTPError as exc:
    raise SystemExit(f"Could not reach Google Maps Platform: {exc}") from exc
