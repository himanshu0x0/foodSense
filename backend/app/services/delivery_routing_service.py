from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

import httpx

from ..schemas.delivery_routing_schema import (
    DeliveryRoutingRequest,
    DeliveryRoutingResponse,
    RouteOption,
    TrafficInterval,
)


class DeliveryRoutingService:
    """Server-side adapter around Google Routes API."""

    ROUTES_URL = (
        "https://routes.googleapis.com/directions/v2:computeRoutes"
    )

    def __init__(
        self,
        *,
        api_key: str | None = None,
        timeout_seconds: float = 20.0,
    ) -> None:
        self._api_key = (
            api_key
            if api_key is not None
            else os.getenv(
                "FOODSENSE_GOOGLE_ROUTES_API_KEY",
                "",
            ).strip()
        )
        self._timeout_seconds = timeout_seconds

    @property
    def configured(self) -> bool:
        return bool(self._api_key)

    def compute(
        self,
        request: DeliveryRoutingRequest,
    ) -> DeliveryRoutingResponse:
        if not self.configured:
            raise RuntimeError(
                "FOODSENSE_GOOGLE_ROUTES_API_KEY is not configured."
            )

        departure_time = request.departureTime
        if departure_time is None:
            departure_time = datetime.now(timezone.utc)
        elif departure_time.tzinfo is None:
            departure_time = departure_time.replace(
                tzinfo=timezone.utc
            )

        payload: dict[str, Any] = {
            "origin": {
                "location": {
                    "latLng": {
                        "latitude": request.origin.latitude,
                        "longitude": request.origin.longitude,
                    }
                }
            },
            "destination": {
                "location": {
                    "latLng": {
                        "latitude": request.destination.latitude,
                        "longitude": request.destination.longitude,
                    }
                }
            },
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_AWARE_OPTIMAL",
            "computeAlternativeRoutes": True,
            "trafficModel": "BEST_GUESS",
            "extraComputations": ["TRAFFIC_ON_POLYLINE"],
            "departureTime": (
                departure_time
                .astimezone(timezone.utc)
                .isoformat()
                .replace("+00:00", "Z")
            ),
            "languageCode": "en-US",
            "units": "METRIC",
        }

        field_mask = ",".join(
            [
                "routes.duration",
                "routes.staticDuration",
                "routes.distanceMeters",
                "routes.polyline.encodedPolyline",
                "routes.routeLabels",
                "routes.travelAdvisory.speedReadingIntervals",
            ]
        )

        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self._api_key,
            "X-Goog-FieldMask": field_mask,
        }

        try:
            with httpx.Client(
                timeout=self._timeout_seconds
            ) as client:
                response = client.post(
                    self.ROUTES_URL,
                    headers=headers,
                    json=payload,
                )
        except httpx.HTTPError as exc:
            raise RuntimeError(
                "Google Routes API could not be reached."
            ) from exc

        if response.status_code < 200 or response.status_code >= 300:
            message = "Google Routes API request failed."

            try:
                body = response.json()
                error = body.get("error", {})
                if isinstance(error, dict) and error.get("message"):
                    message = str(error["message"])
            except ValueError:
                pass

            raise RuntimeError(message)

        try:
            body = response.json()
        except ValueError as exc:
            raise RuntimeError(
                "Google Routes API returned invalid JSON."
            ) from exc

        raw_routes = body.get("routes") or []

        if not raw_routes:
            raise RuntimeError(
                "No route was available for these locations."
            )

        options: list[RouteOption] = []

        for raw_route in raw_routes:
            duration_seconds = self._duration_seconds(
                raw_route.get("duration")
            )
            static_duration_seconds = self._duration_seconds(
                raw_route.get("staticDuration")
            )
            traffic_intervals = self._traffic_intervals(
                raw_route
            )

            options.append(
                RouteOption(
                    label=self._route_label(raw_route),
                    distanceMeters=int(
                        raw_route.get("distanceMeters") or 0
                    ),
                    durationSeconds=duration_seconds,
                    staticDurationSeconds=static_duration_seconds,
                    trafficLevel=self._traffic_level(
                        traffic_intervals
                    ),
                    encodedPolyline=str(
                        (
                            raw_route.get("polyline") or {}
                        ).get("encodedPolyline")
                        or ""
                    ),
                    trafficIntervals=traffic_intervals,
                )
            )

        options.sort(
            key=lambda option: (
                option.durationSeconds,
                option.distanceMeters,
            )
        )

        return DeliveryRoutingResponse(
            options=options,
            recommendedIndex=0,
            generatedAt=datetime.now(timezone.utc),
        )

    @staticmethod
    def _duration_seconds(value: Any) -> int:
        if not isinstance(value, str):
            return 0

        raw = value.strip()
        if raw.endswith("s"):
            raw = raw[:-1]

        try:
            return max(0, round(float(raw)))
        except ValueError:
            return 0

    @staticmethod
    def _route_label(route: dict[str, Any]) -> str:
        labels = route.get("routeLabels") or []
        if labels:
            return str(labels[0])
        return "ROUTE"

    @staticmethod
    def _traffic_intervals(
        route: dict[str, Any],
    ) -> list[TrafficInterval]:
        advisory = route.get("travelAdvisory") or {}
        raw_intervals = (
            advisory.get("speedReadingIntervals") or []
        )

        intervals: list[TrafficInterval] = []

        for raw in raw_intervals:
            if not isinstance(raw, dict):
                continue

            start = raw.get("startPolylinePointIndex")
            end = raw.get("endPolylinePointIndex")

            if start is None or end is None:
                continue

            intervals.append(
                TrafficInterval(
                    startPolylinePointIndex=int(start),
                    endPolylinePointIndex=int(end),
                    speed=str(
                        raw.get("speed") or "NORMAL"
                    ),
                )
            )

        return intervals

    @staticmethod
    def _traffic_level(
        intervals: list[TrafficInterval],
    ) -> str:
        speeds = {
            interval.speed.upper()
            for interval in intervals
        }

        if "TRAFFIC_JAM" in speeds:
            return "heavy"

        if "SLOW" in speeds:
            return "moderate"

        return "low"
