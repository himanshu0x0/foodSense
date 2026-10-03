import 'package:cloud_firestore/cloud_firestore.dart';

enum DeliveryStatus {
  assigned,
  enRoutePickup,
  arrivedPickup,
  pickedUp,
  enRouteDelivery,
  arrivedDropoff,
  delivered,
  cancelled,
}

String deliveryStatusValue(DeliveryStatus status) {
  switch (status) {
    case DeliveryStatus.assigned:
      return 'assigned';
    case DeliveryStatus.enRoutePickup:
      return 'en_route_pickup';
    case DeliveryStatus.arrivedPickup:
      return 'arrived_pickup';
    case DeliveryStatus.pickedUp:
      return 'picked_up';
    case DeliveryStatus.enRouteDelivery:
      return 'en_route_delivery';
    case DeliveryStatus.arrivedDropoff:
      return 'arrived_dropoff';
    case DeliveryStatus.delivered:
      return 'delivered';
    case DeliveryStatus.cancelled:
      return 'cancelled';
  }
}

DeliveryStatus deliveryStatusFromValue(String? value) {
  switch (value) {
    case 'en_route_pickup':
      return DeliveryStatus.enRoutePickup;
    case 'arrived_pickup':
      return DeliveryStatus.arrivedPickup;
    case 'picked_up':
      return DeliveryStatus.pickedUp;
    case 'en_route_delivery':
      return DeliveryStatus.enRouteDelivery;
    case 'arrived_dropoff':
      return DeliveryStatus.arrivedDropoff;
    case 'delivered':
      return DeliveryStatus.delivered;
    case 'cancelled':
      return DeliveryStatus.cancelled;
    case 'assigned':
    default:
      return DeliveryStatus.assigned;
  }
}

String deliveryStatusLabel(DeliveryStatus status) {
  switch (status) {
    case DeliveryStatus.assigned:
      return 'Assigned';
    case DeliveryStatus.enRoutePickup:
      return 'En route to pickup';
    case DeliveryStatus.arrivedPickup:
      return 'Arrived at pickup';
    case DeliveryStatus.pickedUp:
      return 'Picked up';
    case DeliveryStatus.enRouteDelivery:
      return 'En route to drop-off';
    case DeliveryStatus.arrivedDropoff:
      return 'Arrived at drop-off';
    case DeliveryStatus.delivered:
      return 'Delivered';
    case DeliveryStatus.cancelled:
      return 'Cancelled';
  }
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  return value is DateTime ? value : null;
}

class GeoPointData {
  const GeoPointData({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.heading,
    this.speedMps,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final double? heading;
  final double? speedMps;

  factory GeoPointData.fromMap(Object? value) {
    if (value is GeoPoint) {
      return GeoPointData(latitude: value.latitude, longitude: value.longitude);
    }

    if (value is Map) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(value);
      return GeoPointData(
        latitude:
            (data['latitude'] as num?)?.toDouble() ??
            (data['lat'] as num?)?.toDouble() ??
            0,
        longitude:
            (data['longitude'] as num?)?.toDouble() ??
            (data['lng'] as num?)?.toDouble() ??
            0,
        accuracyMeters: (data['accuracyMeters'] as num?)?.toDouble(),
        heading: (data['heading'] as num?)?.toDouble(),
        speedMps: (data['speedMps'] as num?)?.toDouble(),
      );
    }

    return const GeoPointData(latitude: 0, longitude: 0);
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'latitude': latitude,
    'longitude': longitude,
    if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
    if (heading != null) 'heading': heading,
    if (speedMps != null) 'speedMps': speedMps,
  };
}

class DeliveryRouteSnapshot {
  const DeliveryRouteSnapshot({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.staticDurationSeconds,
    required this.delaySeconds,
    required this.trafficLevel,
    required this.encodedPolyline,
    this.refreshedAt,
  });

  final int distanceMeters;
  final int durationSeconds;
  final int staticDurationSeconds;
  final int delaySeconds;
  final String trafficLevel;
  final String encodedPolyline;
  final DateTime? refreshedAt;

  factory DeliveryRouteSnapshot.fromMap(Map<String, dynamic> data) {
    return DeliveryRouteSnapshot(
      distanceMeters: (data['distanceMeters'] as num?)?.toInt() ?? 0,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      staticDurationSeconds:
          (data['staticDurationSeconds'] as num?)?.toInt() ?? 0,
      delaySeconds: (data['delaySeconds'] as num?)?.toInt() ?? 0,
      trafficLevel: (data['trafficLevel'] as String?) ?? 'unknown',
      encodedPolyline: (data['encodedPolyline'] as String?) ?? '',
      refreshedAt: _date(data['refreshedAt']),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'staticDurationSeconds': staticDurationSeconds,
    'delaySeconds': delaySeconds,
    'trafficLevel': trafficLevel,
    'encodedPolyline': encodedPolyline,
    'refreshedAt': FieldValue.serverTimestamp(),
  };
}

class DeliveryJob {
  const DeliveryJob({
    required this.id,
    required this.organizationId,
    required this.redistributionRequestId,
    required this.sourceSurplusId,
    required this.status,
    required this.deliveryPartnerId,
    required this.deliveryPartnerName,
    required this.vehicleType,
    required this.vehicleNumber,
    required this.pickupAddress,
    required this.pickup,
    required this.dropoffAddress,
    required this.dropoff,
    required this.foodName,
    required this.quantity,
    required this.unit,
    required this.scheduledAt,
    required this.createdBy,
    required this.currentLocation,
    required this.currentLocationUpdatedAt,
    required this.route,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String organizationId;
  final String redistributionRequestId;
  final String sourceSurplusId;
  final DeliveryStatus status;

  final String deliveryPartnerId;
  final String deliveryPartnerName;
  final String vehicleType;
  final String vehicleNumber;

  final String pickupAddress;
  final GeoPointData pickup;
  final String dropoffAddress;
  final GeoPointData dropoff;

  final String foodName;
  final double quantity;
  final String unit;
  final DateTime? scheduledAt;
  final String createdBy;

  final GeoPointData? currentLocation;
  final DateTime? currentLocationUpdatedAt;
  final DeliveryRouteSnapshot? route;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory DeliveryJob.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data = document.data() ?? <String, dynamic>{};

    final Map<String, dynamic>? routeData = data['route'] is Map
        ? Map<String, dynamic>.from(data['route'] as Map)
        : null;

    return DeliveryJob(
      id: document.id,
      organizationId: (data['organizationId'] as String?) ?? '',
      redistributionRequestId:
          (data['redistributionRequestId'] as String?) ?? '',
      sourceSurplusId: (data['sourceSurplusId'] as String?) ?? '',
      status: deliveryStatusFromValue(data['status'] as String?),
      deliveryPartnerId: (data['deliveryPartnerId'] as String?) ?? '',
      deliveryPartnerName: (data['deliveryPartnerName'] as String?) ?? '',
      vehicleType: (data['vehicleType'] as String?) ?? '',
      vehicleNumber: (data['vehicleNumber'] as String?) ?? '',
      pickupAddress: (data['pickupAddress'] as String?) ?? '',
      pickup: GeoPointData.fromMap(data['pickup']),
      dropoffAddress: (data['dropoffAddress'] as String?) ?? '',
      dropoff: GeoPointData.fromMap(data['dropoff']),
      foodName: (data['foodName'] as String?) ?? '',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      unit: (data['unit'] as String?) ?? 'kg',
      scheduledAt: _date(data['scheduledAt']),
      createdBy: (data['createdBy'] as String?) ?? '',
      currentLocation: data['currentLocation'] == null
          ? null
          : GeoPointData.fromMap(data['currentLocation']),
      currentLocationUpdatedAt: _date(data['currentLocationUpdatedAt']),
      route: routeData == null
          ? null
          : DeliveryRouteSnapshot.fromMap(routeData),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  Map<String, Object?> toCreateMap() => <String, Object?>{
    'organizationId': organizationId,
    'redistributionRequestId': redistributionRequestId,
    'sourceSurplusId': sourceSurplusId,
    'status': deliveryStatusValue(status),
    'deliveryPartnerId': deliveryPartnerId,
    'deliveryPartnerName': deliveryPartnerName,
    'vehicleType': vehicleType,
    'vehicleNumber': vehicleNumber,
    'pickupAddress': pickupAddress,
    'pickup': GeoPoint(pickup.latitude, pickup.longitude),
    'dropoffAddress': dropoffAddress,
    'dropoff': GeoPoint(dropoff.latitude, dropoff.longitude),
    'foodName': foodName,
    'quantity': quantity,
    'unit': unit,
    'scheduledAt': scheduledAt == null
        ? null
        : Timestamp.fromDate(scheduledAt!),
    'createdBy': createdBy,
    'currentLocation': null,
    'currentLocationUpdatedAt': null,
    'route': null,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class DeliveryEvent {
  const DeliveryEvent({
    required this.id,
    required this.type,
    required this.message,
    required this.actorId,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String message;
  final String actorId;
  final DateTime? createdAt;

  factory DeliveryEvent.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data = document.data() ?? <String, dynamic>{};

    return DeliveryEvent(
      id: document.id,
      type: (data['type'] as String?) ?? 'event',
      message: (data['message'] as String?) ?? '',
      actorId: (data['actorId'] as String?) ?? '',
      createdAt: _date(data['createdAt']),
    );
  }
}
