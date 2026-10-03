import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'delivery_job.dart';
import 'delivery_route.dart';

class DeliveryRouteMap extends StatefulWidget {
  const DeliveryRouteMap({
    required this.job,
    required this.route,
    required this.showCurrentLocation,
    super.key,
  });

  final DeliveryJob job;
  final DeliveryRouteOption? route;
  final bool showCurrentLocation;

  @override
  State<DeliveryRouteMap> createState() => _DeliveryRouteMapState();
}

class _DeliveryRouteMapState extends State<DeliveryRouteMap> {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  @override
  void didUpdateWidget(covariant DeliveryRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.route?.encodedPolyline !=
        oldWidget.route?.encodedPolyline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitRoute();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<Marker> markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(
          widget.job.pickup.latitude,
          widget.job.pickup.longitude,
        ),
        infoWindow: InfoWindow(
          title: 'Pickup',
          snippet: widget.job.pickupAddress,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueOrange,
        ),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(
          widget.job.dropoff.latitude,
          widget.job.dropoff.longitude,
        ),
        infoWindow: InfoWindow(
          title: 'Drop-off',
          snippet: widget.job.dropoffAddress,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueGreen,
        ),
      ),
    };

    if (widget.showCurrentLocation &&
        widget.job.currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(
            widget.job.currentLocation!.latitude,
            widget.job.currentLocation!.longitude,
          ),
          infoWindow: InfoWindow(
            title: 'Delivery partner',
            snippet: widget.job.deliveryPartnerName,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    return Stack(
      children: <Widget>[
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _initialTarget(),
            zoom: 13,
          ),
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          markers: markers,
          polylines: _buildPolylines(),
          onMapCreated: (GoogleMapController controller) {
            if (!_controller.isCompleted) {
              _controller.complete(controller);
            }
            _fitRoute();
          },
        ),
        Positioned(
          right: 12,
          top: 12,
          child: FloatingActionButton.small(
            heroTag: 'fit-route',
            onPressed: _fitRoute,
            tooltip: 'Fit route',
            child: const Icon(Icons.center_focus_strong_rounded),
          ),
        ),
      ],
    );
  }

  LatLng _initialTarget() {
    if (widget.showCurrentLocation &&
        widget.job.currentLocation != null) {
      return LatLng(
        widget.job.currentLocation!.latitude,
        widget.job.currentLocation!.longitude,
      );
    }

    return LatLng(
      widget.job.pickup.latitude,
      widget.job.pickup.longitude,
    );
  }

  Set<Polyline> _buildPolylines() {
    final DeliveryRouteOption? route = widget.route;
    if (route == null || route.encodedPolyline.isEmpty) {
      return <Polyline>{};
    }

    final List<LatLng> points = _decodePolyline(route.encodedPolyline);
    if (points.length < 2) {
      return <Polyline>{};
    }

    final Set<Polyline> polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route-underlay'),
        points: points,
        width: 9,
        color: Colors.black26,
        zIndex: 1,
      ),
    };

    if (route.trafficIntervals.isEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          width: 7,
          color: Colors.green,
          zIndex: 2,
        ),
      );
      return polylines;
    }

    int cursor = 0;

    for (int index = 0;
        index < route.trafficIntervals.length;
        index++) {
      final TrafficInterval interval = route.trafficIntervals[index];

      int start = interval.startPolylinePointIndex;
      int end = interval.endPolylinePointIndex;

      start = start.clamp(0, points.length - 1);
      end = end.clamp(start + 1, points.length);

      if (start > cursor) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('traffic-gap-$index'),
            points: points.sublist(cursor, start + 1),
            width: 7,
            color: Colors.green,
            zIndex: 2,
          ),
        );
      }

      if (end > start) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('traffic-$index'),
            points: points.sublist(start, end),
            width: 7,
            color: _trafficColor(interval.speed),
            zIndex: 3,
          ),
        );
        cursor = end - 1;
      }
    }

    if (cursor < points.length - 1) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('traffic-tail'),
          points: points.sublist(cursor),
          width: 7,
          color: Colors.green,
          zIndex: 2,
        ),
      );
    }

    return polylines;
  }

  Color _trafficColor(String speed) {
    switch (speed.toUpperCase()) {
      case 'TRAFFIC_JAM':
        return Colors.red;
      case 'SLOW':
        return Colors.orange;
      case 'NORMAL':
      default:
        return Colors.green;
    }
  }

  Future<void> _fitRoute() async {
    if (!_controller.isCompleted) return;

    final DeliveryRouteOption? route = widget.route;
    List<LatLng> points = <LatLng>[
      LatLng(
        widget.job.pickup.latitude,
        widget.job.pickup.longitude,
      ),
      LatLng(
        widget.job.dropoff.latitude,
        widget.job.dropoff.longitude,
      ),
    ];

    if (widget.showCurrentLocation &&
        widget.job.currentLocation != null) {
      points.add(
        LatLng(
          widget.job.currentLocation!.latitude,
          widget.job.currentLocation!.longitude,
        ),
      );
    }

    if (route != null && route.encodedPolyline.isNotEmpty) {
      final List<LatLng> decoded =
          _decodePolyline(route.encodedPolyline);
      if (decoded.length > 1) {
        points = decoded;
      }
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final LatLng point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final GoogleMapController controller = await _controller.future;

    if ((maxLat - minLat).abs() < 0.001 &&
        (maxLng - minLng).abs() < 0.001) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: points.first,
            zoom: 16,
          ),
        ),
      );
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = <LatLng>[];

    int index = 0;
    int latitude = 0;
    int longitude = 0;

    while (index < encoded.length) {
      int result = 0;
      int shift = 0;

      while (true) {
        if (index >= encoded.length) return points;

        final int byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;

        if (byte < 0x20) break;
      }

      latitude +=
          (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      result = 0;
      shift = 0;

      while (true) {
        if (index >= encoded.length) return points;

        final int byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;

        if (byte < 0x20) break;
      }

      longitude +=
          (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      points.add(
        LatLng(
          latitude / 100000.0,
          longitude / 100000.0,
        ),
      );
    }

    return points;
  }
}
