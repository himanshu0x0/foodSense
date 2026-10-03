import 'package:flutter_test/flutter_test.dart';

import 'package:foodsense/features/inventory/models/inventory_item.dart';
import 'package:foodsense/features/inventory/services/recommendation.dart';

void main() {
  const InventoryRecommendationService service =
      InventoryRecommendationService();

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

  test('creates high-priority recommendation for expired stock', () {
    final result = service.generate(<InventoryItem>[
      item(
        id: 'expired',
        quantity: 10,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
        reorderLevel: 2,
      ),
    ]);

    expect(result.recommendations, hasLength(1));
    expect(result.recommendations.first.priority, RecommendationPriority.high);
    expect(result.recommendations.first.category, 'Food safety');
  });

  test('creates stock recommendation when item is out of stock', () {
    final result = service.generate(<InventoryItem>[
      item(
        id: 'stock-out',
        quantity: 0,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        reorderLevel: 2,
      ),
    ]);

    expect(result.recommendations, hasLength(1));
    expect(result.recommendations.first.category, 'Stock');
    expect(result.recommendations.first.priority, RecommendationPriority.high);
  });

  test('creates medium recommendation for low stock', () {
    final result = service.generate(<InventoryItem>[
      item(
        id: 'low',
        quantity: 2,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        reorderLevel: 5,
      ),
    ]);

    expect(result.recommendations, hasLength(1));
    expect(
      result.recommendations.first.priority,
      RecommendationPriority.medium,
    );
  });

  test('creates data-quality recommendation when expiry is missing', () {
    final result = service.generate(<InventoryItem>[
      item(id: 'missing-expiry', quantity: 20, reorderLevel: 2),
    ]);

    expect(result.recommendations, hasLength(1));
    expect(result.recommendations.first.category, 'Data quality');
    expect(result.recommendations.first.priority, RecommendationPriority.low);
  });

  test('healthy inventory produces no recommendation', () {
    final result = service.generate(<InventoryItem>[
      item(
        id: 'healthy',
        quantity: 20,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        reorderLevel: 2,
      ),
    ]);

    expect(result.recommendations, isEmpty);
    expect(result.inventoryCount, 1);
  });
}
