import 'package:cloud_firestore/cloud_firestore.dart';

class DeliveryPartner {
  const DeliveryPartner({
    required this.userId,
    required this.organizationId,
    required this.name,
    required this.phone,
    required this.vehicleType,
    required this.vehicleNumber,
    required this.active,
    this.createdAt,
    this.updatedAt,
  });

  final String userId;
  final String organizationId;
  final String name;
  final String phone;
  final String vehicleType;
  final String vehicleNumber;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory DeliveryPartner.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final Map<String, dynamic> data = document.data() ?? <String, dynamic>{};

    DateTime? date(Object? value) {
      if (value is Timestamp) return value.toDate();
      return value is DateTime ? value : null;
    }

    return DeliveryPartner(
      userId: (data['userId'] as String?) ?? document.id,
      organizationId: (data['organizationId'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      vehicleType: (data['vehicleType'] as String?) ?? 'Two wheeler',
      vehicleNumber: (data['vehicleNumber'] as String?) ?? '',
      active: (data['active'] as bool?) ?? true,
      createdAt: date(data['createdAt']),
      updatedAt: date(data['updatedAt']),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'userId': userId,
    'organizationId': organizationId,
    'name': name,
    'phone': phone,
    'vehicleType': vehicleType,
    'vehicleNumber': vehicleNumber,
    'active': active,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
