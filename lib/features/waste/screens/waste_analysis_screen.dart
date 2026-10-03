import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foodsense/core/network/foodsense_ai_api_client.dart';
import 'package:foodsense/features/forecast/providers/forecast_provider.dart';

/// Phase 2 waste-analysis dashboard.
///
/// The screen reads historical food-record data through the authenticated
/// FastAPI backend and presents both aggregate metrics and daily trend data.
/// It intentionally does not calculate waste metrics locally; the backend is
/// the source of truth.
class WasteAnalysisScreen extends ConsumerStatefulWidget {
  const WasteAnalysisScreen({required this.organizationId, super.key});

  final String organizationId;

  @override
  ConsumerState<WasteAnalysisScreen> createState() =>
      _WasteAnalysisScreenState();
}

class _WasteAnalysisScreenState extends ConsumerState<WasteAnalysisScreen> {
  late DateTime _startDate;
  late DateTime _endDate;
  String? _mealType;
  WasteAnalysisQuery? _query;
  WasteTrendQuery? _trendQuery;

  @override
  void initState() {
    super.initState();

    final DateTime today = _dateOnly(DateTime.now());
    _endDate = today;
    _startDate = today.subtract(const Duration(days: 29));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (widget.organizationId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Waste Analysis')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Organization information is missing. Please open Waste Analysis from a valid organization.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Waste Analysis')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Understand where food waste is happening',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'FoodSense analyzes historical preparation, consumption, '
                'remaining meals and recorded waste to identify patterns.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _buildFilterCard(theme),
              const SizedBox(height: 20),
              if (_query == null)
                _buildInitialState(theme)
              else
                _buildAnalysisState(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Analysis period',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _buildDateSelector(
                    label: 'Start date',
                    value: _startDate,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDateSelector(
                    label: 'End date',
                    value: _endDate,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _mealType,
              decoration: const InputDecoration(
                labelText: 'Meal type',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.restaurant_outlined),
              ),
              items: const <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All meals'),
                ),
                DropdownMenuItem<String?>(
                  value: 'Breakfast',
                  child: Text('Breakfast'),
                ),
                DropdownMenuItem<String?>(value: 'Lunch', child: Text('Lunch')),
                DropdownMenuItem<String?>(
                  value: 'Dinner',
                  child: Text('Dinner'),
                ),
                DropdownMenuItem<String?>(value: 'Snack', child: Text('Snack')),
                DropdownMenuItem<String?>(value: 'Other', child: Text('Other')),
              ],
              onChanged: (String? value) {
                setState(() {
                  _mealType = value;
                });
              },
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _runAnalysis,
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Analyze waste'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(_formatDate(value)),
      ),
    );
  }

  Widget _buildInitialState(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.delete_sweep_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Ready to analyze',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a date range and optionally a meal type, then analyze '
              'historical food waste.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisState(ThemeData theme) {
    final WasteAnalysisQuery query = _query!;
    final AsyncValue<WasteAnalysisResult> analysis = ref.watch(
      wasteAnalysisProvider(query),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        analysis.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Column(
                  children: <Widget>[
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('Analyzing historical waste...'),
                  ],
                ),
              ),
            ),
          ),
          error: (Object error, StackTrace stackTrace) {
            return _buildErrorCard(
              theme,
              title: 'Waste analysis failed',
              error: error,
              onRetry: () => ref.invalidate(wasteAnalysisProvider(query)),
            );
          },
          data: (WasteAnalysisResult result) {
            return _buildAnalysisResult(theme, result);
          },
        ),
        const SizedBox(height: 12),
        if (_trendQuery != null) _buildTrendSection(theme, _trendQuery!),
      ],
    );
  }

  Widget _buildAnalysisResult(ThemeData theme, WasteAnalysisResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                result.mealType == null
                    ? 'All meals'
                    : '${result.mealType} analysis',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _TrendChip(trend: result.trend),
          ],
        ),
        const SizedBox(height: 12),
        _buildMetricGrid(theme, result),
        const SizedBox(height: 12),
        _buildInsightCard(theme, result),
        const SizedBox(height: 12),
        _buildRecommendationsCard(theme, result),
      ],
    );
  }

  Widget _buildMetricGrid(ThemeData theme, WasteAnalysisResult result) {
    return Column(
      children: <Widget>[
        _MetricTile(
          label: 'Total waste',
          value: result.totalWasteKg.toStringAsFixed(2),
          unit: 'kg',
          icon: Icons.delete_outline_rounded,
        ),
        const SizedBox(height: 10),
        _MetricTile(
          label: 'Average daily waste',
          value: result.averageDailyWasteKg.toStringAsFixed(2),
          unit: 'kg/day',
          icon: Icons.date_range_outlined,
        ),
        const SizedBox(height: 10),
        _MetricTile(
          label: 'Meals prepared',
          value: '${result.totalMealsPrepared}',
          unit: 'meals',
          icon: Icons.local_dining_outlined,
        ),
        const SizedBox(height: 10),
        _MetricTile(
          label: 'Meals consumed',
          value: '${result.totalMealsConsumed}',
          unit: 'meals',
          icon: Icons.restaurant_outlined,
        ),
        const SizedBox(height: 10),
        _MetricTile(
          label: 'Meals remaining',
          value: '${result.totalMealsRemaining}',
          unit: 'meals',
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: 10),
        _MetricTile(
          label: 'Surplus rate',
          value: result.surplusRatePercent.toStringAsFixed(1),
          unit: '%',
          icon: Icons.pie_chart_outline,
        ),
        const SizedBox(height: 10),
        _MetricTile(
          label: 'Waste rate',
          value: result.wasteRatePercent.toStringAsFixed(2),
          unit: '%',
          icon: Icons.auto_graph_outlined,
        ),
      ],
    );
  }

  Widget _buildInsightCard(ThemeData theme, WasteAnalysisResult result) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Operational insight',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(result.insight),
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Records analyzed',
              value: '${result.recordsAnalyzed}',
            ),
            _DetailRow(
              label: 'Excess production',
              value: '${result.excessProductionMeals} meals',
            ),
            _DetailRow(
              label: 'Waste per remaining meal',
              value:
                  '${result.averageWastePerRemainingMealKg.toStringAsFixed(3)} kg',
            ),
            _DetailRow(
              label: 'Analysis method',
              value: _formatMethod(result.method),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationsCard(
    ThemeData theme,
    WasteAnalysisResult result,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Recommendations',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ...result.recommendations.map((String recommendation) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.check_circle_outline, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(recommendation)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendSection(ThemeData theme, WasteTrendQuery query) {
    final AsyncValue<WasteTrendResult> trendAsync = ref.watch(
      wasteTrendProvider(query),
    );

    return trendAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Loading daily waste trend...'),
              ],
            ),
          ),
        ),
      ),
      error: (Object error, StackTrace stackTrace) {
        return _buildErrorCard(
          theme,
          title: 'Trend analysis failed',
          error: error,
          onRetry: () => ref.invalidate(wasteTrendProvider(query)),
        );
      },
      data: (WasteTrendResult result) {
        return _buildTrendResult(theme, result);
      },
    );
  }

  Widget _buildTrendResult(ThemeData theme, WasteTrendResult result) {
    if (result.dailyMetrics.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'No daily waste data is available for the selected period.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final double maxWaste = result.dailyMetrics.fold<double>(
      0,
      (double current, WasteDailyMetric metric) =>
          metric.wasteKg > current ? metric.wasteKg : current,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Daily waste trend',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _TrendChip(trend: result.trend),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${result.dailyMetrics.length} daily data points',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (maxWaste <= 0)
              const SizedBox(
                height: 100,
                child: Center(child: Text('No recorded waste in this period.')),
              )
            else
              ...result.dailyMetrics.reversed.take(14).map((
                WasteDailyMetric metric,
              ) {
                final double fraction = (metric.wasteKg / maxWaste).clamp(
                  0.0,
                  1.0,
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          SizedBox(
                            width: 88,
                            child: Text(
                              _formatDate(metric.recordDate),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                minHeight: 10,
                                value: fraction,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 62,
                            child: Text(
                              '${metric.wasteKg.toStringAsFixed(1)} kg',
                              textAlign: TextAlign.end,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Prepared ${metric.mealsPrepared} • '
                        'Consumed ${metric.mealsConsumed} • '
                        'Remaining ${metric.mealsRemaining}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    ThemeData theme, {
    required String title,
    required Object error,
    required VoidCallback onRetry,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 6),
            Text(_friendlyError(error)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final DateTime initial = isStart ? _startDate : _endDate;

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      if (isStart) {
        _startDate = selected;

        if (_startDate.isAfter(_endDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = selected;

        if (_endDate.isBefore(_startDate)) {
          _startDate = _endDate;
        }
      }
    });
  }

  void _runAnalysis() {
    if (_endDate.isBefore(_startDate)) {
      _showMessage('End date cannot be before start date.');
      return;
    }

    final String organizationId = widget.organizationId.trim();

    if (organizationId.isEmpty) {
      _showMessage('Organization information is missing.');
      return;
    }

    final WasteAnalysisQuery query = WasteAnalysisQuery(
      organizationId: organizationId,
      startDate: _startDate,
      endDate: _endDate,
      mealType: _mealType,
    );

    setState(() {
      _query = query;
      _trendQuery = WasteTrendQuery(
        organizationId: organizationId,
        startDate: _startDate,
        endDate: _endDate,
        mealType: _mealType,
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object error) {
    if (error is FoodSenseApiException) {
      return error.message;
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  static DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');

    return '${local.year}-$month-$day';
  }

  static String _formatMethod(String method) {
    return method
        .replaceAll('_', ' ')
        .split(' ')
        .where((String part) => part.isNotEmpty)
        .map((String part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class WasteAnalysisQuery {
  const WasteAnalysisQuery({
    required this.organizationId,
    required this.startDate,
    required this.endDate,
    required this.mealType,
  });

  final String organizationId;
  final DateTime startDate;
  final DateTime endDate;
  final String? mealType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is WasteAnalysisQuery &&
        other.organizationId == organizationId &&
        _sameDate(other.startDate, startDate) &&
        _sameDate(other.endDate, endDate) &&
        other.mealType == mealType;
  }

  @override
  int get hashCode {
    return Object.hash(
      organizationId,
      startDate.year,
      startDate.month,
      startDate.day,
      endDate.year,
      endDate.month,
      endDate.day,
      mealType,
    );
  }

  static bool _sameDate(DateTime left, DateTime right) {
    final a = left.toLocal();
    final b = right.toLocal();

    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class WasteTrendQuery {
  const WasteTrendQuery({
    required this.organizationId,
    required this.startDate,
    required this.endDate,
    required this.mealType,
  });

  final String organizationId;
  final DateTime startDate;
  final DateTime endDate;
  final String? mealType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is WasteTrendQuery &&
        other.organizationId == organizationId &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.mealType == mealType;
  }

  @override
  int get hashCode => Object.hash(organizationId, startDate, endDate, mealType);
}

final wasteAnalysisProvider = FutureProvider.autoDispose
    .family<WasteAnalysisResult, WasteAnalysisQuery>((ref, query) async {
      final client = ref.watch(foodSenseAiApiClientProvider);

      final response = await client.waste(<String, dynamic>{
        'organization_id': query.organizationId,
        'start_date': _dateOnlyString(query.startDate),
        'end_date': _dateOnlyString(query.endDate),
        if (query.mealType != null) 'meal_type': query.mealType,
      });

      return WasteAnalysisResult.fromMap(response);
    });

final wasteTrendProvider = FutureProvider.autoDispose
    .family<WasteTrendResult, WasteTrendQuery>((ref, query) async {
      final client = ref.watch(foodSenseAiApiClientProvider);

      final response = await client.wasteTrend(<String, dynamic>{
        'organization_id': query.organizationId,
        'start_date': _dateOnlyString(query.startDate),
        'end_date': _dateOnlyString(query.endDate),
        if (query.mealType != null) 'meal_type': query.mealType,
      });

      return WasteTrendResult.fromMap(response);
    });

class WasteAnalysisResult {
  const WasteAnalysisResult({
    required this.organizationId,
    required this.startDate,
    required this.endDate,
    required this.mealType,
    required this.recordsAnalyzed,
    required this.totalMealsPrepared,
    required this.totalMealsConsumed,
    required this.totalMealsRemaining,
    required this.totalWasteKg,
    required this.averageDailyWasteKg,
    required this.wasteRatePercent,
    required this.surplusRatePercent,
    required this.excessProductionMeals,
    required this.averageWastePerRemainingMealKg,
    required this.trend,
    required this.insight,
    required this.recommendations,
    required this.method,
    required this.generatedAt,
  });

  final String organizationId;
  final DateTime startDate;
  final DateTime endDate;
  final String? mealType;
  final int recordsAnalyzed;
  final int totalMealsPrepared;
  final int totalMealsConsumed;
  final int totalMealsRemaining;
  final double totalWasteKg;
  final double averageDailyWasteKg;
  final double wasteRatePercent;
  final double surplusRatePercent;
  final int excessProductionMeals;
  final double averageWastePerRemainingMealKg;
  final String trend;
  final String insight;
  final List<String> recommendations;
  final String method;
  final DateTime generatedAt;

  factory WasteAnalysisResult.fromMap(Map<String, dynamic> map) {
    return WasteAnalysisResult(
      organizationId: _stringField(map, 'organization_id'),
      startDate: _dateField(map, 'start_date'),
      endDate: _dateField(map, 'end_date'),
      mealType: map['meal_type'] == null
          ? null
          : _stringField(map, 'meal_type'),
      recordsAnalyzed: _intField(map, 'records_analyzed'),
      totalMealsPrepared: _intField(map, 'total_meals_prepared'),
      totalMealsConsumed: _intField(map, 'total_meals_consumed'),
      totalMealsRemaining: _intField(map, 'total_meals_remaining'),
      totalWasteKg: _doubleField(map, 'total_waste_kg'),
      averageDailyWasteKg: _doubleField(map, 'average_daily_waste_kg'),
      wasteRatePercent: _doubleField(map, 'waste_rate_percent'),
      surplusRatePercent: _doubleField(map, 'surplus_rate_percent'),
      excessProductionMeals: _intField(map, 'excess_production_meals'),
      averageWastePerRemainingMealKg: _doubleField(
        map,
        'average_waste_per_remaining_meal_kg',
      ),
      trend: _stringField(map, 'trend'),
      insight: _stringField(map, 'insight'),
      recommendations: _stringListField(map, 'recommendations'),
      method: _stringField(map, 'method'),
      generatedAt: _timestampField(map, 'generated_at'),
    );
  }
}

class WasteTrendResult {
  const WasteTrendResult({
    required this.organizationId,
    required this.startDate,
    required this.endDate,
    required this.mealType,
    required this.trend,
    required this.dailyMetrics,
    required this.generatedAt,
  });

  final String organizationId;
  final DateTime startDate;
  final DateTime endDate;
  final String? mealType;
  final String trend;
  final List<WasteDailyMetric> dailyMetrics;
  final DateTime generatedAt;

  factory WasteTrendResult.fromMap(Map<String, dynamic> map) {
    final dynamic rawMetrics = map['daily_metrics'];

    final List<WasteDailyMetric> metrics = rawMetrics is List
        ? rawMetrics
              .whereType<Map<String, dynamic>>()
              .map(WasteDailyMetric.fromMap)
              .toList(growable: false)
        : const <WasteDailyMetric>[];

    return WasteTrendResult(
      organizationId: _stringField(map, 'organization_id'),
      startDate: _dateField(map, 'start_date'),
      endDate: _dateField(map, 'end_date'),
      mealType: map['meal_type'] == null
          ? null
          : _stringField(map, 'meal_type'),
      trend: _stringField(map, 'trend'),
      dailyMetrics: metrics,
      generatedAt: _timestampField(map, 'generated_at'),
    );
  }
}

class WasteDailyMetric {
  const WasteDailyMetric({
    required this.recordDate,
    required this.mealsPrepared,
    required this.mealsConsumed,
    required this.mealsRemaining,
    required this.wasteKg,
    required this.wasteRatePercent,
    required this.surplusRatePercent,
  });

  final DateTime recordDate;
  final int mealsPrepared;
  final int mealsConsumed;
  final int mealsRemaining;
  final double wasteKg;
  final double wasteRatePercent;
  final double surplusRatePercent;

  factory WasteDailyMetric.fromMap(Map<String, dynamic> map) {
    return WasteDailyMetric(
      recordDate: _dateField(map, 'record_date'),
      mealsPrepared: _intField(map, 'meals_prepared'),
      mealsConsumed: _intField(map, 'meals_consumed'),
      mealsRemaining: _intField(map, 'meals_remaining'),
      wasteKg: _doubleField(map, 'waste_kg'),
      wasteRatePercent: _doubleField(map, 'waste_rate_percent'),
      surplusRatePercent: _doubleField(map, 'surplus_rate_percent'),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(unit, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.trend});

  final String trend;

  @override
  Widget build(BuildContext context) {
    final IconData icon;

    switch (trend) {
      case 'improving':
        icon = Icons.trending_down;
        break;
      case 'worsening':
        icon = Icons.trending_up;
        break;
      case 'stable':
        icon = Icons.trending_flat;
        break;
      default:
        icon = Icons.help_outline;
    }

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(trend.replaceAll('_', ' ').toUpperCase()),
      visualDensity: VisualDensity.compact,
    );
  }
}

String _dateOnlyString(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');

  return '${local.year}-$month-$day';
}

String _stringField(Map<String, dynamic> map, String field) {
  final dynamic value = map[field];

  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  throw FormatException('Waste field "$field" must be a non-empty string.');
}

int _intField(Map<String, dynamic> map, String field) {
  final dynamic value = map[field];

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    final int? parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }

  throw FormatException('Waste field "$field" must be an integer.');
}

double _doubleField(Map<String, dynamic> map, String field) {
  final dynamic value = map[field];

  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    final double? parsed = double.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }

  throw FormatException('Waste field "$field" must be a number.');
}

DateTime _dateField(Map<String, dynamic> map, String field) {
  final dynamic value = map[field];

  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);

    if (parsed != null) {
      return parsed;
    }
  }

  throw FormatException('Waste field "$field" must be a valid date.');
}

DateTime _timestampField(Map<String, dynamic> map, String field) {
  final dynamic value = map[field];

  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);

    if (parsed != null) {
      return parsed;
    }
  }

  throw FormatException('Waste field "$field" must be a valid timestamp.');
}

List<String> _stringListField(Map<String, dynamic> map, String field) {
  final dynamic value = map[field];

  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }

  throw FormatException('Waste field "$field" must be a list of strings.');
}
