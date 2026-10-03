from __future__ import annotations

from unittest.mock import patch

import httpx

from app.schemas.place_search_schema import PlaceSearchRequest
from app.services.place_search_service import PlaceSearchService


def test_place_search_service_calls_google_places_and_parses_results() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == httpx.URL(
            "https://places.googleapis.com/v1/places:searchText"
        )
        assert request.headers["X-Goog-Api-Key"] == "test-key"
        assert "places.location" in request.headers["X-Goog-FieldMask"]

        payload = request.read().decode("utf-8")
        assert "REC Bijnor" in payload

        return httpx.Response(
            200,
            json={
                "places": [
                    {
                        "id": "place-1",
                        "displayName": {"text": "REC Bijnor"},
                        "formattedAddress": "Bijnor, Uttar Pradesh, India",
                        "location": {
                            "latitude": 29.3732,
                            "longitude": 78.1351,
                        },
                    },
                ],
            },
        )

    with patch(
        "app.services.place_search_service.httpx.Client",
        return_value=httpx.Client(
            transport=httpx.MockTransport(handler),
        ),
    ):
        result = PlaceSearchService(api_key="test-key").search(
            PlaceSearchRequest(
                organizationId="org-1",
                query="REC Bijnor",
                latitude=29.3732,
                longitude=78.1351,
            )
        )

    assert len(result.results) == 1

    place = result.results[0]
    assert place.placeId == "place-1"
    assert place.name == "REC Bijnor"
    assert place.address == "Bijnor, Uttar Pradesh, India"
    assert place.latitude == 29.3732
    assert place.longitude == 78.1351
