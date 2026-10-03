import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foodsense/core/network/foodsense_ai_api_client.dart';
import 'package:foodsense/features/forecast/providers/forecast_provider.dart';

/// Phase 2: compares multiple production quantities against the same
/// FoodSense demand forecast.
///
/// The backend remains the source of truth for demand, surplus, and risk.
class SurplusScenarioScreen extends ConsumerStatefulWidget {
  const SurplusScenarioScreen({required this.organizationId, super.key});

  final String organizationId;

  @override
  ConsumerState<SurplusScenarioScreen> createState() =>
      _SurplusScenarioScreenState();
}

class _SurplusScenarioScreenState extends ConsumerState<SurplusScenarioScreen> {
  static const List<String> _mealTypes = <String>[
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'Other',
  ];

  late final TextEditingController _peopleController;
  final List<TextEditingController> _productionControllers =
      <TextEditingController>[];

  DateTime _predictionDate = DateTime.now();
  String _mealType = 'Lunch';
  bool _specialEvent = false;
  SurplusScenarioQuery? _query;

  @override
  void initState() {
    super.initState();

    _peopleController = TextEditingController(text: '1800');

    const List<int> defaults = <int>[1650, 1750, 1850, 1950, 2050];

    for (final int value in defaults) {
      _productionControllers.add(TextEditingController(text: '$value'));
    }
  }

  @override
  void dispose() {
    _peopleController.dispose();

    for (final TextEditingController controller in _productionControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (widget.organizationId.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Production Scenarios')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Organization information is missing. Please open this screen from an active organization.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Production Scenarios')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            final SurplusScenarioQuery? query = _query;

            if (query != null) {
              ref.invalidate(surplusScenarioProvider(query));
              await ref.read(surplusScenarioProvider(query).future);
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'Compare production plans',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Test several production quantities before service. '
                'FoodSense uses one demand forecast and calculates the '
                'expected surplus and risk for each production plan.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _buildInputCard(theme),
              const SizedBox(height: 20),
              if (_query == null)
                _buildInitialState(theme)
              else
                _buildResultState(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Scenario inputs',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Prediction date',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(_formatDate(_predictionDate)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _mealType,
              decoration: const InputDecoration(
                labelText: 'Meal type',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.restaurant_outlined),
              ),
              items: _mealTypes.map((String meal) {
                return DropdownMenuItem<String>(value: meal, child: Text(meal));
              }).toList(),
              onChanged: (String? value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _mealType = value;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _peopleController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Expected people',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.groups_outlined),
                helperText: 'Expected meals/people to serve.',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Production quantities',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...List<Widget>.generate(_productionControllers.length, (
              int index,
            ) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _productionControllers[index],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Scenario ${index + 1} production',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.local_dining_outlined),
                    suffixText: 'meals',
                  ),
                ),
              );
            }),
            const SizedBox(height: 2),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Special event'),
              subtitle: const Text(
                'Use event-aware historical demand when available.',
              ),
              value: _specialEvent,
              onChanged: (bool value) {
                setState(() {
                  _specialEvent = value;
                });
              },
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _compareScenarios,
              icon: const Icon(Icons.compare_arrows_rounded),
              label: const Text('Compare scenarios'),
            ),
          ],
        ),
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
              Icons.compare_arrows_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Ready to compare',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter several production quantities to see how the '
              'planned amount changes predicted surplus and risk.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultState(ThemeData theme) {
    final SurplusScenarioQuery query = _query!;
    final AsyncValue<List<SurplusScenarioResult>> asyncScenarios = ref.watch(
      surplusScenarioProvider(query),
    );

    return asyncScenarios.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Column(
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Comparing production scenarios...'),
              ],
            ),
          ),
        ),
      ),
      error: (Object error, StackTrace stackTrace) {
        return _buildErrorCard(theme, error, () {
          ref.invalidate(surplusScenarioProvider(query));
        });
      },
      data: (List<SurplusScenarioResult> results) {
        return _buildResults(theme, results, query);
      },
    );
  }

  Widget _buildResults(
    ThemeData theme,
    List<SurplusScenarioResult> results,
    SurplusScenarioQuery query,
  ) {
    if (results.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'The backend returned no production scenarios.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final int lowestSurplus = results
        .map((SurplusScenarioResult item) => item.predictedSurplus)
        .reduce((int a, int b) => a < b ? a : b);

    final int highestSurplus = results
        .map((SurplusScenarioResult item) => item.predictedSurplus)
        .reduce((int a, int b) => a > b ? a : b);

    final SurplusScenarioResult reference = results.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.analytics_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${query.mealType} production comparison',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _MetricRow(
                  label: 'Expected people',
                  value: _formatInteger(query.expectedPeople),
                ),
                _MetricRow(
                  label: 'Predicted demand',
                  value: '${_formatInteger(reference.predictedDemand)} meals',
                ),
                _MetricRow(
                  label: 'Scenarios returned',
                  value: '${results.length}',
                ),
                _MetricRow(
                  label: 'Surplus range',
                  value:
                      '${_formatInteger(lowestSurplus)}–'
                      '${_formatInteger(highestSurplus)} meals',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Scenario results',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...results.map((SurplusScenarioResult result) {
          final bool lowest = result.predictedSurplus == lowestSurplus;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildScenarioCard(theme, result, highlight: lowest),
          );
        }),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The highlighted scenario has the lowest predicted '
                    'surplus among the submitted production quantities. '
                    'Review operational needs and safety requirements '
                    'before selecting a production plan.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScenarioCard(
    ThemeData theme,
    SurplusScenarioResult result, {
    required bool highlight,
  }) {
    final Color riskColor = _riskColor(theme, result.surplusRisk);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: highlight
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(color: theme.colorScheme.primary, width: 4),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${_formatInteger(result.plannedProduction)} meals',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(_titleCase(result.surplusRisk)),
                    avatar: Icon(
                      result.surplusRisk.toLowerCase() == 'none'
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      size: 16,
                    ),
                    backgroundColor: riskColor.withValues(alpha: 0.10),
                    side: BorderSide(color: riskColor),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (highlight) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'Lowest predicted surplus in this comparison',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _MetricRow(
                label: 'Predicted demand',
                value: '${_formatInteger(result.predictedDemand)} meals',
              ),
              _MetricRow(
                label: 'Predicted surplus',
                value: '${_formatInteger(result.predictedSurplus)} meals',
              ),
              _MetricRow(
                label: 'Surplus percentage',
                value: '${result.surplusPercent.toStringAsFixed(1)}%',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme, Object error, VoidCallback onRetry) {
    final String message = error is FoodSenseApiException
        ? error.message
        : error.toString().replaceFirst('Exception: ', '');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(Icons.error_outline, size: 42, color: theme.colorScheme.error),
            const SizedBox(height: 10),
            Text(
              'Scenario comparison failed',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 6),
            Text(message),
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

  Future<void> _pickDate() async {
    final DateTime today = DateTime.now();
    final DateTime todayOnly = DateTime(today.year, today.month, today.day);

    final DateTime initialDate = _predictionDate.isBefore(todayOnly)
        ? todayOnly
        : _predictionDate;

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: todayOnly,
      lastDate: DateTime(2100),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _predictionDate = selected;
    });
  }

  void _compareScenarios() {
    final int? expectedPeople = int.tryParse(_peopleController.text.trim());

    if (expectedPeople == null || expectedPeople < 0) {
      _showMessage('Enter a valid non-negative expected people value.');
      return;
    }

    final List<int> productionSteps = <int>[];

    for (final TextEditingController controller in _productionControllers) {
      final String text = controller.text.trim();

      if (text.isEmpty) {
        continue;
      }

      final int? value = int.tryParse(text);

      if (value == null || value < 0) {
        _showMessage(
          'Production quantities must be valid non-negative numbers.',
        );
        return;
      }

      productionSteps.add(value);
    }

    final List<int> uniqueSteps = productionSteps.toSet().toList()..sort();

    if (uniqueSteps.isEmpty) {
      _showMessage('Enter at least one production quantity.');
      return;
    }

    final DateTime today = DateTime.now();
    final DateTime todayOnly = DateTime(today.year, today.month, today.day);

    if (_predictionDate.isBefore(todayOnly)) {
      _showMessage('Prediction date cannot be earlier than today.');
      setState(() {
        _predictionDate = todayOnly;
      });
      return;
    }

    setState(() {
      _query = SurplusScenarioQuery(
        organizationId: widget.organizationId.trim(),
        predictionDate: _predictionDate,
        mealType: _mealType,
        expectedPeople: expectedPeople,
        specialEvent: _specialEvent,
        productionSteps: uniqueSteps,
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatDate(DateTime value) {
    final DateTime local = value.toLocal();
    final String month = local.month.toString().padLeft(2, '0');
    final String day = local.day.toString().padLeft(2, '0');

    return '${local.year}-$month-$day';
  }

  static String _formatInteger(int value) {
    final String digits = value.abs().toString();
    final StringBuffer formatted = StringBuffer();

    for (int index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        formatted.write(',');
      }

      formatted.write(digits[index]);
    }

    final String result = formatted.toString();

    return value < 0 ? '-$result' : result;
  }

  static String _titleCase(String value) {
    final String normalized = value.trim().toLowerCase();

    if (normalized.isEmpty) {
      return 'Unknown';
    }

    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  static Color _riskColor(ThemeData theme, String risk) {
    switch (risk.trim().toLowerCase()) {
      case 'none':
        return theme.colorScheme.primary;
      case 'low':
        return theme.colorScheme.primary;
      case 'medium':
        return theme.colorScheme.tertiary;
      case 'high':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.outline;
    }
  }
}

/// Immutable parameters for the scenario-comparison provider.
class SurplusScenarioQuery {
  const SurplusScenarioQuery({
    required this.organizationId,
    required this.predictionDate,
    required this.mealType,
    required this.expectedPeople,
    required this.specialEvent,
    required this.productionSteps,
  });

  final String organizationId;
  final DateTime predictionDate;
  final String mealType;
  final int expectedPeople;
  final bool specialEvent;
  final List<int> productionSteps;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is SurplusScenarioQuery &&
        other.organizationId == organizationId &&
        _sameDate(other.predictionDate, predictionDate) &&
        other.mealType == mealType &&
        other.expectedPeople == expectedPeople &&
        other.specialEvent == specialEvent &&
        _sameList(other.productionSteps, productionSteps);
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    predictionDate.year,
    predictionDate.month,
    predictionDate.day,
    mealType,
    expectedPeople,
    specialEvent,
    Object.hashAll(productionSteps),
  );

  static bool _sameDate(DateTime left, DateTime right) {
    final DateTime a = left.toLocal();
    final DateTime b = right.toLocal();

    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool _sameList(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }

    return true;
  }
}

/// Calls the Phase 2 `/surplus/scenarios` endpoint and parses its list
/// response into typed results.
final surplusScenarioProvider = FutureProvider.autoDispose
    .family<List<SurplusScenarioResult>, SurplusScenarioQuery>((
      ref,
      query,
    ) async {
      final FoodSenseAiApiClient client = ref.watch(
        foodSenseAiApiClientProvider,
      );

      final List<Map<String, dynamic>> response = await client.surplusScenarios(
        <String, dynamic>{
          'organization_id': query.organizationId.trim(),
          'prediction_date': _dateOnlyValue(query.predictionDate),
          'meal_type': query.mealType,
          'planned_production': query.productionSteps.first,
          'expected_people': query.expectedPeople,
          'special_event': query.specialEvent,
          'production_steps': query.productionSteps,
        },
      );

      return response
          .map(SurplusScenarioResult.fromMap)
          .toList(growable: false);
    });

/// Typed representation of one backend scenario result.
class SurplusScenarioResult {
  const SurplusScenarioResult({
    required this.plannedProduction,
    required this.predictedDemand,
    required this.predictedSurplus,
    required this.surplusPercent,
    required this.surplusRisk,
  });

  final int plannedProduction;
  final int predictedDemand;
  final int predictedSurplus;
  final double surplusPercent;
  final String surplusRisk;

  factory SurplusScenarioResult.fromMap(Map<String, dynamic> map) {
    return SurplusScenarioResult(
      plannedProduction: _intValue(
        map['planned_production'],
        'planned_production',
      ),
      predictedDemand: _intValue(map['predicted_demand'], 'predicted_demand'),
      predictedSurplus: _intValue(
        map['predicted_surplus'],
        'predicted_surplus',
      ),
      surplusPercent: _doubleValue(map['surplus_percent'], 'surplus_percent'),
      surplusRisk: _stringValue(map['surplus_risk'], 'surplus_risk'),
    );
  }

  static int _intValue(dynamic value, String field) {
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

    throw FormatException(
      'Surplus scenario field "$field" must be an integer.',
    );
  }

  static double _doubleValue(dynamic value, String field) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final double? parsed = double.tryParse(value);

      if (parsed != null) {
        return parsed;
      }
    }

    throw FormatException('Surplus scenario field "$field" must be a number.');
  }

  static String _stringValue(dynamic value, String field) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    throw FormatException(
      'Surplus scenario field "$field" must be a non-empty string.',
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

String _dateOnlyValue(DateTime value) {
  final DateTime local = value.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');

  return '${local.year}-$month-$day';
}
