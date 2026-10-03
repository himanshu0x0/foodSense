from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class RoutePoint(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)


class DeliveryRoutingRequest(BaseModel):
    organizationId: str = Field(min_length=1)
    origin: RoutePoint
    destination: RoutePoint
    departureTime: datetime | None = None


class TrafficInterval(BaseModel):
    startPolylinePointIndex: int = Field(ge=0)
    endPolylinePointIndex: int = Field(gt=0)
    speed: str


class RouteOption(BaseModel):
    label: str
    distanceMeters: int = Field(ge=0)
    durationSeconds: int = Field(ge=0)
    staticDurationSeconds: int = Field(ge=0)
    trafficLevel: str
    encodedPolyline: str
    trafficIntervals: list[TrafficInterval]


class DeliveryRoutingResponse(BaseModel):
    options: list[RouteOption]
    recommendedIndex: int = Field(ge=0)
    generatedAt: datetime
