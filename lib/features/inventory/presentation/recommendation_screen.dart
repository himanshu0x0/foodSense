import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/inventory_repository.dart';
import '../models/inventory_item.dart';
import '../services/inventory_risk.dart';
import '../services/recommendation.dart';

/// Operational recommendation center.
///
/// Recommendations are derived from the organization's live inventory
/// stream. No Firestore writes occur from this screen.
class RecommendationScreen extends StatelessWidget {
  const RecommendationScreen({super.key, required this.organizationId});

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
        body: Center(child: Text('Please sign in to view recommendations.')),
      );
    }

    return _RecommendationView(organizationId: organizationId);
  }
}

class _RecommendationView extends StatefulWidget {
  const _RecommendationView({required this.organizationId});

  final String organizationId;

  @override
  State<_RecommendationView> createState() => _RecommendationViewState();
}

class _RecommendationViewState extends State<_RecommendationView> {
  final InventoryRepository _repository = InventoryRepository();

  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommendations'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Filter recommendations',
            initialValue: _filter,
            onSelected: (value) {
              setState(() {
                _filter = value;
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(value: 'all', child: Text('All')),
              PopupMenuItem<String>(
                value: 'high',
                child: Text('High priority'),
              ),
              PopupMenuItem<String>(value: 'expiry', child: Text('Expiry')),
              PopupMenuItem<String>(value: 'stock', child: Text('Stock')),
              PopupMenuItem<String>(value: 'data', child: Text('Data quality')),
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

          final RecommendationResult result =
              const InventoryRecommendationService().generate(
                snapshot.data ?? const <InventoryItem>[],
              );

          final List<InventoryRecommendation> visible = result.recommendations
              .where(_matchesFilter)
              .toList(growable: false);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _buildHeader(theme, result),
                const SizedBox(height: 16),
                if (visible.isEmpty)
                  _buildEmpty(theme, result)
                else
                  ...visible.map(
                    (recommendation) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RecommendationCard(
                        recommendation: recommendation,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                _buildMethodNote(theme),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _matchesFilter(InventoryRecommendation recommendation) {
    switch (_filter) {
      case 'high':
        return recommendation.priority == RecommendationPriority.high;
      case 'expiry':
        return recommendation.category == 'Expiry' ||
            recommendation.category == 'Food safety';
      case 'stock':
        return recommendation.category == 'Stock';
      case 'data':
        return recommendation.category == 'Data quality';
      case 'all':
      default:
        return true;
    }
  }

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildHeader(ThemeData theme, RecommendationResult result) {
    final ColorScheme colors = theme.colorScheme;
    final String headline = result.hasRecommendations
        ? '${result.recommendations.length} action(s) suggested'
        : 'No immediate actions detected';

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
              child: Icon(Icons.auto_awesome_rounded, color: colors.onPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FoodSense Recommendations',
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
                    'Based on ${result.inventoryCount} live inventory '
                    'item(s) and transparent operational rules.',
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

  Widget _buildEmpty(ThemeData theme, RecommendationResult result) {
    final bool hasInventory = result.inventoryCount > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              hasInventory
                  ? Icons.check_circle_outline_rounded
                  : Icons.inventory_2_outlined,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              hasInventory
                  ? 'Inventory is currently stable.'
                  : 'No inventory has been recorded yet.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasInventory
                  ? 'FoodSense did not detect an immediate operational '
                        'action from the current inventory data.'
                  : 'Add inventory items with quantity, reorder level '
                        'and expiry information to activate recommendations.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodNote(ThemeData theme) {
    return Text(
      'Recommendations are explainable and rule-based in this phase. '
      'They do not replace food-safety procedures or staff judgment.',
      style: theme.textTheme.bodySmall,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildError(BuildContext context, Object? error) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(
              'Unable to load recommendations.',
              style: theme.textTheme.titleMedium,
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
      return 'You do not have permission to view this organization inventory.';
    }

    if (message.contains('signed in')) {
      return 'Please sign in again.';
    }

    return 'Check your Firebase connection and try again.';
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendation});

  final InventoryRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final _RecommendationVisual visual = _visualFor(
      recommendation.priority,
      colors,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: visual.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(visual.icon, color: visual.foreground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              recommendation.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _PriorityChip(
                            label: recommendation.priorityLabel,
                            background: visual.background,
                            foreground: visual.foreground,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        recommendation.category,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.help_outline_rounded,
              label: 'Why',
              text: recommendation.reason,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.task_alt_rounded,
              label: 'Action',
              text: recommendation.action,
            ),
            if (recommendation.item != null) ...[
              const SizedBox(height: 12),
              _InventoryDetails(assessment: recommendation.item!),
            ],
          ],
        ),
      ),
    );
  }

  _RecommendationVisual _visualFor(
    RecommendationPriority priority,
    ColorScheme colors,
  ) {
    switch (priority) {
      case RecommendationPriority.high:
        return _RecommendationVisual(
          icon: Icons.priority_high_rounded,
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
        );
      case RecommendationPriority.medium:
        return _RecommendationVisual(
          icon: Icons.lightbulb_outline_rounded,
          background: colors.secondaryContainer,
          foreground: colors.onSecondaryContainer,
        );
      case RecommendationPriority.low:
        return _RecommendationVisual(
          icon: Icons.info_outline_rounded,
          background: colors.surfaceContainerHighest,
          foreground: colors.onSurfaceVariant,
        );
    }
  }
}

class _RecommendationVisual {
  const _RecommendationVisual({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({
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
      constraints: const BoxConstraints(maxWidth: 120),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.text});

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(text, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _InventoryDetails extends StatelessWidget {
  const _InventoryDetails({required this.assessment});

  final InventoryRiskAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final InventoryItem item = assessment.item;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          Text(
            'Stock: ${_formatQuantity(item.quantity)} ${item.unit}',
            style: theme.textTheme.bodySmall,
          ),
          if (item.expiryDate != null)
            Text(
              'Expiry: ${_formatDate(item.expiryDate!)}',
              style: theme.textTheme.bodySmall,
            ),
          if (item.reorderLevel != null)
            Text(
              'Reorder: ${_formatQuantity(item.reorderLevel!.toDouble())} '
              '${item.unit}',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  static String _formatDate(DateTime date) {
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
