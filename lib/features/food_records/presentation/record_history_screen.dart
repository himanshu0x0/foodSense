import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/food_record_repository.dart';
import '../models/daily_food_record.dart';

/// Phase 1 screen for reviewing previously submitted daily food records.
///
/// Records are loaded through [FoodRecordRepository] rather than directly
/// from Firestore.
///
/// Features:
/// - Realtime record history
/// - Search by menu or meal type
/// - Filter by meal type
/// - Filter by date range
/// - Summary metrics
/// - Edit and delete actions
class RecordHistoryScreen extends StatefulWidget {
  const RecordHistoryScreen({
    super.key,
    required this.organizationId,
  });

  final String organizationId;

  @override
  State<RecordHistoryScreen> createState() => _RecordHistoryScreenState();
}

class _RecordHistoryScreenState extends State<RecordHistoryScreen> {
  final FoodRecordRepository _repository = FoodRecordRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedMealType = 'All';
  DateTimeRange? _selectedDateRange;
  bool _isDeleting = false;

  static const List<String> _mealTypes = <String>[
    'All',
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'Other',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters {
    return _searchQuery.isNotEmpty ||
        _selectedMealType != 'All' ||
        _selectedDateRange != null;
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _matchesFilters(DailyFoodRecord record) {
    if (_selectedMealType != 'All' &&
        record.mealType != _selectedMealType) {
      return false;
    }

    if (_searchQuery.isNotEmpty) {
      final String query = _searchQuery.toLowerCase();

      final bool matchesMenu =
          record.menu.toLowerCase().contains(query);
      final bool matchesMealType =
          record.mealType.toLowerCase().contains(query);

      if (!matchesMenu && !matchesMealType) {
        return false;
      }
    }

    final DateTimeRange? range = _selectedDateRange;

    if (range != null) {
      final DateTime recordDate = _dateOnly(record.recordDate);
      final DateTime start = _dateOnly(range.start);
      final DateTime end = _dateOnly(range.end);

      if (recordDate.isBefore(start) || recordDate.isAfter(end)) {
        return false;
      }
    }

    return true;
  }

  Future<void> _pickDateRange() async {
    final DateTime now = DateTime.now();

    final DateTimeRange? selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day),
          ),
      helpText: 'Select record date range',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDateRange = selected;
    });
  }

  void _clearFilters() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _selectedMealType = 'All';
      _selectedDateRange = null;
    });
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

  String _formatRange(DateTimeRange range) {
    final DateTime start = _dateOnly(range.start);
    final DateTime end = _dateOnly(range.end);

    if (start == end) {
      return _formatDate(start);
    }

    return '${_formatDate(start)} → ${_formatDate(end)}';
  }

  Future<void> _editRecord(DailyFoodRecord record) async {
    final String encodedOrganizationId =
        Uri.encodeComponent(widget.organizationId);
    final String encodedRecordId = Uri.encodeComponent(record.id);

    await context.push(
      '/food-records/edit/$encodedOrganizationId/$encodedRecordId',
    );
  }

  Future<void> _deleteRecord(DailyFoodRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete food record?'),
          content: Text(
            '${record.mealType} on ${_formatDate(record.recordDate)} '
            'will be permanently removed.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final User? user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        context.go('/login');
      }
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      await _repository.deleteRecord(
        organizationId: widget.organizationId,
        recordId: record.id,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Food record deleted successfully.',
        isError: false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message ?? 'Authentication error.',
        isError: true,
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _firebaseErrorMessage(error),
        isError: true,
      );
    } on ArgumentError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message?.toString() ?? 'Invalid record information.',
        isError: true,
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        error.message,
        isError: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint('Delete record error: $error');

      _showMessage(
        'Unable to delete this record. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  String _firebaseErrorMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Permission denied. You do not have access to this organization.';
      case 'unauthenticated':
        return 'Your session has expired. Please sign in again.';
      case 'unavailable':
        return 'Firebase is temporarily unavailable. Check your connection.';
      default:
        return error.message ?? 'Firebase could not complete the request.';
    }
  }

  void _showMessage(
    String message, {
    required bool isError,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colors.error : null,
        ),
      );
  }

  IconData _mealIcon(String mealType) {
    switch (mealType.toLowerCase()) {
      case 'breakfast':
        return Icons.free_breakfast_outlined;
      case 'lunch':
        return Icons.lunch_dining_outlined;
      case 'dinner':
        return Icons.dinner_dining_outlined;
      case 'snack':
        return Icons.cookie_outlined;
      default:
        return Icons.restaurant_outlined;
    }
  }

  Widget _buildHeader() {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Food record history',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Review production, consumption, remaining meals, and waste '
          'recorded by your organization.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _searchController,
          enabled: !_isDeleting,
          onChanged: (String value) {
            setState(() {
              _searchQuery = value.trim();
            });
          },
          decoration: InputDecoration(
            hintText: 'Search menu or meal type',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();

                      setState(() {
                        _searchQuery = '';
                      });
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (
            BuildContext context,
            BoxConstraints constraints,
          ) {
            final bool compact = constraints.maxWidth < 560;

            final DropdownButtonFormField<String> mealFilter =
                DropdownButtonFormField<String>(
              value: _selectedMealType,
              decoration: const InputDecoration(
                labelText: 'Meal type',
                prefixIcon: Icon(Icons.restaurant_menu_outlined),
              ),
              items: _mealTypes
                  .map(
                    (String mealType) =>
                        DropdownMenuItem<String>(
                      value: mealType,
                      child: Text(mealType),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _isDeleting
                  ? null
                  : (String? value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _selectedMealType = value;
                      });
                    },
            );

            final OutlinedButton dateFilter = OutlinedButton.icon(
              onPressed: _isDeleting ? null : _pickDateRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Flexible(
                child: Text(
                  _selectedDateRange == null
                      ? 'Date range'
                      : _formatRange(_selectedDateRange!),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  mealFilter,
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 54,
                    child: dateFilter,
                  ),
                ],
              );
            }

            return Row(
              children: <Widget>[
                Expanded(child: mealFilter),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: dateFilter,
                  ),
                ),
              ],
            );
          },
        ),
        if (_hasActiveFilters) ...<Widget>[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isDeleting ? null : _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear filters'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummary(
    List<DailyFoodRecord> records,
  ) {
    int mealsPrepared = 0;
    int mealsConsumed = 0;
    int mealsRemaining = 0;
    double wasteKg = 0;

    for (final DailyFoodRecord record in records) {
      mealsPrepared += record.mealsPrepared;
      mealsConsumed += record.mealsConsumed;
      mealsRemaining += record.mealsRemaining;
      wasteKg += record.wasteKg;
    }

    final List<Widget> cards = <Widget>[
      _SummaryCard(
        title: 'Records',
        value: records.length.toString(),
        icon: Icons.receipt_long_outlined,
      ),
      _SummaryCard(
        title: 'Prepared',
        value: mealsPrepared.toString(),
        icon: Icons.restaurant_menu_outlined,
      ),
      _SummaryCard(
        title: 'Consumed',
        value: mealsConsumed.toString(),
        icon: Icons.people_outline,
      ),
      _SummaryCard(
        title: 'Remaining',
        value: mealsRemaining.toString(),
        icon: Icons.inventory_2_outlined,
      ),
      _SummaryCard(
        title: 'Waste',
        value: '${wasteKg.toStringAsFixed(1)} kg',
        icon: Icons.delete_outline,
      ),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cards,
    );
  }

  Widget _buildRecordCard(DailyFoodRecord record) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16,
        ),
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          child: Icon(_mealIcon(record.mealType)),
        ),
        title: Text(
          record.mealType,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${_formatDate(record.recordDate)} • ${record.menu}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: PopupMenuButton<String>(
          enabled: !_isDeleting,
          tooltip: 'Record actions',
          onSelected: (String action) async {
            if (action == 'edit') {
              await _editRecord(record);
            } else if (action == 'delete') {
              await _deleteRecord(record);
            }
          },
          itemBuilder: (BuildContext context) {
            return const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
            ];
          },
          icon: const Icon(Icons.more_vert),
        ),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _MetricChip(
                  label: 'Expected',
                  value: record.expectedPeople.toString(),
                  icon: Icons.groups_outlined,
                ),
                _MetricChip(
                  label: 'Actual',
                  value: record.actualPeople.toString(),
                  icon: Icons.person_outline,
                ),
                _MetricChip(
                  label: 'Prepared',
                  value: record.mealsPrepared.toString(),
                  icon: Icons.soup_kitchen_outlined,
                ),
                _MetricChip(
                  label: 'Consumed',
                  value: record.mealsConsumed.toString(),
                  icon: Icons.restaurant_outlined,
                ),
                _MetricChip(
                  label: 'Remaining',
                  value: record.mealsRemaining.toString(),
                  icon: Icons.inventory_2_outlined,
                ),
                _MetricChip(
                  label: 'Waste',
                  value: '${record.wasteKg.toStringAsFixed(1)} kg',
                  icon: Icons.delete_sweep_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (record.specialEvent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.event_available_outlined,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Special event / unusual demand day',
                      style: TextStyle(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              const Icon(
                Icons.analytics_outlined,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Consumption rate: '
                  '${_consumptionRate(record).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _consumptionRate(DailyFoodRecord record) {
    if (record.mealsPrepared <= 0) {
      return 0;
    }

    final double value =
        (record.mealsConsumed / record.mealsPrepared) * 100;

    return value.clamp(0, 100);
  }

  Widget _buildEmptyState() {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: <Widget>[
            CircleAvatar(
              radius: 30,
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _hasActiveFilters
                  ? 'No matching records'
                  : 'No food records yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _hasActiveFilters
                  ? 'Try changing the search or filters.'
                  : 'Daily food records added by your organization '
                    'will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            if (_hasActiveFilters) ...<Widget>[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _clearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object error) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    String message = 'Unable to load food records.';

    if (error is FirebaseException) {
      message = _firebaseErrorMessage(error);
    } else if (error is StateError) {
      message = error.message;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 32,
              backgroundColor: colors.errorContainer,
              foregroundColor: colors.onErrorContainer,
              child: const Icon(
                Icons.error_outline_rounded,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load food records',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.organizationId.trim().isEmpty) {
      return _buildError(
        StateError(
          'Organization information is missing. Complete organization setup first.',
        ),
      );
    }

    return StreamBuilder<List<DailyFoodRecord>>(
      stream: _repository.watchRecords(widget.organizationId),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<DailyFoodRecord>> snapshot,
      ) {
        if (snapshot.hasError) {
          return _buildError(snapshot.error!);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final List<DailyFoodRecord> records =
            snapshot.data ?? <DailyFoodRecord>[];

        final List<DailyFoodRecord> filteredRecords =
            records.where(_matchesFilters).toList();

        return RefreshIndicator(
          onRefresh: () async {
            await Future<void>.delayed(
              const Duration(milliseconds: 300),
            );
            if (mounted) {
              setState(() {});
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: <Widget>[
              _buildHeader(),
              const SizedBox(height: 20),
              _buildSummary(filteredRecords),
              const SizedBox(height: 22),
              if (filteredRecords.isEmpty)
                _buildEmptyState()
              else
                ...filteredRecords.map(_buildRecordCard),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record History'),
      ),
      body: _buildBody(),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
