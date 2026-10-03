import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/daily_food_record.dart';

/// Repository responsible for Phase 1 daily food-record persistence.
///
/// Firestore structure:
/// organizations/{organizationId}/food_records/{recordId}
///
/// Media structure:
/// - Image binary/file: Cloudinary
/// - imageUrl + imagePublicId: Firestore food record document
///
/// The repository keeps Firestore-specific logic outside presentation screens.
/// Firestore security rules remain the final authority for authorization.
class FoodRecordRepository {
  FoodRecordRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  User get _currentUser {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in to manage food records.');
    }

    return user;
  }

  DocumentReference<Map<String, dynamic>> _organizationRef(
    String organizationId,
  ) {
    final String id = organizationId.trim();

    if (id.isEmpty) {
      throw ArgumentError('Organization ID cannot be empty.');
    }

    return _firestore.collection('organizations').doc(id);
  }

  CollectionReference<Map<String, dynamic>> _recordsRef(String organizationId) {
    return _organizationRef(organizationId).collection('food_records');
  }

  /// Returns whether the signed-in user can access the organization.
  ///
  /// Ownership is stored on the organization document. Additional users are
  /// represented in organizations/{organizationId}/members/{userId}.
  Future<bool> isOrganizationMember(String organizationId) async {
    final User user = _currentUser;
    final DocumentReference<Map<String, dynamic>> organization =
        _organizationRef(organizationId);

    final DocumentSnapshot<Map<String, dynamic>> organizationSnapshot =
        await organization.get();

    if (!organizationSnapshot.exists) {
      return false;
    }

    final Map<String, dynamic> organizationData =
        organizationSnapshot.data() ?? <String, dynamic>{};

    final String ownerId = organizationData['ownerId'] as String? ?? '';

    if (ownerId == user.uid) {
      return true;
    }

    final DocumentSnapshot<Map<String, dynamic>> memberSnapshot =
        await organization.collection('members').doc(user.uid).get();

    return memberSnapshot.exists;
  }

  Future<void> _requireOrganizationAccess(String organizationId) async {
    final bool allowed = await isOrganizationMember(organizationId);

    if (!allowed) {
      throw StateError('You do not have access to this organization.');
    }
  }

  /// Returns the membership document for the current user.
  ///
  /// Owners do not need a membership document, so owners receive a synthetic
  /// membership map with role = owner.
  Future<Map<String, dynamic>?> getMyMembership(String organizationId) async {
    final User user = _currentUser;
    final DocumentReference<Map<String, dynamic>> organization =
        _organizationRef(organizationId);

    final DocumentSnapshot<Map<String, dynamic>> organizationSnapshot =
        await organization.get();

    if (!organizationSnapshot.exists) {
      return null;
    }

    final Map<String, dynamic> organizationData =
        organizationSnapshot.data() ?? <String, dynamic>{};

    final String ownerId = organizationData['ownerId'] as String? ?? '';

    if (ownerId == user.uid) {
      return <String, dynamic>{'userId': user.uid, 'role': 'owner'};
    }

    final DocumentSnapshot<Map<String, dynamic>> memberSnapshot =
        await organization.collection('members').doc(user.uid).get();

    if (!memberSnapshot.exists) {
      return null;
    }

    return <String, dynamic>{'userId': user.uid, ...?memberSnapshot.data()};
  }

  /// Creates a new daily food record.
  ///
  /// The repository generates the document ID unless [record.id] is already
  /// provided. Server timestamps are used for audit metadata.
  Future<DailyFoodRecord> createRecord(DailyFoodRecord record) async {
    final User user = _currentUser;

    if (record.organizationId.trim().isEmpty) {
      throw ArgumentError('Organization ID cannot be empty.');
    }

    await _requireOrganizationAccess(record.organizationId);

    _validateRecord(record);

    final CollectionReference<Map<String, dynamic>> collection = _recordsRef(
      record.organizationId,
    );

    final DocumentReference<Map<String, dynamic>> document =
        record.id.trim().isEmpty
        ? collection.doc()
        : collection.doc(record.id.trim());

    final Map<String, dynamic> data = record.toMap(includeMetadata: false);

    data['createdBy'] = user.uid;
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedBy'] = user.uid;
    data['updatedAt'] = FieldValue.serverTimestamp();

    await document.set(data);

    final DocumentSnapshot<Map<String, dynamic>> saved = await document.get();

    return DailyFoodRecord.fromDocument(saved);
  }

  /// Attaches a Cloudinary image to an existing food record.
  ///
  /// Only the record creator or an organization owner/manager can attach or
  /// replace media. This method stores Cloudinary metadata only; the actual
  /// image file remains in Cloudinary.
  Future<DailyFoodRecord> attachImage({
    required String organizationId,
    required String recordId,
    required String imageUrl,
    required String imagePublicId,
  }) async {
    final User user = _currentUser;
    final String organization = organizationId.trim();
    final String id = recordId.trim();
    final String url = imageUrl.trim();
    final String publicId = imagePublicId.trim();

    if (organization.isEmpty) {
      throw ArgumentError('Organization ID cannot be empty.');
    }

    if (id.isEmpty) {
      throw ArgumentError('Record ID cannot be empty.');
    }

    if (url.isEmpty) {
      throw ArgumentError('Image URL cannot be empty.');
    }

    if (publicId.isEmpty) {
      throw ArgumentError('Image public ID cannot be empty.');
    }

    await _requireOrganizationAccess(organization);

    final DocumentReference<Map<String, dynamic>> document = _recordsRef(
      organization,
    ).doc(id);

    final DocumentSnapshot<Map<String, dynamic>> existing = await document
        .get();

    if (!existing.exists) {
      throw StateError('The food record no longer exists.');
    }

    final Map<String, dynamic> existingData =
        existing.data() ?? <String, dynamic>{};

    final String existingOrganizationId =
        existingData['organizationId'] as String? ?? '';

    if (existingOrganizationId != organization) {
      throw StateError('The food record does not belong to this organization.');
    }

    await _requireRecordWriteAccess(
      organizationId: organization,
      existingData: existingData,
      userId: user.uid,
    );

    await document.update(<String, dynamic>{
      'imageUrl': url,
      'imagePublicId': publicId,
      'updatedBy': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final DocumentSnapshot<Map<String, dynamic>> updated = await document.get();

    return DailyFoodRecord.fromDocument(updated);
  }

  /// Removes the Cloudinary media references from a food record.
  ///
  /// This does not delete the Cloudinary asset itself. The caller should
  /// delete the Cloudinary asset first (using its public ID) and then call
  /// this method to remove the Firestore references.
  Future<DailyFoodRecord> clearImage({
    required String organizationId,
    required String recordId,
  }) async {
    final User user = _currentUser;
    final String organization = organizationId.trim();
    final String id = recordId.trim();

    if (organization.isEmpty) {
      throw ArgumentError('Organization ID cannot be empty.');
    }

    if (id.isEmpty) {
      throw ArgumentError('Record ID cannot be empty.');
    }

    await _requireOrganizationAccess(organization);

    final DocumentReference<Map<String, dynamic>> document = _recordsRef(
      organization,
    ).doc(id);

    final DocumentSnapshot<Map<String, dynamic>> existing = await document
        .get();

    if (!existing.exists) {
      throw StateError('The food record no longer exists.');
    }

    final Map<String, dynamic> existingData =
        existing.data() ?? <String, dynamic>{};

    await _requireRecordWriteAccess(
      organizationId: organization,
      existingData: existingData,
      userId: user.uid,
    );

    await document.update(<String, dynamic>{
      'imageUrl': FieldValue.delete(),
      'imagePublicId': FieldValue.delete(),
      'updatedBy': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final DocumentSnapshot<Map<String, dynamic>> updated = await document.get();

    return DailyFoodRecord.fromDocument(updated);
  }

  /// Gets one food record by document ID.
  Future<DailyFoodRecord?> getRecord({
    required String organizationId,
    required String recordId,
  }) async {
    await _requireOrganizationAccess(organizationId);

    final String id = recordId.trim();

    if (id.isEmpty) {
      throw ArgumentError('Record ID cannot be empty.');
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _recordsRef(
      organizationId,
    ).doc(id).get();

    if (!snapshot.exists) {
      return null;
    }

    final DailyFoodRecord record = DailyFoodRecord.fromDocument(snapshot);

    _ensureOrganizationMatch(record, organizationId);

    return record;
  }

  /// Watches all food records for an organization in newest-first order.
  Stream<List<DailyFoodRecord>> watchRecords(String organizationId) async* {
    await _requireOrganizationAccess(organizationId);

    yield* _recordsRef(organizationId)
        .orderBy('recordDate', descending: true)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return snapshot.docs
              .map(DailyFoodRecord.fromDocument)
              .where(
                (DailyFoodRecord record) =>
                    record.organizationId == organizationId,
              )
              .toList();
        });
  }

  /// Watches records for a particular calendar date.
  ///
  /// The range is [date, date + 1 day), which is safer than comparing exact
  /// timestamps and works with Firestore Timestamp values.
  Stream<List<DailyFoodRecord>> watchRecordsForDate({
    required String organizationId,
    required DateTime date,
  }) {
    final DateTime start = _dateOnly(date);
    final DateTime end = start.add(const Duration(days: 1));

    return _recordsRef(organizationId)
        .where('recordDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('recordDate', isLessThan: Timestamp.fromDate(end))
        .orderBy('recordDate', descending: true)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return snapshot.docs
              .map(DailyFoodRecord.fromDocument)
              .where(
                (DailyFoodRecord record) =>
                    record.organizationId == organizationId,
              )
              .toList();
        });
  }

  /// Gets one page of records.
  ///
  /// Pass the last returned document as [startAfter] to fetch the next page.
  Future<FoodRecordPage> getRecordsPage({
    required String organizationId,
    int limit = 25,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    await _requireOrganizationAccess(organizationId);

    if (limit < 1 || limit > 100) {
      throw ArgumentError('Limit must be between 1 and 100.');
    }

    Query<Map<String, dynamic>> query = _recordsRef(organizationId)
        .orderBy('recordDate', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();

    final List<DailyFoodRecord> records = snapshot.docs
        .map(DailyFoodRecord.fromDocument)
        .where(
          (DailyFoodRecord record) => record.organizationId == organizationId,
        )
        .toList();

    return FoodRecordPage(
      records: records,
      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  /// Updates an existing food record.
  ///
  /// The creator can update their own record. Organization managers/owners can
  /// also update records, subject to Firestore security rules.
  Future<DailyFoodRecord> updateRecord(DailyFoodRecord record) async {
    final User user = _currentUser;

    if (record.id.trim().isEmpty) {
      throw ArgumentError('Record ID cannot be empty.');
    }

    await _requireOrganizationAccess(record.organizationId);
    _validateRecord(record);

    final DocumentReference<Map<String, dynamic>> document = _recordsRef(
      record.organizationId,
    ).doc(record.id.trim());

    final DocumentSnapshot<Map<String, dynamic>> existing = await document
        .get();

    if (!existing.exists) {
      throw StateError('The food record no longer exists.');
    }

    final Map<String, dynamic> existingData =
        existing.data() ?? <String, dynamic>{};

    final String existingOrganizationId =
        existingData['organizationId'] as String? ?? '';

    if (existingOrganizationId != record.organizationId) {
      throw StateError('The record does not belong to this organization.');
    }

    await _requireRecordWriteAccess(
      organizationId: record.organizationId,
      existingData: existingData,
      userId: user.uid,
    );

    final Map<String, dynamic> data = record.toMap(includeMetadata: false);

    data.remove('createdBy');
    data.remove('createdAt');

    data['updatedBy'] = user.uid;
    data['updatedAt'] = FieldValue.serverTimestamp();

    await document.update(data);

    final DocumentSnapshot<Map<String, dynamic>> updated = await document.get();

    return DailyFoodRecord.fromDocument(updated);
  }

  /// Deletes an existing food record.
  ///
  /// The creator can delete their own record. Organization managers/owners can
  /// also delete records, subject to Firestore security rules.
  Future<void> deleteRecord({
    required String organizationId,
    required String recordId,
  }) async {
    final User user = _currentUser;

    await _requireOrganizationAccess(organizationId);

    final String id = recordId.trim();

    if (id.isEmpty) {
      throw ArgumentError('Record ID cannot be empty.');
    }

    final DocumentReference<Map<String, dynamic>> document = _recordsRef(
      organizationId,
    ).doc(id);

    final DocumentSnapshot<Map<String, dynamic>> existing = await document
        .get();

    if (!existing.exists) {
      return;
    }

    final Map<String, dynamic> data = existing.data() ?? <String, dynamic>{};

    final String existingOrganizationId =
        data['organizationId'] as String? ?? '';

    if (existingOrganizationId != organizationId) {
      throw StateError('The record does not belong to this organization.');
    }

    await _requireRecordWriteAccess(
      organizationId: organizationId,
      existingData: data,
      userId: user.uid,
    );

    await document.delete();
  }

  /// Verifies that the current user may modify an existing record.
  ///
  /// Record creators may modify their own records. Owners, admins and
  /// managers may modify organization records.
  Future<void> _requireRecordWriteAccess({
    required String organizationId,
    required Map<String, dynamic> existingData,
    required String userId,
  }) async {
    final String createdBy = existingData['createdBy'] as String? ?? '';

    if (createdBy == userId) {
      return;
    }

    final bool ownerOrManager = await _isOwnerOrManager(organizationId, userId);

    if (!ownerOrManager) {
      throw StateError(
        'Only the record creator or an organization manager can modify this record.',
      );
    }
  }

  /// Returns whether the signed-in user owns or manages the organization.
  Future<bool> _isOwnerOrManager(String organizationId, String userId) async {
    final DocumentSnapshot<Map<String, dynamic>> organizationSnapshot =
        await _organizationRef(organizationId).get();

    if (!organizationSnapshot.exists) {
      return false;
    }

    final Map<String, dynamic> organizationData =
        organizationSnapshot.data() ?? <String, dynamic>{};

    final String ownerId = organizationData['ownerId'] as String? ?? '';

    if (ownerId == userId) {
      return true;
    }

    final DocumentSnapshot<Map<String, dynamic>> memberSnapshot =
        await _organizationRef(organizationId)
            .collection('members')
            .doc(userId)
            .get();

    if (!memberSnapshot.exists) {
      return false;
    }

    final String role = (memberSnapshot.data()?['role'] as String? ?? '')
        .toLowerCase();

    return role == 'manager' || role == 'admin';
  }

  void _ensureOrganizationMatch(DailyFoodRecord record, String organizationId) {
    if (record.organizationId != organizationId) {
      throw StateError('The food record belongs to a different organization.');
    }
  }

  void _validateRecord(DailyFoodRecord record) {
    if (record.mealType.trim().isEmpty) {
      throw ArgumentError('Meal type is required.');
    }

    if (record.menu.trim().isEmpty) {
      throw ArgumentError('Menu is required.');
    }

    if (record.expectedPeople < 0) {
      throw ArgumentError('Expected people cannot be negative.');
    }

    if (record.actualPeople < 0) {
      throw ArgumentError('Actual people cannot be negative.');
    }

    if (record.actualPeople > record.expectedPeople) {
      throw ArgumentError('Actual people cannot exceed expected people.');
    }

    if (record.mealsPrepared < 0) {
      throw ArgumentError('Meals prepared cannot be negative.');
    }

    if (record.mealsConsumed < 0) {
      throw ArgumentError('Meals consumed cannot be negative.');
    }

    if (record.mealsConsumed > record.mealsPrepared) {
      throw ArgumentError('Meals consumed cannot exceed meals prepared.');
    }

    if (record.wasteKg < 0) {
      throw ArgumentError('Food waste cannot be negative.');
    }

    final int expectedRemaining = record.mealsPrepared - record.mealsConsumed;

    if (record.mealsRemaining != expectedRemaining) {
      throw ArgumentError(
        'Meals remaining must equal meals prepared minus meals consumed.',
      );
    }
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

/// Result object for paginated daily food records.
class FoodRecordPage {
  const FoodRecordPage({
    required this.records,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<DailyFoodRecord> records;

  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;

  final bool hasMore;
}
