import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Phase 2 AI workspace.
///
/// This screen provides one entry point for the current AI capabilities:
/// demand forecasting, surplus prediction, scenario comparison, and
/// historical waste analysis.
class Phase2AiHubScreen extends StatelessWidget {
  const Phase2AiHubScreen({required this.organizationId, super.key});

  final String organizationId;

  bool get _hasOrganization => organizationId.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Operations')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: <Widget>[
            _buildHeader(context, theme),
            const SizedBox(height: 20),
            _buildWorkflowCard(context, theme),
            const SizedBox(height: 20),
            Text(
              'AI tools',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            _buildToolCard(
              context,
              theme,
              icon: Icons.trending_up_rounded,
              title: 'Demand forecast',
              description:
                  'Estimate how many meals are likely to be consumed '
                  'before production begins.',
              route: '/forecast',
            ),
            const SizedBox(height: 12),
            _buildToolCard(
              context,
              theme,
              icon: Icons.inventory_2_outlined,
              title: 'Surplus prediction',
              description:
                  'Estimate expected surplus from a planned production '
                  'quantity.',
              route: '/surplus',
            ),
            const SizedBox(height: 12),
            _buildToolCard(
              context,
              theme,
              icon: Icons.compare_arrows_rounded,
              title: 'Scenario comparison',
              description:
                  'Compare several production quantities against the same '
                  'demand estimate.',
              route: '/surplus-scenarios',
            ),
            const SizedBox(height: 12),
            _buildToolCard(
              context,
              theme,
              icon: Icons.analytics_outlined,
              title: 'Waste analysis',
              description:
                  'Review historical waste, surplus, trends, insights, '
                  'and recommendations.',
              route: '/waste',
            ),
            const SizedBox(height: 12),
            _buildToolCard(
              context,
              theme,
              icon: Icons.auto_awesome_rounded,
              title: 'Operational recommendations',
              description:
                  'Turn inventory risk signals into clear actions for '
                  'expiry and stock management.',
              route: '/recommendations',
            ),
            const SizedBox(height: 20),
            _buildWorkflowExplanation(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final ColorScheme colors = theme.colorScheme;

    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 25,
              backgroundColor: colors.primary,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: colors.onPrimary,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'FoodSense AI',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Use operational data to plan production, '
                    'reduce avoidable surplus, and understand waste.',
                    style: theme.textTheme.bodyMedium?.copyWith(
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

  Widget _buildWorkflowCard(BuildContext context, ThemeData theme) {
    final ColorScheme colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Recommended workflow',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _buildStep(
              theme,
              number: '1',
              title: 'Predict demand',
              text: 'Estimate expected consumption.',
              icon: Icons.trending_up_rounded,
            ),
            _buildConnector(colors),
            _buildStep(
              theme,
              number: '2',
              title: 'Plan production',
              text: 'Choose a production quantity.',
              icon: Icons.soup_kitchen_outlined,
            ),
            _buildConnector(colors),
            _buildStep(
              theme,
              number: '3',
              title: 'Check surplus',
              text: 'Compare surplus and risk before service.',
              icon: Icons.inventory_2_outlined,
            ),
            _buildConnector(colors),
            _buildStep(
              theme,
              number: '4',
              title: 'Analyze waste',
              text: 'Use historical results to improve future planning.',
              icon: Icons.analytics_outlined,
            ),
            _buildConnector(colors),
            _buildStep(
              theme,
              number: '5',
              title: 'Act on recommendations',
              text: 'Turn operational signals into clear next actions.',
              icon: Icons.task_alt_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(
    ThemeData theme, {
    required String number,
    required String title,
    required String text,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 19,
          child: Text(
            number,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(text, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnector(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 19, top: 3, bottom: 3),
      child: SizedBox(
        height: 16,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: colors.outlineVariant,
        ),
      ),
    );
  }

  Widget _buildToolCard(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
    required String route,
  }) {
    final ColorScheme colors = theme.colorScheme;

    return Card(
      child: InkWell(
        onTap: () => _openTool(context, route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colors.onSecondaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(description, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkflowExplanation(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.lightbulb_outline_rounded),
                const SizedBox(width: 8),
                Text(
                  'How these tools work together',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'The demand forecast provides the baseline estimate. '
              'Surplus prediction uses that demand estimate with your '
              'planned production. Scenario comparison lets you test '
              'multiple quantities without changing the underlying '
              'forecast. Waste analysis closes the feedback loop by '
              'showing historical operational results. Recommendations '
              'translate current inventory signals into explainable next '
              'actions.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  void _openTool(BuildContext context, String route) {
    if (!_hasOrganization) {
      context.push('/organization/setup');
      return;
    }

    context.push('$route/${Uri.encodeComponent(organizationId)}');
  }
}
