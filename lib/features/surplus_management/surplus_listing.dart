import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle states for an actual surplus listing.
enum SurplusStatus {
  available,
  reserved,
  collected,
  distributed,
  expired,
  wasted,
  cancelled,
}

/// Operational condition label supplied by the kitchen/operator.
enum SurplusQuality { good, useSoon, review }

/// A persisted, organization-scoped surplus-food listing.
class SurplusListing {
  const SurplusListing({
    required this.id,
    required this.organizationId,
    required this.foodName,
    required this.mealType,
    required this.quantity,
    required this.unit,
    required this.quality,
    required this.status,
    required this.preparedAt,
    required this.availableUntil,
    required this.notes,
    required this.sourceType,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.sourceFoodRecordId,
  });

  final String id;
  final String organizationId;
  final String foodName;
  final String mealType;
  final double quantity;
  final String unit;
  final SurplusQuality quality;
  final SurplusStatus status;
  final DateTime preparedAt;
  final DateTime availableUntil;
  final String notes;
  final String sourceType;
  final String? sourceFoodRecordId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCurrentlyAvailable =>
      status == SurplusStatus.available &&
      availableUntil.isAfter(DateTime.now());

  bool get isPastAvailabilityWindow =>
      status == SurplusStatus.available &&
      !availableUntil.isAfter(DateTime.now());

  SurplusListing copyWith({
    String? foodName,
    String? mealType,
    double? quantity,
    String? unit,
    SurplusQuality? quality,
    SurplusStatus? status,
    DateTime? preparedAt,
    DateTime? availableUntil,
    String? notes,
    String? sourceType,
    String? sourceFoodRecordId,
    bool clearSourceFoodRecordId = false,
    String? updatedAtOverride,
  }) {
    return SurplusListing(
      id: id,
      organizationId: organizationId,
      foodName: foodName ?? this.foodName,
      mealType: mealType ?? this.mealType,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      quality: quality ?? this.quality,
      status: status ?? this.status,
      preparedAt: preparedAt ?? this.preparedAt,
      availableUntil: availableUntil ?? this.availableUntil,
      notes: notes ?? this.notes,
      sourceType: sourceType ?? this.sourceType,
      sourceFoodRecordId: clearSourceFoodRecordId
          ? null
          : (sourceFoodRecordId ?? this.sourceFoodRecordId),
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAtOverride == null
          ? updatedAt
          : DateTime.tryParse(updatedAtOverride) ?? updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'organizationId': organizationId,
      'foodName': foodName,
      'mealType': mealType,
      'quantity': quantity,
      'unit': unit,
      'quality': quality.name,
      'status': status.name,
      'preparedAt': Timestamp.fromDate(preparedAt),
      'availableUntil': Timestamp.fromDate(availableUntil),
      'notes': notes,
      'sourceType': sourceType,
      'sourceFoodRecordId': sourceFoodRecordId,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory SurplusListing.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data = document.data() ?? <String, dynamic>{};

    return SurplusListing(
      id: document.id,
      organizationId: _readString(data['organizationId']),
      foodName: _readString(data['foodName']),
      mealType: _readString(data['mealType'], fallback: 'Other'),
      quantity: _readDouble(data['quantity']),
      unit: _readString(data['unit'], fallback: 'kg'),
      quality: _parseQuality(data['quality']),
      status: _parseStatus(data['status']),
      preparedAt: _readDate(data['preparedAt'], fallback: DateTime.now()),
      availableUntil: _readDate(
        data['availableUntil'],
        fallback: DateTime.now(),
      ),
      notes: _readString(data['notes']),
      sourceType: _readString(data['sourceType'], fallback: 'manual'),
      sourceFoodRecordId: _readNullableString(data['sourceFoodRecordId']),
      createdBy: _readString(data['createdBy']),
      createdAt: _readDate(data['createdAt'], fallback: DateTime.now()),
      updatedAt: _readDate(data['updatedAt'], fallback: DateTime.now()),
    );
  }

  static String _readString(dynamic value, {String fallback = ''}) {
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  static String? _readNullableString(dynamic value) {
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static double _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _readDate(dynamic value, {required DateTime fallback}) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value) ?? fallback;
    }

    return fallback;
  }

  static SurplusStatus _parseStatus(dynamic value) {
    if (value is String) {
      for (final SurplusStatus status in SurplusStatus.values) {
        if (status.name == value) {
          return status;
        }
      }
    }

    return SurplusStatus.available;
  }

  static SurplusQuality _parseQuality(dynamic value) {
    if (value is String) {
      for (final SurplusQuality quality in SurplusQuality.values) {
        if (quality.name == value) {
          return quality;
        }
      }
    }

    return SurplusQuality.good;
  }
}

String surplusStatusLabel(SurplusStatus status) {
  switch (status) {
    case SurplusStatus.available:
      return 'Available';
    case SurplusStatus.reserved:
      return 'Reserved';
    case SurplusStatus.collected:
      return 'Collected';
    case SurplusStatus.distributed:
      return 'Distributed';
    case SurplusStatus.expired:
      return 'Expired';
    case SurplusStatus.wasted:
      return 'Wasted';
    case SurplusStatus.cancelled:
      return 'Cancelled';
  }
}

String surplusQualityLabel(SurplusQuality quality) {
  switch (quality) {
    case SurplusQuality.good:
      return 'Good';
    case SurplusQuality.useSoon:
      return 'Use soon';
    case SurplusQuality.review:
      return 'Review';
  }
}
