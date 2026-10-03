import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Entry point for the FoodSense delivery-partner redistribution network.
///
/// The widget deliberately keeps the dashboard integration small: the
/// organization ID already comes from the dashboard's authenticated user
/// context, while the actual delivery network lives in the delivery_tracking
/// feature.
class DeliveryNetworkEntryCard extends StatelessWidget {
  const DeliveryNetworkEntryCard({
    required this.organizationId,
    super.key,
  });

  final String organizationId;

  void _open(BuildContext context) {
    final String organization = organizationId.trim();

    if (organization.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push(
      '/redistribution-network/${Uri.encodeComponent(organization)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                child: Icon(Icons.local_shipping_outlined),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Delivery Network',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      organizationId.trim().isEmpty
                          ? 'Set up your organization to start'
                          : 'Manage surplus deliveries, routes, ETA and live tracking',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
