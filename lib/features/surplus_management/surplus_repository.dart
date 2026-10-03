import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'surplus_listing.dart';
import 'surplus_status_service.dart';

/// Firestore repository for organization-scoped actual surplus listings.
class SurplusRepository {
  SurplusRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    SurplusStatusService? statusService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _statusService = statusService ?? const SurplusStatusService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final SurplusStatusService _statusService;

  CollectionReference<Map<String, dynamic>> _collection(String organizationId) {
    final String organization = organizationId.trim();

    if (organization.isEmpty) {
      throw ArgumentError('Organization ID is required.');
    }

    return _firestore
        .collection('organizations')
        .doc(organization)
        .collection('surplus');
  }

  Future<void> _requireSignedIn() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('A signed-in user is required.');
    }
  }

  Stream<List<SurplusListing>> watchListings({required String organizationId}) {
    return _collection(organizationId)
        .orderBy('availableUntil')
        .snapshots()
        .map(
          (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
              .map(SurplusListing.fromDocument)
              .toList(growable: false),
        );
  }

  Future<SurplusListing> createListing({
    required String organizationId,
    required String foodName,
    required String mealType,
    required double quantity,
    required String unit,
    required SurplusQuality quality,
    required DateTime preparedAt,
    required DateTime availableUntil,
    required String notes,
  }) async {
    await _requireSignedIn();

    final String normalizedFoodName = foodName.trim();

    if (normalizedFoodName.isEmpty) {
      throw ArgumentError('Food name is required.');
    }

    if (quantity <= 0) {
      throw ArgumentError('Quantity must be greater than zero.');
    }

    if (!availableUntil.isAfter(preparedAt)) {
      throw ArgumentError(
        'Available-until time must be after the prepared time.',
      );
    }

    final User user = _auth.currentUser!;

    final DocumentReference<Map<String, dynamic>> document = _collection(
      organizationId,
    ).doc();

    final DateTime now = DateTime.now();

    final SurplusListing listing = SurplusListing(
      id: document.id,
      organizationId: organizationId.trim(),
      foodName: normalizedFoodName,
      mealType: mealType.trim().isEmpty ? 'Other' : mealType.trim(),
      quantity: quantity,
      unit: unit.trim().isEmpty ? 'kg' : unit.trim(),
      quality: quality,
      status: SurplusStatus.available,
      preparedAt: preparedAt,
      availableUntil: availableUntil,
      notes: notes.trim(),
      sourceType: 'manual',
      sourceFoodRecordId: null,
      createdBy: user.uid,
      createdAt: now,
      updatedAt: now,
    );

    await document.set(listing.toMap());

    return listing;
  }

  Future<SurplusListing> updateStatus({
    required String organizationId,
    required String surplusId,
    required SurplusStatus nextStatus,
  }) async {
    await _requireSignedIn();

    final DocumentReference<Map<String, dynamic>> document = _collection(
      organizationId,
    ).doc(surplusId.trim());

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await document
        .get();

    if (!snapshot.exists) {
      throw StateError('This surplus listing no longer exists.');
    }

    final SurplusListing current = SurplusListing.fromDocument(snapshot);

    _statusService.validateTransition(current.status, nextStatus);

    final DateTime now = DateTime.now();

    await document.update(<String, dynamic>{
      'status': nextStatus.name,
      'updatedAt': Timestamp.fromDate(now),
    });

    return current.copyWith(
      status: nextStatus,
      updatedAtOverride: now.toIso8601String(),
    );
  }

  Future<SurplusListing> markExpired({
    required String organizationId,
    required String surplusId,
  }) async {
    final SurplusListing current = await getListing(
      organizationId: organizationId,
      surplusId: surplusId,
    );

    if (!current.isPastAvailabilityWindow) {
      throw StateError('This surplus is still inside its availability window.');
    }

    return updateStatus(
      organizationId: organizationId,
      surplusId: surplusId,
      nextStatus: SurplusStatus.expired,
    );
  }

  Future<SurplusListing> getListing({
    required String organizationId,
    required String surplusId,
  }) async {
    await _requireSignedIn();

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _collection(
      organizationId,
    ).doc(surplusId.trim()).get();

    if (!snapshot.exists) {
      throw StateError('This surplus listing could not be found.');
    }

    return SurplusListing.fromDocument(snapshot);
  }

  Future<void> cancelListing({
    required String organizationId,
    required String surplusId,
  }) async {
    await updateStatus(
      organizationId: organizationId,
      surplusId: surplusId,
      nextStatus: SurplusStatus.cancelled,
    );
  }
}
