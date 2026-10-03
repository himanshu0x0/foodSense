import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:foodsense/features/inventory/services/inventory_risk.dart';
import 'package:foodsense/features/inventory/services/inventory_risk_service.dart';

import '../data/inventory_repository.dart';
import '../models/inventory_item.dart';

/// Phase 3 foundation: Inventory Risk Center.
///
/// This screen is intentionally read-only. It analyzes the inventory data
/// already stored in Firestore and presents operational actions without
/// changing the existing inventory workflow.
class InventoryRiskScreen extends StatelessWidget {
  const InventoryRiskScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  Widget build(BuildContext context) {
    if (organizationId.trim().isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Organization information is missing.')),
      );
    }

    if (FirebaseAuth.instance.currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view inventory risk.')),
      );
    }

    return _InventoryRiskView(organizationId: organizationId);
  }
}

class _InventoryRiskView extends StatefulWidget {
  const _InventoryRiskView({required this.organizationId});

  final String organizationId;

  @override
  State<_InventoryRiskView> createState() => _InventoryRiskViewState();
}

class _InventoryRiskViewState extends State<_InventoryRiskView> {
  static const InventoryRiskService _riskService = InventoryRiskService();

  final InventoryRepository _repository = InventoryRepository();

  String _filter = 'actionable';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Risk'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Filter risk',
            initialValue: _filter,
            onSelected: (value) {
              setState(() {
                _filter = value;
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'actionable',
                child: Text('Actionable'),
              ),
              PopupMenuItem<String>(value: 'high', child: Text('High risk')),
              PopupMenuItem<String>(value: 'expiry', child: Text('Expiry')),
              PopupMenuItem<String>(value: 'stock', child: Text('Stock')),
              PopupMenuItem<String>(value: 'all', child: Text('All items')),
            ],
            icon: const Icon(Icons.filter_list_rounded),
          ),
        ],
      ),
      body: StreamBuilder<List<InventoryItem>>(
        stream: _repository.watchItems(organizationId: widget.organizationId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildError(context, snapshot.error);
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<InventoryRiskAssessment> assessments = _riskService
              .assessAll(snapshot.data ?? const <InventoryItem>[]);

          final InventoryRiskSummary summary = _riskService.summarize(
            assessments,
          );

          final List<InventoryRiskAssessment> filtered =
              assessments.where(_matchesFilter).toList(growable: true)
                ..sort(_compareRisk);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildHeader(context, summary),
                const SizedBox(height: 16),
                _buildSummaryGrid(context, summary),
                const SizedBox(height: 20),
                Text(
                  _filterTitle(),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  _buildEmptyState(context)
                else
                  ...filtered.map(
                    (assessment) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RiskCard(assessment: assessment),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _matchesFilter(InventoryRiskAssessment assessment) {
    switch (_filter) {
      case 'high':
        return assessment.isHighRisk;
      case 'expiry':
        return assessment.status == InventoryRiskStatus.expired ||
            assessment.status == InventoryRiskStatus.criticalExpiry ||
            assessment.status == InventoryRiskStatus.expiringSoon;
      case 'stock':
        return assessment.status == InventoryRiskStatus.stockOut ||
            assessment.status == InventoryRiskStatus.lowStock;
      case 'all':
        return true;
      case 'actionable':
      default:
        return assessment.isActionable;
    }
  }

  int _compareRisk(InventoryRiskAssessment a, InventoryRiskAssessment b) {
    final int statusDifference = _priority(a.status)
        .compareTo(_priority(b.status));

    if (statusDifference != 0) {
      return statusDifference;
    }

    return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
  }

  int _priority(InventoryRiskStatus status) {
    switch (status) {
      case InventoryRiskStatus.expired:
        return 0;
      case InventoryRiskStatus.stockOut:
        return 1;
      case InventoryRiskStatus.criticalExpiry:
        return 2;
      case InventoryRiskStatus.expiringSoon:
        return 3;
      case InventoryRiskStatus.lowStock:
        return 4;
      case InventoryRiskStatus.noExpiryData:
        return 5;
      case InventoryRiskStatus.healthy:
        return 6;
    }
  }

  String _filterTitle() {
    switch (_filter) {
      case 'high':
        return 'High-risk items';
      case 'expiry':
        return 'Expiry-related items';
      case 'stock':
        return 'Stock-related items';
      case 'all':
        return 'All inventory';
      case 'actionable':
      default:
        return 'Items needing attention';
    }
  }

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildHeader(BuildContext context, InventoryRiskSummary summary) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final String headline = summary.actionableItems == 0
        ? 'Inventory looks stable'
        : '${summary.actionableItems} item(s) need attention';

    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colors.primary,
              child: Icon(Icons.shield_outlined, color: colors.onPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inventory Risk Center',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headline,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Food expiry is checked first, followed by stock '
                    'availability and reorder thresholds.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(BuildContext context, InventoryRiskSummary summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = (constraints.maxWidth - 10) / 2;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Total',
                value: '${summary.totalItems}',
                icon: Icons.inventory_2_outlined,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Expired',
                value: '${summary.expiredItems}',
                icon: Icons.error_outline_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Expiring ≤ 7 days',
                value:
                    '${summary.criticalExpiryItems + summary.expiringSoonItems}',
                icon: Icons.schedule_outlined,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _SummaryCard(
                label: 'Low / out',
                value: '${summary.lowStockItems + summary.stockOutItems}',
                icon: Icons.trending_down_rounded,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(
              'No items match this filter.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another filter or add more inventory data.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Unable to analyze inventory risk.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_friendlyError(error), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object? error) {
    final String message = error?.toString() ?? '';

    if (message.contains('permission-denied')) {
      return 'You do not have permission to view this inventory.';
    }

    if (message.contains('signed in')) {
      return 'Please sign in again.';
    }

    return 'Check your Firebase connection and try again.';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.assessment});

  final InventoryRiskAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final _RiskVisual visual = _visualFor(assessment.status, colors);

    final InventoryItem item = assessment.item;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIconBox(visual),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _RiskChip(
                        label: assessment.title,
                        background: visual.background,
                        foreground: visual.foreground,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.quantity} ${item.unit} • ${item.category}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(assessment.reason, style: theme.textTheme.bodySmall),
                  if (item.expiryDate != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Expiry: ${_formatDate(item.expiryDate!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (item.reorderLevel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Reorder level: ${item.reorderLevel} ${item.unit}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconBox(_RiskVisual visual) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: visual.background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(visual.icon, color: visual.foreground),
    );
  }

  String _formatDate(DateTime date) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day.toString().padLeft(2, '0')} '
        '${months[date.month - 1]} ${date.year}';
  }
}

class _RiskChip extends StatelessWidget {
  const _RiskChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RiskVisual {
  const _RiskVisual({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
}

_RiskVisual _visualFor(InventoryRiskStatus status, ColorScheme colors) {
  switch (status) {
    case InventoryRiskStatus.expired:
      return _RiskVisual(
        icon: Icons.error_outline_rounded,
        background: colors.errorContainer,
        foreground: colors.onErrorContainer,
      );
    case InventoryRiskStatus.stockOut:
      return _RiskVisual(
        icon: Icons.remove_shopping_cart_outlined,
        background: colors.errorContainer,
        foreground: colors.onErrorContainer,
      );
    case InventoryRiskStatus.criticalExpiry:
      return _RiskVisual(
        icon: Icons.alarm_outlined,
        background: colors.tertiaryContainer,
        foreground: colors.onTertiaryContainer,
      );
    case InventoryRiskStatus.expiringSoon:
      return _RiskVisual(
        icon: Icons.schedule_outlined,
        background: colors.secondaryContainer,
        foreground: colors.onSecondaryContainer,
      );
    case InventoryRiskStatus.lowStock:
      return _RiskVisual(
        icon: Icons.trending_down_rounded,
        background: colors.secondaryContainer,
        foreground: colors.onSecondaryContainer,
      );
    case InventoryRiskStatus.noExpiryData:
      return _RiskVisual(
        icon: Icons.event_busy_outlined,
        background: colors.surfaceContainerHighest,
        foreground: colors.onSurfaceVariant,
      );
    case InventoryRiskStatus.healthy:
      return _RiskVisual(
        icon: Icons.check_circle_outline_rounded,
        background: colors.primaryContainer,
        foreground: colors.onPrimaryContainer,
      );
  }
}
