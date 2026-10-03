import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/organization_model.dart';

/// Repository for organization-scoped FoodSense data.
///
/// Firestore structure:
///
/// organizations/{organizationId}
/// organizations/{organizationId}/members/{userId}
///
/// The current user's organization is resolved from:
///
/// users/{uid}.organizationId
///
/// This avoids collection-wide owner queries and gives us a deterministic,
/// scalable relationship between a user and their organization.
class OrganizationRepository {
  OrganizationRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _organizationsCollection =>
      _firestore.collection('organizations');

  CollectionReference<Map<String, dynamic>> _membersCollection(
    String organizationId,
  ) {
    return _organizationsCollection.doc(organizationId).collection('members');
  }

  /// Creates a new organization for the currently signed-in user.
  Future<OrganizationModel> createOrganization({
    required String name,
    required String type,
    required String address,
    required String city,
    required String state,
    String country = 'India',
    required int peopleServed,
  }) async {
    final User? currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be signed in to create an organization.');
    }

    final String normalizedName = name.trim();
    final String normalizedType = type.trim();
    final String normalizedAddress = address.trim();
    final String normalizedCity = city.trim();
    final String normalizedState = state.trim();
    final String normalizedCountry = country.trim();

    if (normalizedName.isEmpty) {
      throw ArgumentError('Organization name cannot be empty.');
    }

    if (normalizedType.isEmpty) {
      throw ArgumentError('Organization type cannot be empty.');
    }

    if (normalizedAddress.isEmpty) {
      throw ArgumentError('Address cannot be empty.');
    }

    if (normalizedCity.isEmpty) {
      throw ArgumentError('City cannot be empty.');
    }

    if (normalizedState.isEmpty) {
      throw ArgumentError('State cannot be empty.');
    }

    if (peopleServed < 0) {
      throw ArgumentError('People served cannot be negative.');
    }

    // Keep the generated document ID as the canonical organization ID.
    final DocumentReference<Map<String, dynamic>> document =
        _organizationsCollection.doc();

    final OrganizationModel organization = OrganizationModel(
      id: document.id,
      name: normalizedName,
      type: normalizedType,
      address: normalizedAddress,
      city: normalizedCity,
      state: normalizedState,
      country: normalizedCountry.isEmpty ? 'India' : normalizedCountry,
      peopleServed: peopleServed,
      ownerId: currentUser.uid,
    );

    await document.set({
      ...organization.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return organization;
  }

  /// Gets an organization by its document ID.
  Future<OrganizationModel?> getOrganization(String organizationId) async {
    final String id = organizationId.trim();

    if (id.isEmpty) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _organizationsCollection.doc(id).get();

    if (!snapshot.exists) {
      return null;
    }

    final Map<String, dynamic>? data = snapshot.data();

    if (data == null) {
      return null;
    }

    return OrganizationModel.fromMap(data);
  }

  /// Gets the organization belonging to the current user.
  ///
  /// We resolve the relationship through the user's own profile instead of
  /// querying every organization by ownerId. This is cleaner, more scalable,
  /// and easier to secure with Firestore rules.
  Future<OrganizationModel?> getMyOrganization() async {
    final User? currentUser = _auth.currentUser;

    if (currentUser == null) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> userSnapshot = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();

    if (!userSnapshot.exists) {
      return null;
    }

    final Map<String, dynamic> userData = userSnapshot.data() ?? {};

    final dynamic organizationIdValue = userData['organizationId'];

    if (organizationIdValue is! String || organizationIdValue.trim().isEmpty) {
      return null;
    }

    return getOrganization(organizationIdValue.trim());
  }

  /// Updates an existing organization.
  Future<void> updateOrganization(OrganizationModel organization) async {
    final User? currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be signed in to update an organization.');
    }

    if (organization.id.trim().isEmpty) {
      throw ArgumentError('Organization ID cannot be empty.');
    }

    if (organization.ownerId != currentUser.uid) {
      throw StateError('You can only update an organization that you own.');
    }

    if (organization.name.trim().isEmpty) {
      throw ArgumentError('Organization name cannot be empty.');
    }

    if (organization.type.trim().isEmpty) {
      throw ArgumentError('Organization type cannot be empty.');
    }

    if (organization.peopleServed < 0) {
      throw ArgumentError('People served cannot be negative.');
    }

    await _organizationsCollection.doc(organization.id).set({
      ...organization.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deletes an organization owned by the current user.
  ///
  /// Destructive deletion of organization subcollections should eventually
  /// be performed by trusted backend code. Phase 1 only deletes the
  /// organization metadata document.
  Future<void> deleteOrganization(String organizationId) async {
    final User? currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be signed in to delete an organization.');
    }

    final OrganizationModel? organization = await getOrganization(
      organizationId,
    );

    if (organization == null) {
      return;
    }

    if (organization.ownerId != currentUser.uid) {
      throw StateError('You can only delete an organization that you own.');
    }

    await _organizationsCollection.doc(organization.id).delete();
  }

  /// Checks whether the current user owns the supplied organization.
  Future<bool> isOwner(String organizationId) async {
    final User? currentUser = _auth.currentUser;

    if (currentUser == null || organizationId.trim().isEmpty) {
      return false;
    }

    final OrganizationModel? organization = await getOrganization(
      organizationId,
    );

    return organization?.ownerId == currentUser.uid;
  }

  /// Returns the current user's member record, if one exists.
  ///
  /// The owner does not need a member document; ownership is represented on
  /// the organization itself. This method becomes useful when team members
  /// are introduced in a later Phase 1/Phase 2 step.
  Future<Map<String, dynamic>?> getMyMembership(String organizationId) async {
    final User? currentUser = _auth.currentUser;

    if (currentUser == null || organizationId.trim().isEmpty) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _membersCollection(organizationId).doc(currentUser.uid).get();

    if (!snapshot.exists) {
      return null;
    }

    return snapshot.data();
  }
}
