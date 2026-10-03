import 'package:cloud_firestore/cloud_firestore.dart';

enum RedistributionStatus {
  pending,
  accepted,
  pickupScheduled,
  collected,
  delivered,
  completed,
  rejected,
  cancelled,
  expired,
}

String redistributionStatusValue(RedistributionStatus status) {
  switch (status) {
    case RedistributionStatus.pending:
      return 'pending';
    case RedistributionStatus.accepted:
      return 'accepted';
    case RedistributionStatus.pickupScheduled:
      return 'pickup_scheduled';
    case RedistributionStatus.collected:
      return 'collected';
    case RedistributionStatus.delivered:
      return 'delivered';
    case RedistributionStatus.completed:
      return 'completed';
    case RedistributionStatus.rejected:
      return 'rejected';
    case RedistributionStatus.cancelled:
      return 'cancelled';
    case RedistributionStatus.expired:
      return 'expired';
  }
}

RedistributionStatus redistributionStatusFromValue(String? value) {
  switch (value) {
    case 'accepted':
      return RedistributionStatus.accepted;
    case 'pickup_scheduled':
      return RedistributionStatus.pickupScheduled;
    case 'collected':
      return RedistributionStatus.collected;
    case 'delivered':
      return RedistributionStatus.delivered;
    case 'completed':
      return RedistributionStatus.completed;
    case 'rejected':
      return RedistributionStatus.rejected;
    case 'cancelled':
      return RedistributionStatus.cancelled;
    case 'expired':
      return RedistributionStatus.expired;
    case 'pending':
    default:
      return RedistributionStatus.pending;
  }
}

String redistributionStatusLabel(RedistributionStatus status) {
  switch (status) {
    case RedistributionStatus.pending:
      return 'Pending';
    case RedistributionStatus.accepted:
      return 'Accepted';
    case RedistributionStatus.pickupScheduled:
      return 'Pickup scheduled';
    case RedistributionStatus.collected:
      return 'Collected';
    case RedistributionStatus.delivered:
      return 'Delivered';
    case RedistributionStatus.completed:
      return 'Completed';
    case RedistributionStatus.rejected:
      return 'Rejected';
    case RedistributionStatus.cancelled:
      return 'Cancelled';
    case RedistributionStatus.expired:
      return 'Expired';
  }
}

DateTime? _dateFromFirestore(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  return null;
}

class RedistributionRequest {
  const RedistributionRequest({
    required this.id,
    required this.organizationId,
    required this.status,
    required this.recipientName,
    required this.recipientType,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.address,
    required this.foodName,
    required this.quantity,
    required this.unit,
    required this.sourceSurplusId,
    required this.notes,
    required this.requestedFor,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String organizationId;
  final RedistributionStatus status;

  final String recipientName;
  final String recipientType;
  final String contactName;
  final String phone;
  final String email;
  final String address;

  final String foodName;
  final double quantity;
  final String unit;

  final String sourceSurplusId;
  final String notes;

  final DateTime? requestedFor;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory RedistributionRequest.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data = document.data() ?? <String, dynamic>{};

    return RedistributionRequest(
      id: document.id,
      organizationId: (data['organizationId'] as String?) ?? '',
      status: redistributionStatusFromValue(data['status'] as String?),
      recipientName: (data['recipientName'] as String?) ?? '',
      recipientType: (data['recipientType'] as String?) ?? '',
      contactName: (data['contactName'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      address: (data['address'] as String?) ?? '',
      foodName: (data['foodName'] as String?) ?? '',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      unit: (data['unit'] as String?) ?? 'kg',
      sourceSurplusId: (data['sourceSurplusId'] as String?) ?? '',
      notes: (data['notes'] as String?) ?? '',
      requestedFor: _dateFromFirestore(data['requestedFor']),
      createdBy: (data['createdBy'] as String?) ?? '',
      createdAt: _dateFromFirestore(data['createdAt']),
      updatedAt: _dateFromFirestore(data['updatedAt']),
    );
  }

  Map<String, Object?> toMapForCreate() {
    return <String, Object?>{
      'organizationId': organizationId,
      'status': redistributionStatusValue(status),
      'recipientName': recipientName,
      'recipientType': recipientType,
      'contactName': contactName,
      'phone': phone,
      'email': email,
      'address': address,
      'foodName': foodName,
      'quantity': quantity,
      'unit': unit,
      'sourceSurplusId': sourceSurplusId,
      'notes': notes,
      'requestedFor': requestedFor == null
          ? null
          : Timestamp.fromDate(requestedFor!),
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
