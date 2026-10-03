from datetime import datetime, timezone

from app.schemas.delivery_routing_schema import (
    DeliveryRoutingRequest,
    RoutePoint,
    TrafficInterval,
)
from app.services.delivery_routing_service import (
    DeliveryRoutingService,
)


def test_duration_parser_handles_seconds():
    assert (
        DeliveryRoutingService._duration_seconds("123.6s")
        == 124
    )


def test_duration_parser_handles_invalid_values():
    assert (
        DeliveryRoutingService._duration_seconds("invalid")
        == 0
    )
    assert (
        DeliveryRoutingService._duration_seconds(None)
        == 0
    )


def test_traffic_level_is_heavy_when_jam_is_present():
    intervals = [
        TrafficInterval(
            startPolylinePointIndex=0,
            endPolylinePointIndex=5,
            speed="NORMAL",
        ),
        TrafficInterval(
            startPolylinePointIndex=5,
            endPolylinePointIndex=10,
            speed="TRAFFIC_JAM",
        ),
    ]

    assert (
        DeliveryRoutingService._traffic_level(intervals)
        == "heavy"
    )


def test_traffic_level_is_moderate_when_slow_is_present():
    intervals = [
        TrafficInterval(
            startPolylinePointIndex=0,
            endPolylinePointIndex=8,
            speed="SLOW",
        ),
    ]

    assert (
        DeliveryRoutingService._traffic_level(intervals)
        == "moderate"
    )


def test_traffic_level_is_low_when_intervals_are_normal():
    intervals = [
        TrafficInterval(
            startPolylinePointIndex=0,
            endPolylinePointIndex=8,
            speed="NORMAL",
        ),
    ]

    assert (
        DeliveryRoutingService._traffic_level(intervals)
        == "low"
    )


def test_routing_request_validates_coordinates():
    request = DeliveryRoutingRequest(
        organizationId="org-123",
        origin=RoutePoint(
            latitude=28.9845,
            longitude=77.7064,
        ),
        destination=RoutePoint(
            latitude=29.0012,
            longitude=77.7137,
        ),
        departureTime=datetime.now(timezone.utc),
    )

    assert request.origin.latitude == 28.9845
    assert request.destination.longitude == 77.7137
