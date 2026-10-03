import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/inventory_item.dart';

/// Repository for organization-scoped inventory data.
///
/// Firestore structure:
///
/// organizations/{organizationId}/inventory/{itemId}
///
/// Inventory items are deliberately kept separate from user profiles and
/// other operational datasets. Every operation validates that the current
/// user belongs to / owns the organization before accessing its inventory.
class InventoryRepository {
  InventoryRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _inventoryCollection(
    String organizationId,
  ) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('inventory');
  }

  CollectionReference<Map<String, dynamic>> _membersCollection(
    String organizationId,
  ) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('members');
  }

  Future<void> _requireOrganizationAccess(
    String organizationId, {
    bool requireManager = false,
  }) async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be signed in to access inventory.');
    }

    final String orgId = organizationId.trim();

    if (orgId.isEmpty) {
      throw ArgumentError('Organization ID cannot be empty.');
    }

    final DocumentSnapshot<Map<String, dynamic>> organizationSnapshot =
        await _firestore.collection('organizations').doc(orgId).get();

    if (!organizationSnapshot.exists) {
      throw StateError('Organization does not exist.');
    }

    final Map<String, dynamic> organizationData =
        organizationSnapshot.data() ?? {};

    final String ownerId = organizationData['ownerId'] as String? ?? '';

    if (ownerId == user.uid) {
      return;
    }

    final DocumentSnapshot<Map<String, dynamic>> memberSnapshot =
        await _membersCollection(orgId).doc(user.uid).get();

    if (!memberSnapshot.exists) {
      throw StateError('You do not have access to this organization.');
    }

    if (!requireManager) {
      return;
    }

    final Map<String, dynamic> memberData = memberSnapshot.data() ?? {};
    final String role = memberData['role'] as String? ?? '';

    if (role != 'manager') {
      throw StateError(
        'Manager access is required for this inventory operation.',
      );
    }
  }

  /// Creates a new inventory item in the organization.
  Future<InventoryItem> createItem({
    required String organizationId,
    required String name,
    required String category,
    required double quantity,
    required String unit,
    DateTime? purchaseDate,
    DateTime? expiryDate,
    required String storageType,
    String? supplierName,
    double? unitCost,
    int? reorderLevel,
  }) async {
    final String orgId = organizationId.trim();

    await _requireOrganizationAccess(orgId, requireManager: true);

    _validateItemInput(
      name: name,
      category: category,
      quantity: quantity,
      unit: unit,
      storageType: storageType,
      unitCost: unitCost,
      reorderLevel: reorderLevel,
    );

    if (expiryDate != null &&
        purchaseDate != null &&
        expiryDate.isBefore(purchaseDate)) {
      throw ArgumentError(
        'Expiry date cannot be earlier than the purchase date.',
      );
    }

    final DocumentReference<Map<String, dynamic>> document =
        _inventoryCollection(orgId).doc();

    final InventoryItem item = InventoryItem(
      id: document.id,
      organizationId: orgId,
      name: name.trim(),
      category: category.trim(),
      quantity: quantity,
      unit: unit.trim().toLowerCase(),
      purchaseDate: purchaseDate,
      expiryDate: expiryDate,
      storageType: storageType.trim().toLowerCase(),
      supplierName: supplierName?.trim(),
      unitCost: unitCost,
      reorderLevel: reorderLevel,
    );

    final Map<String, dynamic> data = item.toMap()
      ..addAll(<String, dynamic>{
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser!.uid,
        'updatedBy': _auth.currentUser!.uid,
      });

    await document.set(data);

    return item;
  }

  /// Attaches Cloudinary metadata to an existing inventory item.
  ///
  /// The actual image remains in Cloudinary. Firestore stores only its URL
  /// and public ID.
  Future<InventoryItem> attachImage({
    required String organizationId,
    required String itemId,
    required String imageUrl,
    required String imagePublicId,
  }) async {
    final String orgId = organizationId.trim();
    final String id = itemId.trim();
    final String url = imageUrl.trim();
    final String publicId = imagePublicId.trim();

    await _requireOrganizationAccess(orgId, requireManager: true);

    if (id.isEmpty) {
      throw ArgumentError('Inventory item ID cannot be empty.');
    }

    if (url.isEmpty) {
      throw ArgumentError('Image URL cannot be empty.');
    }

    if (publicId.isEmpty) {
      throw ArgumentError('Image public ID cannot be empty.');
    }

    final DocumentReference<Map<String, dynamic>> document =
        _inventoryCollection(orgId).doc(id);

    final DocumentSnapshot<Map<String, dynamic>> existing = await document
        .get();

    if (!existing.exists) {
      throw StateError('The inventory item no longer exists.');
    }

    await document.update({
      'imageUrl': url,
      'imagePublicId': publicId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _auth.currentUser!.uid,
    });

    final DocumentSnapshot<Map<String, dynamic>> updated = await document.get();

    return InventoryItem.fromMap(updated.data() ?? <String, dynamic>{});
  }

  /// Removes Cloudinary image references from an inventory item.
  Future<InventoryItem> clearImage({
    required String organizationId,
    required String itemId,
  }) async {
    final String orgId = organizationId.trim();
    final String id = itemId.trim();

    await _requireOrganizationAccess(orgId, requireManager: true);

    if (id.isEmpty) {
      throw ArgumentError('Inventory item ID cannot be empty.');
    }

    final DocumentReference<Map<String, dynamic>> document =
        _inventoryCollection(orgId).doc(id);

    final DocumentSnapshot<Map<String, dynamic>> existing = await document
        .get();

    if (!existing.exists) {
      throw StateError('The inventory item no longer exists.');
    }

    await document.update({
      'imageUrl': FieldValue.delete(),
      'imagePublicId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _auth.currentUser!.uid,
    });

    final DocumentSnapshot<Map<String, dynamic>> updated = await document.get();

    return InventoryItem.fromMap(updated.data() ?? <String, dynamic>{});
  }

  /// Gets one inventory item by document ID.
  Future<InventoryItem?> getItem({
    required String organizationId,
    required String itemId,
  }) async {
    final String orgId = organizationId.trim();
    final String id = itemId.trim();

    await _requireOrganizationAccess(orgId);

    if (id.isEmpty) {
      throw ArgumentError('Inventory item ID cannot be empty.');
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _inventoryCollection(orgId).doc(id).get();

    if (!snapshot.exists) {
      return null;
    }

    final Map<String, dynamic>? data = snapshot.data();

    if (data == null) {
      return null;
    }

    return InventoryItem.fromMap(data);
  }

  /// Streams all inventory items for an organization.
  ///
  /// Ordering by `name` keeps the list stable for the Phase 1 UI. A Firestore
  /// index is normally not required for a single-field orderBy.
  Stream<List<InventoryItem>> watchItems({required String organizationId}) {
    final String orgId = organizationId.trim();

    if (orgId.isEmpty) {
      return Stream<List<InventoryItem>>.error(
        ArgumentError('Organization ID cannot be empty.'),
      );
    }

    return _inventoryCollection(orgId)
        .orderBy('name')
        .snapshots()
        .asyncMap((snapshot) async {
          await _requireOrganizationAccess(orgId);

          return snapshot.docs
              .map((document) => InventoryItem.fromMap(document.data()))
              .toList(growable: false);
        });
  }

  /// Fetches a single page of inventory items.
  ///
  /// [limit] is capped to avoid unintentionally requesting a very large
  /// collection from a mobile client.
  Future<List<InventoryItem>> getItems({
    required String organizationId,
    int limit = 50,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final String orgId = organizationId.trim();

    await _requireOrganizationAccess(orgId);

    final int safeLimit = limit.clamp(1, 100);

    Query<Map<String, dynamic>> query = _inventoryCollection(orgId)
        .orderBy('name')
        .limit(safeLimit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();

    return snapshot.docs
        .map((document) => InventoryItem.fromMap(document.data()))
        .toList(growable: false);
  }

  /// Updates an existing inventory item.
  Future<void> updateItem(InventoryItem item) async {
    final String orgId = item.organizationId.trim();

    await _requireOrganizationAccess(orgId, requireManager: true);

    if (item.id.trim().isEmpty) {
      throw ArgumentError('Inventory item ID cannot be empty.');
    }

    _validateItemInput(
      name: item.name,
      category: item.category,
      quantity: item.quantity,
      unit: item.unit,
      storageType: item.storageType,
      unitCost: item.unitCost,
      reorderLevel: item.reorderLevel,
    );

    if (item.expiryDate != null &&
        item.purchaseDate != null &&
        item.expiryDate!.isBefore(item.purchaseDate!)) {
      throw ArgumentError(
        'Expiry date cannot be earlier than the purchase date.',
      );
    }

    final Map<String, dynamic> data = item.toMap()
      ..addAll(<String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _auth.currentUser!.uid,
      });

    // Preserve immutable creation metadata by using merge.
    await _inventoryCollection(orgId)
        .doc(item.id)
        .set(data, SetOptions(merge: true));
  }

  /// Deletes an inventory item.
  Future<void> deleteItem({
    required String organizationId,
    required String itemId,
  }) async {
    final String orgId = organizationId.trim();
    final String id = itemId.trim();

    await _requireOrganizationAccess(orgId, requireManager: true);

    if (id.isEmpty) {
      throw ArgumentError('Inventory item ID cannot be empty.');
    }

    await _inventoryCollection(orgId).doc(id).delete();
  }

  /// Changes only the current quantity.
  ///
  /// Keeping quantity updates separate makes it possible later to introduce
  /// inventory movement/consumption records without rewriting the item model.
  Future<void> updateQuantity({
    required String organizationId,
    required String itemId,
    required double quantity,
  }) async {
    final String orgId = organizationId.trim();
    final String id = itemId.trim();

    await _requireOrganizationAccess(orgId, requireManager: true);

    if (id.isEmpty) {
      throw ArgumentError('Inventory item ID cannot be empty.');
    }

    if (quantity < 0) {
      throw ArgumentError('Quantity cannot be negative.');
    }

    await _inventoryCollection(orgId).doc(id).update({
      'quantity': quantity,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _auth.currentUser!.uid,
    });
  }

  void _validateItemInput({
    required String name,
    required String category,
    required double quantity,
    required String unit,
    required String storageType,
    double? unitCost,
    int? reorderLevel,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError('Inventory item name cannot be empty.');
    }

    if (category.trim().isEmpty) {
      throw ArgumentError('Inventory category cannot be empty.');
    }

    if (quantity < 0) {
      throw ArgumentError('Quantity cannot be negative.');
    }

    if (unit.trim().isEmpty) {
      throw ArgumentError('Unit cannot be empty.');
    }

    if (storageType.trim().isEmpty) {
      throw ArgumentError('Storage type cannot be empty.');
    }

    if (unitCost != null && unitCost < 0) {
      throw ArgumentError('Unit cost cannot be negative.');
    }

    if (reorderLevel != null && reorderLevel < 0) {
      throw ArgumentError('Reorder level cannot be negative.');
    }
  }
}
