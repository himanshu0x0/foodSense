import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'delivery_job.dart';
import 'delivery_partner.dart';

class DeliveryRepository {
  DeliveryRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _org(String organizationId) =>
      _firestore.collection('organizations').doc(organizationId.trim());

  CollectionReference<Map<String, dynamic>> _partners(String organizationId) =>
      _org(organizationId).collection('delivery_partners');

  CollectionReference<Map<String, dynamic>> _deliveries(
    String organizationId,
  ) => _org(organizationId).collection('deliveries');

  CollectionReference<Map<String, dynamic>> _events(
    String organizationId,
    String deliveryId,
  ) => _deliveries(organizationId).doc(deliveryId).collection('events');

  Future<bool> isManager(String organizationId) async {
    final User? user = _auth.currentUser;
    if (user == null) return false;

    final DocumentSnapshot<Map<String, dynamic>> org = await _org(
      organizationId,
    ).get();

    if (!org.exists) return false;

    final Map<String, dynamic> data = org.data() ?? <String, dynamic>{};

    if (data['ownerId'] == user.uid) return true;

    final DocumentSnapshot<Map<String, dynamic>> member = await _org(
      organizationId,
    ).collection('members').doc(user.uid).get();

    final String role = (member.data()?['role'] as String?) ?? '';
    return role == 'manager' || role == 'owner';
  }

  Stream<List<DeliveryJob>> watchJobs({
    required String organizationId,
    required bool manager,
  }) {
    final User? user = _auth.currentUser;

    if (user == null || organizationId.trim().isEmpty) {
      return const Stream<List<DeliveryJob>>.empty();
    }

    Query<Map<String, dynamic>> query = _deliveries(organizationId);

    if (!manager) {
      query = query.where('deliveryPartnerId', isEqualTo: user.uid);
    }

    return query.snapshots().map((
      QuerySnapshot<Map<String, dynamic>> snapshot,
    ) {
      final List<DeliveryJob> jobs = snapshot.docs
          .map(DeliveryJob.fromDocument)
          .toList();

      jobs.sort(
        (DeliveryJob a, DeliveryJob b) =>
            (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ),
      );

      return jobs;
    });
  }

  Stream<List<DeliveryPartner>> watchPartners({
    required String organizationId,
  }) {
    if (organizationId.trim().isEmpty) {
      return const Stream<List<DeliveryPartner>>.empty();
    }

    return _partners(organizationId)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          final List<DeliveryPartner> partners = snapshot.docs
              .map(DeliveryPartner.fromDocument)
              .where((DeliveryPartner partner) => partner.active)
              .toList();

          partners.sort(
            (DeliveryPartner a, DeliveryPartner b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

          return partners;
        });
  }

  Future<DeliveryPartner?> getMyPartner({
    required String organizationId,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) return null;

    final DocumentSnapshot<Map<String, dynamic>> doc = await _partners(
      organizationId,
    ).doc(user.uid).get();

    if (!doc.exists) return null;

    return DeliveryPartner.fromDocument(doc);
  }

  Future<void> saveMyPartner({
    required String organizationId,
    required String name,
    required String phone,
    required String vehicleType,
    required String vehicleNumber,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in again.');
    }

    final String normalizedName = name.trim();

    if (normalizedName.isEmpty) {
      throw ArgumentError('Delivery partner name is required.');
    }

    await _partners(organizationId).doc(user.uid).set(<String, Object?>{
      'userId': user.uid,
      'organizationId': organizationId,
      'name': normalizedName,
      'phone': phone.trim(),
      'vehicleType': vehicleType.trim(),
      'vehicleNumber': vehicleNumber.trim(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> createDelivery({
    required String organizationId,
    required String deliveryPartnerId,
    required String deliveryPartnerName,
    required String vehicleType,
    required String vehicleNumber,
    required GeoPointData pickup,
    required String pickupAddress,
    required GeoPointData dropoff,
    required String dropoffAddress,
    required String foodName,
    required double quantity,
    required String unit,
    required String redistributionRequestId,
    required String sourceSurplusId,
    required DateTime? scheduledAt,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in again.');
    }

    if (quantity <= 0) {
      throw ArgumentError('Food quantity must be greater than zero.');
    }

    final DocumentReference<Map<String, dynamic>> doc = _deliveries(
      organizationId,
    ).doc();

    final DeliveryJob job = DeliveryJob(
      id: doc.id,
      organizationId: organizationId,
      redistributionRequestId: redistributionRequestId.trim(),
      sourceSurplusId: sourceSurplusId.trim(),
      status: DeliveryStatus.assigned,
      deliveryPartnerId: deliveryPartnerId.trim(),
      deliveryPartnerName: deliveryPartnerName.trim(),
      vehicleType: vehicleType.trim(),
      vehicleNumber: vehicleNumber.trim(),
      pickupAddress: pickupAddress.trim(),
      pickup: pickup,
      dropoffAddress: dropoffAddress.trim(),
      dropoff: dropoff,
      foodName: foodName.trim(),
      quantity: quantity,
      unit: unit.trim().isEmpty ? 'kg' : unit.trim(),
      scheduledAt: scheduledAt,
      createdBy: user.uid,
      currentLocation: null,
      currentLocationUpdatedAt: null,
      route: null,
      createdAt: null,
      updatedAt: null,
    );

    await doc.set(job.toCreateMap());

    await addEvent(
      organizationId: organizationId,
      deliveryId: doc.id,
      type: 'assigned',
      message: 'Delivery assigned to ${job.deliveryPartnerName}.',
    );

    return doc.id;
  }

  Future<DeliveryJob?> getDelivery({
    required String organizationId,
    required String deliveryId,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> doc = await _deliveries(
      organizationId,
    ).doc(deliveryId).get();

    if (!doc.exists) return null;

    return DeliveryJob.fromDocument(doc);
  }

  Future<void> updateStatus({
    required String organizationId,
    required String deliveryId,
    required DeliveryStatus status,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in again.');
    }

    final DeliveryJob? job = await getDelivery(
      organizationId: organizationId,
      deliveryId: deliveryId,
    );

    if (job == null) {
      throw StateError('Delivery job not found.');
    }

    final bool manager = await isManager(organizationId);

    if (!manager && job.deliveryPartnerId != user.uid) {
      throw StateError('You are not assigned to this delivery.');
    }

    _validateTransition(job.status, status);

    if (job.status == status) return;

    await _deliveries(organizationId).doc(deliveryId).update(<String, Object?>{
      'status': deliveryStatusValue(status),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await addEvent(
      organizationId: organizationId,
      deliveryId: deliveryId,
      type: deliveryStatusValue(status),
      message: deliveryStatusLabel(status),
    );
  }

  Future<void> updateCurrentLocation({
    required String organizationId,
    required String deliveryId,
    required GeoPointData location,
  }) async {
    await _deliveries(organizationId).doc(deliveryId).update(<String, Object?>{
      'currentLocation': location.toMap(),
      'currentLocationUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveRouteSnapshot({
    required String organizationId,
    required String deliveryId,
    required DeliveryRouteSnapshot snapshot,
  }) async {
    await _deliveries(organizationId).doc(deliveryId).update(<String, Object?>{
      'route': snapshot.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<DeliveryEvent>> watchEvents({
    required String organizationId,
    required String deliveryId,
  }) {
    return _events(organizationId, deliveryId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (QuerySnapshot<Map<String, dynamic>> snapshot) =>
              snapshot.docs.map(DeliveryEvent.fromDocument).toList(),
        );
  }

  Future<void> addEvent({
    required String organizationId,
    required String deliveryId,
    required String type,
    required String message,
  }) async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('Please sign in again.');
    }

    await _events(organizationId, deliveryId).add(<String, Object?>{
      'type': type,
      'message': message,
      'actorId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static void _validateTransition(DeliveryStatus from, DeliveryStatus to) {
    final Set<DeliveryStatus> allowed;

    switch (from) {
      case DeliveryStatus.assigned:
        allowed = <DeliveryStatus>{
          DeliveryStatus.enRoutePickup,
          DeliveryStatus.cancelled,
        };
        break;
      case DeliveryStatus.enRoutePickup:
        allowed = <DeliveryStatus>{
          DeliveryStatus.arrivedPickup,
          DeliveryStatus.cancelled,
        };
        break;
      case DeliveryStatus.arrivedPickup:
        allowed = <DeliveryStatus>{
          DeliveryStatus.pickedUp,
          DeliveryStatus.cancelled,
        };
        break;
      case DeliveryStatus.pickedUp:
        allowed = <DeliveryStatus>{DeliveryStatus.enRouteDelivery};
        break;
      case DeliveryStatus.enRouteDelivery:
        allowed = <DeliveryStatus>{
          DeliveryStatus.arrivedDropoff,
          DeliveryStatus.cancelled,
        };
        break;
      case DeliveryStatus.arrivedDropoff:
        allowed = <DeliveryStatus>{DeliveryStatus.delivered};
        break;
      case DeliveryStatus.delivered:
      case DeliveryStatus.cancelled:
        allowed = <DeliveryStatus>{};
        break;
    }

    if (from != to && !allowed.contains(to)) {
      throw StateError(
        'Invalid delivery transition: '
        '${deliveryStatusLabel(from)} -> '
        '${deliveryStatusLabel(to)}.',
      );
    }
  }
}
