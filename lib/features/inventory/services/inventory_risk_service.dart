import '../models/inventory_item.dart';
import 'inventory_risk.dart';

/// Calculates inventory risk from the existing Phase 1 inventory data.
///
/// Expiry rules:
/// - Expired: expiry date is before today.
/// - Critical expiry: expires today or tomorrow.
/// - Expiring soon: expires within the next 7 days.
///
/// Stock rules:
/// - Stock out: quantity <= 0.
/// - Low stock: quantity is at/below reorder level.
///
/// Expiry risk takes precedence because food safety should be checked
/// before stock-reorder messaging. Stock-out is the next priority.
class InventoryRiskService {
  const InventoryRiskService();

  static const int criticalExpiryWindowDays = 1;
  static const int expiryWarningWindowDays = 7;

  InventoryRiskAssessment assess(InventoryItem item) {
    final int? days = item.daysUntilExpiry;

    if (days != null && days < 0) {
      return InventoryRiskAssessment(
        item: item,
        status: InventoryRiskStatus.expired,
        title: 'Expired',
        reason: 'Expiry date passed ${days.abs()} day(s) ago.',
      );
    }

    if (item.quantity <= 0) {
      return InventoryRiskAssessment(
        item: item,
        status: InventoryRiskStatus.stockOut,
        title: 'Out of stock',
        reason: 'Current quantity is zero or below.',
      );
    }

    if (days != null && days <= criticalExpiryWindowDays) {
      return InventoryRiskAssessment(
        item: item,
        status: InventoryRiskStatus.criticalExpiry,
        title: days == 0 ? 'Expires today' : 'Expires tomorrow',
        reason: days == 0
            ? 'Use, redistribute, or process this stock today.'
            : 'Only one day remains before expiry.',
      );
    }

    if (days != null && days <= expiryWarningWindowDays) {
      return InventoryRiskAssessment(
        item: item,
        status: InventoryRiskStatus.expiringSoon,
        title: 'Expiring soon',
        reason: '$days day(s) remain before expiry.',
      );
    }

    if (item.needsReorder) {
      return InventoryRiskAssessment(
        item: item,
        status: InventoryRiskStatus.lowStock,
        title: 'Low stock',
        reason:
            'Quantity ${_formatQuantity(item.quantity)} ${item.unit} '
            'is at or below the reorder level.',
      );
    }

    if (days == null) {
      return InventoryRiskAssessment(
        item: item,
        status: InventoryRiskStatus.noExpiryData,
        title: 'No expiry date',
        reason: 'Add an expiry date to enable food-expiry monitoring.',
      );
    }

    return InventoryRiskAssessment(
      item: item,
      status: InventoryRiskStatus.healthy,
      title: 'Healthy',
      reason: 'No immediate expiry or stock risk was detected.',
    );
  }

  List<InventoryRiskAssessment> assessAll(Iterable<InventoryItem> items) {
    final List<InventoryRiskAssessment> results = items
        .map(assess)
        .toList(growable: false);

    return results;
  }

  InventoryRiskSummary summarize(
    Iterable<InventoryRiskAssessment> assessments,
  ) {
    int expired = 0;
    int stockOut = 0;
    int criticalExpiry = 0;
    int expiringSoon = 0;
    int lowStock = 0;
    int healthy = 0;
    int noExpiry = 0;
    int total = 0;

    for (final InventoryRiskAssessment assessment in assessments) {
      total++;

      switch (assessment.status) {
        case InventoryRiskStatus.expired:
          expired++;
          break;
        case InventoryRiskStatus.stockOut:
          stockOut++;
          break;
        case InventoryRiskStatus.criticalExpiry:
          criticalExpiry++;
          break;
        case InventoryRiskStatus.expiringSoon:
          expiringSoon++;
          break;
        case InventoryRiskStatus.lowStock:
          lowStock++;
          break;
        case InventoryRiskStatus.healthy:
          healthy++;
          break;
        case InventoryRiskStatus.noExpiryData:
          noExpiry++;
          break;
      }
    }

    return InventoryRiskSummary(
      totalItems: total,
      expiredItems: expired,
      stockOutItems: stockOut,
      criticalExpiryItems: criticalExpiry,
      expiringSoonItems: expiringSoon,
      lowStockItems: lowStock,
      healthyItems: healthy,
      noExpiryItems: noExpiry,
    );
  }

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }
}
