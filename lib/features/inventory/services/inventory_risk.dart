import '../models/inventory_item.dart';

/// Operational risk states used by the Inventory Risk Center.
///
/// This classification is deterministic and uses only fields already
/// stored on [InventoryItem]. It does not change the Firestore schema.
enum InventoryRiskStatus {
  expired,
  stockOut,
  criticalExpiry,
  expiringSoon,
  lowStock,
  healthy,
  noExpiryData,
}

/// A calculated risk result for one inventory item.
class InventoryRiskAssessment {
  const InventoryRiskAssessment({
    required this.item,
    required this.status,
    required this.title,
    required this.reason,
  });

  final InventoryItem item;
  final InventoryRiskStatus status;
  final String title;
  final String reason;

  bool get isHighRisk =>
      status == InventoryRiskStatus.expired ||
      status == InventoryRiskStatus.stockOut ||
      status == InventoryRiskStatus.criticalExpiry;

  bool get isActionable =>
      isHighRisk ||
      status == InventoryRiskStatus.expiringSoon ||
      status == InventoryRiskStatus.lowStock ||
      status == InventoryRiskStatus.noExpiryData;
}

/// Summary counts for the current inventory snapshot.
class InventoryRiskSummary {
  const InventoryRiskSummary({
    required this.totalItems,
    required this.expiredItems,
    required this.stockOutItems,
    required this.criticalExpiryItems,
    required this.expiringSoonItems,
    required this.lowStockItems,
    required this.healthyItems,
    required this.noExpiryItems,
  });

  final int totalItems;
  final int expiredItems;
  final int stockOutItems;
  final int criticalExpiryItems;
  final int expiringSoonItems;
  final int lowStockItems;
  final int healthyItems;
  final int noExpiryItems;

  int get actionableItems =>
      expiredItems +
      stockOutItems +
      criticalExpiryItems +
      expiringSoonItems +
      lowStockItems +
      noExpiryItems;
}
