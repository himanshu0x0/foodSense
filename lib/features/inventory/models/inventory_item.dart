/// Represents one inventory item belonging to a FoodSense organization.
///
/// Phase 1 keeps inventory focused on operational data needed for:
/// - stock tracking
/// - expiry monitoring
/// - future demand forecasting
///
/// Inventory is organization-scoped. The [organizationId] must identify the
/// organization that owns this item.
///
/// Avoid putting inventory items inside a user document. Each item is stored
/// as its own Firestore document under:
///
/// organizations/{organizationId}/inventory/{itemId}
class InventoryItem {
  final String id;
  final String organizationId;
  final String name;
  final String category;
  final double quantity;
  final String unit;
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final String storageType;
  final String? supplierName;
  final double? unitCost;
  final int? reorderLevel;

  const InventoryItem({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    this.purchaseDate,
    this.expiryDate,
    required this.storageType,
    this.supplierName,
    this.unitCost,
    this.reorderLevel,
  });

  /// Creates an [InventoryItem] from a Firestore document/map.
  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as String? ?? '',
      organizationId: map['organizationId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
      quantity: _readDouble(map['quantity']),
      unit: map['unit'] as String? ?? 'kg',
      purchaseDate: _readDateTime(map['purchaseDate']),
      expiryDate: _readDateTime(map['expiryDate']),
      storageType: map['storageType'] as String? ?? 'ambient',
      supplierName: _readNullableString(map['supplierName']),
      unitCost: _readNullableDouble(map['unitCost']),
      reorderLevel: _readNullableInt(map['reorderLevel']),
    );
  }

  /// Converts this model into a Firestore-safe map.
  ///
  /// Nullable values are omitted where no value is available. This keeps
  /// Firestore documents clean and avoids storing unnecessary null fields.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'organizationId': organizationId,
      'name': name,
      'category': category,
      'quantity': quantity,
      'unit': unit,
      if (purchaseDate != null) 'purchaseDate': purchaseDate,
      if (expiryDate != null) 'expiryDate': expiryDate,
      'storageType': storageType,
      if (supplierName != null && supplierName!.trim().isNotEmpty)
        'supplierName': supplierName!.trim(),
      if (unitCost != null) 'unitCost': unitCost,
      if (reorderLevel != null) 'reorderLevel': reorderLevel,
    };
  }

  /// Creates a copy with selected fields changed.
  InventoryItem copyWith({
    String? id,
    String? organizationId,
    String? name,
    String? category,
    double? quantity,
    String? unit,
    DateTime? purchaseDate,
    DateTime? expiryDate,
    String? storageType,
    String? supplierName,
    double? unitCost,
    int? reorderLevel,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      expiryDate: expiryDate ?? this.expiryDate,
      storageType: storageType ?? this.storageType,
      supplierName: supplierName ?? this.supplierName,
      unitCost: unitCost ?? this.unitCost,
      reorderLevel: reorderLevel ?? this.reorderLevel,
    );
  }

  /// Whether this item has an expiry date.
  bool get hasExpiryDate => expiryDate != null;

  /// Whether the item is already expired.
  bool get isExpired {
    final DateTime? expiry = expiryDate;
    if (expiry == null) {
      return false;
    }

    final DateTime today = DateTime.now();
    final DateTime todayOnly = DateTime(today.year, today.month, today.day);
    final DateTime expiryOnly = DateTime(expiry.year, expiry.month, expiry.day);

    return expiryOnly.isBefore(todayOnly);
  }

  /// Number of whole days remaining before expiry.
  ///
  /// Returns null when the item has no expiry date.
  int? get daysUntilExpiry {
    final DateTime? expiry = expiryDate;
    if (expiry == null) {
      return null;
    }

    final DateTime today = DateTime.now();
    final DateTime todayOnly = DateTime(today.year, today.month, today.day);
    final DateTime expiryOnly = DateTime(expiry.year, expiry.month, expiry.day);

    return expiryOnly.difference(todayOnly).inDays;
  }

  /// Whether the current stock is at or below the configured reorder level.
  bool get needsReorder {
    final int? level = reorderLevel;
    if (level == null) {
      return false;
    }

    return quantity <= level;
  }

  static double _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _readNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }

  static int? _readNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString());
  }

  static String? _readNullableString(dynamic value) {
    final String valueString = value?.toString().trim() ?? '';

    if (valueString.isEmpty) {
      return null;
    }

    return valueString;
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    // Firestore Timestamp exposes toDate(). Keeping this model loosely typed
    // allows it to remain easy to test without importing Firestore here.
    try {
      final dynamic date = value.toDate();
      if (date is DateTime) {
        return date;
      }
    } catch (_) {
      // Fall through to string parsing.
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  @override
  String toString() {
    return 'InventoryItem('
        'id: $id, '
        'organizationId: $organizationId, '
        'name: $name, '
        'category: $category, '
        'quantity: $quantity, '
        'unit: $unit, '
        'purchaseDate: $purchaseDate, '
        'expiryDate: $expiryDate, '
        'storageType: $storageType, '
        'supplierName: $supplierName, '
        'unitCost: $unitCost, '
        'reorderLevel: $reorderLevel'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is InventoryItem &&
        other.id == id &&
        other.organizationId == organizationId &&
        other.name == name &&
        other.category == category &&
        other.quantity == quantity &&
        other.unit == unit &&
        other.purchaseDate == purchaseDate &&
        other.expiryDate == expiryDate &&
        other.storageType == storageType &&
        other.supplierName == supplierName &&
        other.unitCost == unitCost &&
        other.reorderLevel == reorderLevel;
  }

  @override
  int get hashCode => Object.hash(
        id,
        organizationId,
        name,
        category,
        quantity,
        unit,
        purchaseDate,
        expiryDate,
        storageType,
        supplierName,
        unitCost,
        reorderLevel,
      );
}
