import '../models/inventory_item.dart';
import 'inventory_risk.dart';
import 'inventory_risk_service.dart';

/// Priority used by the transparent operational recommendation engine.
enum RecommendationPriority { high, medium, low }

/// One actionable FoodSense recommendation.
///
/// The recommendation is deliberately explainable: every item includes
/// the condition that triggered it and the operational action to take.
class InventoryRecommendation {
  const InventoryRecommendation({
    required this.id,
    required this.priority,
    required this.category,
    required this.title,
    required this.reason,
    required this.action,
    this.item,
  });

  final String id;
  final RecommendationPriority priority;
  final String category;
  final String title;
  final String reason;
  final String action;
  final InventoryRiskAssessment? item;

  String get priorityLabel {
    switch (priority) {
      case RecommendationPriority.high:
        return 'High priority';
      case RecommendationPriority.medium:
        return 'Recommended';
      case RecommendationPriority.low:
        return 'Review';
    }
  }
}

/// Result of generating recommendations for the current inventory.
class RecommendationResult {
  const RecommendationResult({
    required this.recommendations,
    required this.inventoryCount,
  });

  final List<InventoryRecommendation> recommendations;
  final int inventoryCount;

  bool get hasRecommendations => recommendations.isNotEmpty;
}

/// Transparent rule-based recommendation engine for inventory operations.
///
/// This is intentionally not an external LLM call. The goal is to create
/// a dependable decision-support layer first. Later AI/ML services can
/// use the same recommendation contract and replace individual rules.
class InventoryRecommendationService {
  const InventoryRecommendationService({
    InventoryRiskService riskService = const InventoryRiskService(),
  }) : _riskService = riskService;

  final InventoryRiskService _riskService;

  RecommendationResult generate(Iterable<InventoryItem> items) {
    final List<InventoryItem> inventory = items.toList(growable: false);

    final List<InventoryRiskAssessment> assessments = _riskService.assessAll(
      inventory,
    );

    final List<InventoryRecommendation> recommendations =
        <InventoryRecommendation>[];

    for (final InventoryRiskAssessment assessment in assessments) {
      final InventoryItem item = assessment.item;

      switch (assessment.status) {
        case InventoryRiskStatus.expired:
          recommendations.add(
            InventoryRecommendation(
              id: 'expired-${item.id}',
              priority: RecommendationPriority.high,
              category: 'Food safety',
              title: '${item.name} is expired',
              reason: assessment.reason,
              action:
                  'Remove this stock from active use and review your '
                  'approved disposal process.',
              item: assessment,
            ),
          );
          break;

        case InventoryRiskStatus.stockOut:
          recommendations.add(
            InventoryRecommendation(
              id: 'stockout-${item.id}',
              priority: RecommendationPriority.high,
              category: 'Stock',
              title: '${item.name} is out of stock',
              reason: assessment.reason,
              action:
                  'Review upcoming production needs and replenish this '
                  'item when required.',
              item: assessment,
            ),
          );
          break;

        case InventoryRiskStatus.criticalExpiry:
          recommendations.add(
            InventoryRecommendation(
              id: 'critical-expiry-${item.id}',
              priority: RecommendationPriority.high,
              category: 'Expiry',
              title: 'Prioritize ${item.name}',
              reason: assessment.reason,
              action:
                  'Use this stock in the nearest suitable production '
                  'plan or route it through the appropriate surplus '
                  'workflow before expiry.',
              item: assessment,
            ),
          );
          break;

        case InventoryRiskStatus.expiringSoon:
          recommendations.add(
            InventoryRecommendation(
              id: 'expiring-soon-${item.id}',
              priority: RecommendationPriority.medium,
              category: 'Expiry',
              title: 'Plan around ${item.name}',
              reason: assessment.reason,
              action:
                  'Consider using this stock in upcoming menus before '
                  'ordering more of the same item.',
              item: assessment,
            ),
          );
          break;

        case InventoryRiskStatus.lowStock:
          recommendations.add(
            InventoryRecommendation(
              id: 'low-stock-${item.id}',
              priority: RecommendationPriority.medium,
              category: 'Stock',
              title: 'Review ${item.name} reorder',
              reason: assessment.reason,
              action:
                  'Check the next production plan and replenish before '
                  'the stock falls below the required level.',
              item: assessment,
            ),
          );
          break;

        case InventoryRiskStatus.noExpiryData:
          recommendations.add(
            InventoryRecommendation(
              id: 'missing-expiry-${item.id}',
              priority: RecommendationPriority.low,
              category: 'Data quality',
              title: 'Add an expiry date for ${item.name}',
              reason: assessment.reason,
              action:
                  'Update this inventory item with a verified expiry '
                  'date so FoodSense can monitor food-age risk.',
              item: assessment,
            ),
          );
          break;

        case InventoryRiskStatus.healthy:
          break;
      }
    }

    recommendations.sort(_compareRecommendations);

    return RecommendationResult(
      recommendations: recommendations.take(12).toList(growable: false),
      inventoryCount: inventory.length,
    );
  }

  int _compareRecommendations(
    InventoryRecommendation a,
    InventoryRecommendation b,
  ) {
    final int priorityComparison = _priorityValue(a.priority)
        .compareTo(_priorityValue(b.priority));

    if (priorityComparison != 0) {
      return priorityComparison;
    }

    final String aItem = a.item?.item.name.toLowerCase() ?? a.title;
    final String bItem = b.item?.item.name.toLowerCase() ?? b.title;

    return aItem.compareTo(bItem);
  }

  int _priorityValue(RecommendationPriority priority) {
    switch (priority) {
      case RecommendationPriority.high:
        return 0;
      case RecommendationPriority.medium:
        return 1;
      case RecommendationPriority.low:
        return 2;
    }
  }
}
