from __future__ import annotations

import os
from typing import Any

import httpx

from ..schemas.place_search_schema import (
    PlaceSearchRequest,
    PlaceSearchResponse,
    PlaceSearchResult,
)


class PlaceSearchService:
    """Server-side adapter around Google Places API (New) Text Search."""

    SEARCH_URL = "https://places.googleapis.com/v1/places:searchText"

    def __init__(
        self,
        *,
        api_key: str | None = None,
        timeout_seconds: float = 15.0,
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

    def search(self, request: PlaceSearchRequest) -> PlaceSearchResponse:
        if not self.configured:
            raise RuntimeError(
                "FOODSENSE_GOOGLE_ROUTES_API_KEY is not configured."
            )

        query = request.query.strip()
        if not query:
            raise ValueError("Search query cannot be empty.")

        payload: dict[str, Any] = {
            "textQuery": query,
            "pageSize": 6,
            "languageCode": "en",
            "regionCode": "IN",
        }

        if request.latitude is not None and request.longitude is not None:
            payload["locationBias"] = {
                "circle": {
                    "center": {
                        "latitude": request.latitude,
                        "longitude": request.longitude,
                    },
                    "radius": 50000.0,
                }
            }

        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self._api_key,
            "X-Goog-FieldMask": (
                "places.id,places.displayName,"
                "places.formattedAddress,places.location"
            ),
        }

        try:
            with httpx.Client(timeout=self._timeout_seconds) as client:
                response = client.post(
                    self.SEARCH_URL,
                    headers=headers,
                    json=payload,
                )
        except httpx.HTTPError as exc:
            raise RuntimeError(
                "Google Places API could not be reached."
            ) from exc

        if response.status_code < 200 or response.status_code >= 300:
            message = "Google Places API search failed."

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
                "Google Places API returned invalid JSON."
            ) from exc

        raw_places = body.get("places") or []
        results: list[PlaceSearchResult] = []

        for raw_place in raw_places:
            if not isinstance(raw_place, dict):
                continue

            location = raw_place.get("location") or {}
            display_name = raw_place.get("displayName") or {}
            place_id = str(raw_place.get("id") or "").strip()
            latitude = location.get("latitude")
            longitude = location.get("longitude")

            if (
                not place_id
                or not isinstance(latitude, (int, float))
                or not isinstance(longitude, (int, float))
            ):
                continue

            results.append(
                PlaceSearchResult(
                    placeId=place_id,
                    name=str(display_name.get("text") or "Place"),
                    address=str(
                        raw_place.get("formattedAddress")
                        or "Address unavailable"
                    ),
                    latitude=float(latitude),
                    longitude=float(longitude),
                )
            )

        return PlaceSearchResponse(results=results)
