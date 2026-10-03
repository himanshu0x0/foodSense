import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'redistribution_request.dart';
import 'redistribution_status_service.dart';

class RedistributionRepository {
  RedistributionRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    RedistributionStatusService? statusService,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _statusService = statusService ?? RedistributionStatusService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final RedistributionStatusService _statusService;

  CollectionReference<Map<String, dynamic>> _collection(String organizationId) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('redistribution');
  }

  Stream<List<RedistributionRequest>> watchRequests({
    required String organizationId,
  }) {
    if (organizationId.trim().isEmpty) {
      return const Stream<List<RedistributionRequest>>.empty();
    }

    return _collection(organizationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (QuerySnapshot<Map<String, dynamic>> snapshot) =>
              snapshot.docs.map(RedistributionRequest.fromDocument).toList(),
        );
  }

  Future<String> createRequest({
    required String organizationId,
    required String recipientName,
    required String recipientType,
    required String contactName,
    required String phone,
    required String email,
    required String address,
    required String foodName,
    required double quantity,
    required String unit,
    required String sourceSurplusId,
    required String notes,
    required DateTime? requestedFor,
  }) async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('Please sign in again.');
    }

    final String normalizedOrganizationId = organizationId.trim();
    final String normalizedRecipient = recipientName.trim();
    final String normalizedFood = foodName.trim();

    if (normalizedOrganizationId.isEmpty) {
      throw ArgumentError('Organization ID is required.');
    }

    if (normalizedRecipient.isEmpty) {
      throw ArgumentError('Recipient name is required.');
    }

    if (normalizedFood.isEmpty) {
      throw ArgumentError('Food name is required.');
    }

    if (quantity <= 0) {
      throw ArgumentError('Quantity must be greater than zero.');
    }

    if (requestedFor != null &&
        requestedFor.isBefore(
          DateTime.now().subtract(const Duration(minutes: 1)),
        )) {
      throw ArgumentError(
        'Requested pickup/delivery time cannot be in the past.',
      );
    }

    final DocumentReference<Map<String, dynamic>> reference = _collection(
      normalizedOrganizationId,
    ).doc();

    final RedistributionRequest request = RedistributionRequest(
      id: reference.id,
      organizationId: normalizedOrganizationId,
      status: RedistributionStatus.pending,
      recipientName: normalizedRecipient,
      recipientType: recipientType.trim(),
      contactName: contactName.trim(),
      phone: phone.trim(),
      email: email.trim(),
      address: address.trim(),
      foodName: normalizedFood,
      quantity: quantity,
      unit: unit.trim().isEmpty ? 'kg' : unit.trim(),
      sourceSurplusId: sourceSurplusId.trim(),
      notes: notes.trim(),
      requestedFor: requestedFor,
      createdBy: user.uid,
      createdAt: null,
      updatedAt: null,
    );

    await reference.set(request.toMapForCreate());

    return reference.id;
  }

  Future<void> updateStatus({
    required String organizationId,
    required String requestId,
    required RedistributionStatus status,
  }) async {
    final String normalizedOrganizationId = organizationId.trim();
    final String normalizedRequestId = requestId.trim();

    if (normalizedOrganizationId.isEmpty || normalizedRequestId.isEmpty) {
      throw ArgumentError('Organization ID and request ID are required.');
    }

    final DocumentReference<Map<String, dynamic>> reference = _collection(
      normalizedOrganizationId,
    ).doc(normalizedRequestId);

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await reference
        .get();

    if (!snapshot.exists) {
      throw StateError('Redistribution request not found.');
    }

    final RedistributionRequest request = RedistributionRequest.fromDocument(
      snapshot,
    );

    _statusService.validateTransition(request.status, status);

    if (request.status == status) {
      return;
    }

    await reference.update(<String, Object?>{
      'status': redistributionStatusValue(status),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelRequest({
    required String organizationId,
    required String requestId,
  }) {
    return updateStatus(
      organizationId: organizationId,
      requestId: requestId,
      status: RedistributionStatus.cancelled,
    );
  }

  Future<RedistributionRequest?> getRequest({
    required String organizationId,
    required String requestId,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _collection(
      organizationId.trim(),
    ).doc(requestId.trim()).get();

    if (!snapshot.exists) {
      return null;
    }

    return RedistributionRequest.fromDocument(snapshot);
  }

  String friendlyError(Object error) {
    final String message = error.toString();

    if (message.contains('permission-denied')) {
      return 'Manager access is required for redistribution operations.';
    }

    if (message.contains('signed in')) {
      return 'Please sign in again.';
    }

    if (message.contains('not found')) {
      return 'The redistribution request no longer exists.';
    }

    if (message.contains('Invalid redistribution status')) {
      return message.replaceFirst('Bad state: ', '');
    }

    return 'Unable to complete the redistribution operation. Please try again.';
  }
}
