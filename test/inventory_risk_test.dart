import 'package:flutter_test/flutter_test.dart';

import 'package:foodsense/features/inventory/models/inventory_item.dart';
import 'package:foodsense/features/inventory/services/inventory_risk_service.dart';
import 'package:foodsense/features/inventory/services/inventory_risk.dart';

void main() {
  const InventoryRiskService service = InventoryRiskService();

  InventoryItem item({
    required String id,
    required double quantity,
    DateTime? expiryDate,
    int? reorderLevel,
  }) {
    return InventoryItem(
      id: id,
      organizationId: 'org-test',
      name: 'Rice',
      category: 'Grains',
      quantity: quantity,
      unit: 'kg',
      expiryDate: expiryDate,
      storageType: 'dry storage',
      reorderLevel: reorderLevel,
    );
  }

  test('marks expired inventory as expired', () {
    final InventoryItem inventory = item(
      id: '1',
      quantity: 10,
      expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      reorderLevel: 2,
    );

    final InventoryRiskAssessment result = service.assess(inventory);

    expect(result.status, InventoryRiskStatus.expired);
  });

  test('marks zero quantity as stock out', () {
    final InventoryItem inventory = item(
      id: '2',
      quantity: 0,
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      reorderLevel: 2,
    );

    final InventoryRiskAssessment result = service.assess(inventory);

    expect(result.status, InventoryRiskStatus.stockOut);
  });

  test('marks near expiry as critical expiry', () {
    final InventoryItem inventory = item(
      id: '3',
      quantity: 10,
      expiryDate: DateTime.now().add(const Duration(days: 1)),
      reorderLevel: 2,
    );

    final InventoryRiskAssessment result = service.assess(inventory);

    expect(result.status, InventoryRiskStatus.criticalExpiry);
  });

  test('marks low stock using reorder level', () {
    final InventoryItem inventory = item(
      id: '4',
      quantity: 2,
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      reorderLevel: 5,
    );

    final InventoryRiskAssessment result = service.assess(inventory);

    expect(result.status, InventoryRiskStatus.lowStock);
  });

  test('marks missing expiry separately', () {
    final InventoryItem inventory = item(
      id: '5',
      quantity: 20,
      reorderLevel: 5,
    );

    final InventoryRiskAssessment result = service.assess(inventory);

    expect(result.status, InventoryRiskStatus.noExpiryData);
  });
}
