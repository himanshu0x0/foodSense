import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// FoodSense dashboard.
///
/// This screen provides:
/// - Current user and organization overview
/// - Daily food-operation overview
/// - Phase 1 operational navigation
/// - Inventory risk and operational recommendations
/// - Phase 2 AI navigation
/// - Redistribution and delivery-network navigation
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  String _userName = 'User';
  String _organizationName = 'Organization not set';
  String _organizationType = '';
  String _organizationId = '';

  int _expectedPeople = 0;
  int _actualPeople = 0;
  int _mealsPrepared = 0;
  int _mealsConsumed = 0;
  double _wasteKg = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        context.go('/login');
      }
      return;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnapshot =
          await _firestore.collection('users').doc(user.uid).get();

      final Map<String, dynamic> userData = userSnapshot.data() ?? {};

      final dynamic storedNameValue = userData['name'];
      final String storedName = storedNameValue is String
          ? storedNameValue
          : '';

      _userName = storedName.trim().isNotEmpty
          ? storedName.trim()
          : (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : 'User');

      final dynamic organizationIdValue = userData['organizationId'];
      _organizationId = organizationIdValue is String
          ? organizationIdValue.trim()
          : '';

      if (_organizationId.isNotEmpty) {
        final DocumentSnapshot<Map<String, dynamic>> organizationSnapshot =
            await _firestore
                .collection('organizations')
                .doc(_organizationId)
                .get();

        final Map<String, dynamic> organizationData =
            organizationSnapshot.data() ?? {};

        final dynamic organizationNameValue = organizationData['name'];
        final String storedOrganizationName = organizationNameValue is String
            ? organizationNameValue
            : '';

        _organizationName = storedOrganizationName.trim().isNotEmpty
            ? storedOrganizationName.trim()
            : 'Organization not set';

        final dynamic organizationTypeValue = organizationData['type'];
        _organizationType = organizationTypeValue is String
            ? organizationTypeValue.trim()
            : '';

        await _loadTodayFoodRecord();
      }
    } on FirebaseException catch (error) {
      debugPrint('Dashboard Firebase error: ${error.code} ${error.message}');
    } catch (error) {
      debugPrint('Dashboard error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTodayFoodRecord() async {
    if (_organizationId.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime startOfDay = DateTime(now.year, now.month, now.day);
    final DateTime endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('organizations')
          .doc(_organizationId)
          .collection('food_records')
          .where(
            'recordDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('recordDate', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('recordDate', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return;
      }

      final Map<String, dynamic> data = snapshot.docs.first.data();

      _expectedPeople = _readInt(data['expectedPeople']);
      _actualPeople = _readInt(data['actualPeople']);
      _mealsPrepared = _readInt(data['mealsPrepared']);
      _mealsConsumed = _readInt(data['mealsConsumed']);
      _wasteKg = _readDouble(data['wasteKg']);
    } on FirebaseException catch (error) {
      // The Phase 1 food-record index may not exist until the food-record
      // query is first deployed. The rest of the dashboard can still load.
      debugPrint(
        'Today food record Firebase error: ${error.code} ${error.message}',
      );
    }
  }

  int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();

      if (!mounted) return;

      context.go('/login');
    } on FirebaseException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error.message ?? 'Unable to sign out. Please try again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
    });

    await _loadDashboard();
  }

  void _openOrganization() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/organization/profile');
  }

  void _openInventory() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/inventory/${Uri.encodeComponent(_organizationId)}');
  }

  void _openInventoryRisk() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/inventory-risk/${Uri.encodeComponent(_organizationId)}');
  }

  void _openRecommendations() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/recommendations/${Uri.encodeComponent(_organizationId)}');
  }

  void _openDailyFoodRecord() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/food-records/daily/${Uri.encodeComponent(_organizationId)}');
  }

  void _openRecordHistory() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push(
      '/food-records/history/${Uri.encodeComponent(_organizationId)}',
    );
  }

  void _openAiHub() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/ai/${Uri.encodeComponent(_organizationId)}');
  }

  void _openForecast() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/forecast/${Uri.encodeComponent(_organizationId)}');
  }

  void _openSurplus() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/surplus/${Uri.encodeComponent(_organizationId)}');
  }

  void _openWasteAnalysis() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/waste/${Uri.encodeComponent(_organizationId)}');
  }

  void _openSurplusScenarios() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push('/surplus-scenarios/${Uri.encodeComponent(_organizationId)}');
  }

  void _openDeliveryNetwork() {
    if (_organizationId.isEmpty) {
      context.push('/organization/setup');
      return;
    }

    context.push(
      '/redistribution-network/${Uri.encodeComponent(_organizationId)}',
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    String? suffix,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (suffix != null)
              Text(
                suffix,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(radius: 24, child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FoodSense'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _signOut();
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  Text(
                    'Hello, $_userName',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_organizationName, style: theme.textTheme.bodyLarge),
                  if (_organizationType.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      _organizationType.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    "Today's overview",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildMetricCard(
                    icon: Icons.people_outline_rounded,
                    label: 'Expected people',
                    value: '$_expectedPeople',
                  ),
                  const SizedBox(height: 10),
                  _buildMetricCard(
                    icon: Icons.groups_2_outlined,
                    label: 'Actual people',
                    value: '$_actualPeople',
                  ),
                  const SizedBox(height: 10),
                  _buildMetricCard(
                    icon: Icons.restaurant_outlined,
                    label: 'Meals prepared',
                    value: '$_mealsPrepared',
                  ),
                  const SizedBox(height: 10),
                  _buildMetricCard(
                    icon: Icons.restaurant_rounded,
                    label: 'Meals consumed',
                    value: '$_mealsConsumed',
                  ),
                  const SizedBox(height: 10),
                  _buildMetricCard(
                    icon: Icons.delete_outline_rounded,
                    label: 'Food waste',
                    value: _wasteKg.toStringAsFixed(1),
                    suffix: 'kg',
                  ),
                  const SizedBox(height: 28),

                  // Phase 1.
                  Text(
                    'Phase 1',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildQuickAction(
                    icon: Icons.business_outlined,
                    title: 'Organization',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization'
                        : 'View or edit your organization',
                    onTap: _openOrganization,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.inventory_2_outlined,
                    title: 'Inventory',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'Track ingredients and expiry information',
                    onTap: _openInventory,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.shield_outlined,
                    title: 'Inventory Risk',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'See expiry and stock items needing attention',
                    onTap: _openInventoryRisk,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Recommendations',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'Get clear actions from current inventory risks',
                    onTap: _openRecommendations,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.edit_note_rounded,
                    title: 'Daily food record',
                    subtitle: 'Record preparation, consumption and waste',
                    onTap: _openDailyFoodRecord,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.history_rounded,
                    title: 'Record history',
                    subtitle: 'Review previously recorded food data',
                    onTap: _openRecordHistory,
                  ),
                  const SizedBox(height: 28),

                  // Phase 2 AI.
                  Text(
                    'Phase 2 AI',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Use FoodSense intelligence to plan production, '
                    'identify surplus, and understand waste patterns.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickAction(
                    icon: Icons.auto_awesome_rounded,
                    title: 'FoodSense AI',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'Forecast demand, compare production, and analyze waste',
                    onTap: _openAiHub,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.auto_graph_rounded,
                    title: 'Demand forecast',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'Predict meal demand from historical data',
                    onTap: _openForecast,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.inventory_2_outlined,
                    title: 'Surplus prediction',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'Estimate surplus before production',
                    onTap: _openSurplus,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.compare_arrows_rounded,
                    title: 'Scenario comparison',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'Compare multiple production quantities',
                    onTap: _openSurplusScenarios,
                  ),
                  const SizedBox(height: 10),
                  _buildQuickAction(
                    icon: Icons.analytics_outlined,
                    title: 'Waste analysis',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'Analyze historical waste and trends',
                    onTap: _openWasteAnalysis,
                  ),
                  const SizedBox(height: 28),

                  // Redistribution / logistics.
                  Text(
                    'Redistribution & Logistics',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Connect surplus food to NGOs with delivery-partner '
                    'assignment, traffic-aware routing, ETA and live trip monitoring.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickAction(
                    icon: Icons.local_shipping_outlined,
                    title: 'Delivery Network',
                    subtitle: _organizationId.isEmpty
                        ? 'Set up your organization first'
                        : 'Manage surplus deliveries, routes, ETA and live tracking',
                    onTap: _openDeliveryNetwork,
                  ),
                ],
              ),
            ),
    );
  }
}
