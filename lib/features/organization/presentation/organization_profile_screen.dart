import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/organization_repository.dart';
import '../models/organization_model.dart';

/// Displays the current organization's Phase 1 profile.
///
/// The screen loads the organization owned by the authenticated user,
/// presents its details, and allows the user to return to the onboarding
/// form to edit them.
class OrganizationProfileScreen extends StatefulWidget {
  const OrganizationProfileScreen({super.key});

  @override
  State<OrganizationProfileScreen> createState() =>
      _OrganizationProfileScreenState();
}

class _OrganizationProfileScreenState
    extends State<OrganizationProfileScreen> {
  final OrganizationRepository _organizationRepository =
      OrganizationRepository();

  OrganizationModel? _organization;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrganization();
  }

  Future<void> _loadOrganization() async {
    try {
      final OrganizationModel? organization =
          await _organizationRepository.getMyOrganization();

      if (!mounted) return;

      setState(() {
        _organization = organization;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Organization profile error: $error');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        'Unable to load organization details. Please try again.',
      );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
    });

    await _loadOrganization();
  }

  void _editOrganization() {
    context.push('/organization/setup');
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value.isEmpty ? 'Not provided' : value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organization Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _organization == null
              ? RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 80),
                      Icon(
                        Icons.business_outlined,
                        size: 72,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No organization found',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Set up your organization before recording '
                        'food-operation data.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _editOrganization,
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Set Up Organization'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor:
                                  theme.colorScheme.primary,
                              child: Icon(
                                Icons.business_rounded,
                                size: 32,
                                color:
                                    theme.colorScheme.onPrimary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _organization!.name,
                                    style: theme
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme
                                              .onPrimaryContainer,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _organization!.type,
                                    style: theme
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: theme.colorScheme
                                              .onPrimaryContainer,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Organization details',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        icon: Icons.business_outlined,
                        title: 'Organization name',
                        value: _organization!.name,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoCard(
                        icon: Icons.category_outlined,
                        title: 'Organization type',
                        value: _organization!.type,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoCard(
                        icon: Icons.location_on_outlined,
                        title: 'Address',
                        value: _organization!.address,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoCard(
                        icon: Icons.location_city_outlined,
                        title: 'City',
                        value: _organization!.city,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoCard(
                        icon: Icons.map_outlined,
                        title: 'State',
                        value: _organization!.state,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoCard(
                        icon: Icons.public_outlined,
                        title: 'Country',
                        value: _organization!.country,
                      ),
                      const SizedBox(height: 10),
                      _buildInfoCard(
                        icon: Icons.groups_outlined,
                        title: 'People served per day',
                        value: _organization!.peopleServed.toString(),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _editOrganization,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit Organization'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Back'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
