from __future__ import annotations

from pydantic import BaseModel, Field


class PlaceSearchRequest(BaseModel):
    organizationId: str = Field(min_length=1)
    query: str = Field(min_length=1, max_length=200)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)


class PlaceSearchResult(BaseModel):
    placeId: str
    name: str
    address: str
    latitude: float
    longitude: float


class PlaceSearchResponse(BaseModel):
    results: list[PlaceSearchResult]
