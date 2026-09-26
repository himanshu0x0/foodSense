import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foodsense/core/network/foodsense_ai_api_client.dart';
import 'package:foodsense/features/forecast/providers/forecast_provider.dart';

class SurplusScreen extends ConsumerStatefulWidget {
  const SurplusScreen({
    required this.organizationId,
    super.key,
  });

  final String organizationId;

  @override
  ConsumerState<SurplusScreen> createState() => _SurplusScreenState();
}

class _SurplusScreenState extends ConsumerState<SurplusScreen> {
  late final TextEditingController _productionController;
  late final TextEditingController _peopleController;

  DateTime _predictionDate = DateTime.now();
  String _mealType = 'Lunch';
  bool _specialEvent = false;
  SurplusQuery? _query;

  @override
  void initState() {
    super.initState();
    _productionController = TextEditingController(text: '1900');
    _peopleController = TextEditingController(text: '1800');
  }

  @override
  void dispose() {
    _productionController.dispose();
    _peopleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Surplus Prediction'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Plan production before surplus happens',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'FoodSense combines the AI demand forecast with your planned '
                'production to estimate meals likely to remain after service.',
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
              'Production inputs',
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
              items: const <String>[
                'Breakfast',
                'Lunch',
                'Dinner',
                'Snack',
                'Other',
              ].map((String meal) {
                return DropdownMenuItem<String>(
                  value: meal,
                  child: Text(meal),
                );
              }).toList(),
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _mealType = value;
                  });
                }
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
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _productionController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Planned production',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_dining_outlined),
                helperText: 'Number of meals you plan to prepare.',
              ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _requestPrediction,
              icon: const Icon(Icons.auto_graph),
              label: const Text('Predict surplus'),
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
              Icons.inventory_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Ready to estimate surplus',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter planned production and expected attendance to see '
              'the estimated surplus and risk level.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultState(ThemeData theme) {
    final SurplusQuery query = _query!;
    final surplusAsync = ref.watch(surplusProvider(query));

    return surplusAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Column(
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Calculating expected surplus...'),
              ],
            ),
          ),
        ),
      ),
      error: (Object error, StackTrace stackTrace) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 10),
                Text(
                  'Surplus prediction failed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_friendlyError(error)),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.invalidate(surplusProvider(query));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      },
      data: (SurplusResult result) => _buildResultCard(theme, result),
    );
  }

  Widget _buildResultCard(ThemeData theme, SurplusResult result) {
    final bool historical = result.trainingRecords > 0 && !result.fallbackUsed;

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
                    Icon(
                      Icons.analytics_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${result.mealType} surplus',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StatusChip(
                      label: result.surplusRisk.toUpperCase(),
                      icon: Icons.warning_amber_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_formatDate(result.predictionDate)),
                const SizedBox(height: 18),
                _MetricTile(
                  label: 'Predicted demand',
                  value: '${result.predictedDemand}',
                  unit: 'meals',
                  icon: Icons.restaurant_outlined,
                ),
                const SizedBox(height: 10),
                _MetricTile(
                  label: 'Planned production',
                  value: '${result.plannedProduction}',
                  unit: 'meals',
                  icon: Icons.local_dining_outlined,
                ),
                const SizedBox(height: 10),
                _MetricTile(
                  label: 'Predicted surplus',
                  value: '${result.predictedSurplus}',
                  unit: '${result.surplusPercent.toStringAsFixed(1)}%',
                  icon: Icons.inventory_2_outlined,
                ),
                const SizedBox(height: 10),
                _MetricTile(
                  label: 'Estimated waste',
                  value: result.estimatedWasteKg.toStringAsFixed(2),
                  unit: 'kg',
                  icon: Icons.delete_outline_rounded,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Prediction details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'Expected people',
                  value: '${result.expectedPeople}',
                ),
                _DetailRow(
                  label: 'Training records',
                  value: '${result.trainingRecords}',
                ),
                _DetailRow(
                  label: 'Forecast source',
                  value: historical ? 'Historical data' : 'Fallback',
                ),
                _DetailRow(
                  label: 'Method',
                  value: _formatMethod(result.method),
                ),
                _DetailRow(
                  label: 'Generated',
                  value: _formatDateTime(result.generatedAt),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildActionGuidance(theme, result),
      ],
    );
  }

  Widget _buildActionGuidance(ThemeData theme, SurplusResult result) {
    if (result.predictedSurplus <= 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.check_circle_outline,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'The current production plan does not predict a surplus '
                  'after the demand forecast.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'FoodSense estimates ${result.predictedSurplus} meals '
                'may remain. Use this result as an operational planning '
                'signal and review the production quantity before service.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime today = DateTime.now();
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _predictionDate.isBefore(today) ? today : _predictionDate,
      firstDate: today,
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      setState(() {
        _predictionDate = selected;
      });
    }
  }

  void _requestPrediction() {
    final int? expectedPeople = int.tryParse(
      _peopleController.text.trim(),
    );
    final int? plannedProduction = int.tryParse(
      _productionController.text.trim(),
    );

    if (expectedPeople == null || expectedPeople < 0) {
      _showMessage('Enter a valid non-negative expected people value.');
      return;
    }

    if (plannedProduction == null || plannedProduction < 0) {
      _showMessage('Enter a valid non-negative planned production value.');
      return;
    }

    setState(() {
      _query = SurplusQuery(
        organizationId: widget.organizationId,
        predictionDate: _predictionDate,
        mealType: _mealType,
        expectedPeople: expectedPeople,
        plannedProduction: plannedProduction,
        specialEvent: _specialEvent,
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  String _friendlyError(Object error) {
    if (error is FoodSenseApiException) {
      return error.message;
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');

    return '${local.year}-$month-$day';
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '${_formatDate(local)} $hour:$minute';
  }

  static String _formatMethod(String method) {
    return method
        .replaceAll('_', ' ')
        .split(' ')
        .where((String part) => part.isNotEmpty)
        .map(
          (String part) =>
              '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }
}

class SurplusQuery {
  const SurplusQuery({
    required this.organizationId,
    required this.predictionDate,
    required this.mealType,
    required this.expectedPeople,
    required this.plannedProduction,
    required this.specialEvent,
  });

  final String organizationId;
  final DateTime predictionDate;
  final String mealType;
  final int expectedPeople;
  final int plannedProduction;
  final bool specialEvent;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is SurplusQuery &&
        other.organizationId == organizationId &&
        _sameDate(other.predictionDate, predictionDate) &&
        other.mealType == mealType &&
        other.expectedPeople == expectedPeople &&
        other.plannedProduction == plannedProduction &&
        other.specialEvent == specialEvent;
  }

  @override
  int get hashCode {
    return Object.hash(
      organizationId,
      predictionDate.year,
      predictionDate.month,
      predictionDate.day,
      mealType,
      expectedPeople,
      plannedProduction,
      specialEvent,
    );
  }

  static bool _sameDate(DateTime left, DateTime right) {
    final a = left.toLocal();
    final b = right.toLocal();

    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }
}

final surplusProvider =
    FutureProvider.autoDispose.family<SurplusResult, SurplusQuery>(
  (ref, query) async {
    final apiClient = ref.watch(foodSenseAiApiClientProvider);

    final response = await apiClient.surplus(
      <String, dynamic>{
        'organization_id': query.organizationId,
        'prediction_date': _dateOnly(query.predictionDate),
        'meal_type': query.mealType,
        'planned_production': query.plannedProduction,
        'expected_people': query.expectedPeople,
        'special_event': query.specialEvent,
      },
    );

    return SurplusResult.fromMap(response);
  },
);

class SurplusResult {
  const SurplusResult({
    required this.organizationId,
    required this.predictionDate,
    required this.mealType,
    required this.expectedPeople,
    required this.plannedProduction,
    required this.predictedDemand,
    required this.predictedSurplus,
    required this.surplusPercent,
    required this.surplusRisk,
    required this.estimatedWasteKg,
    required this.method,
    required this.trainingRecords,
    required this.fallbackUsed,
    required this.generatedAt,
  });

  final String organizationId;
  final DateTime predictionDate;
  final String mealType;
  final int expectedPeople;
  final int plannedProduction;
  final int predictedDemand;
  final int predictedSurplus;
  final double surplusPercent;
  final String surplusRisk;
  final double estimatedWasteKg;
  final String method;
  final int trainingRecords;
  final bool fallbackUsed;
  final DateTime generatedAt;

  factory SurplusResult.fromMap(Map<String, dynamic> map) {
    return SurplusResult(
      organizationId: _stringValue(map['organization_id'], 'organization_id'),
      predictionDate: _dateValue(map['prediction_date'], 'prediction_date'),
      mealType: _stringValue(map['meal_type'], 'meal_type'),
      expectedPeople: _intValue(map['expected_people'], 'expected_people'),
      plannedProduction: _intValue(
        map['planned_production'],
        'planned_production',
      ),
      predictedDemand: _intValue(
        map['predicted_demand'],
        'predicted_demand',
      ),
      predictedSurplus: _intValue(
        map['predicted_surplus'],
        'predicted_surplus',
      ),
      surplusPercent: _doubleValue(
        map['surplus_percent'],
        'surplus_percent',
      ),
      surplusRisk: _stringValue(map['surplus_risk'], 'surplus_risk'),
      estimatedWasteKg: _doubleValue(
        map['estimated_waste_kg'],
        'estimated_waste_kg',
      ),
      method: _stringValue(map['method'], 'method'),
      trainingRecords: _intValue(
        map['training_records'],
        'training_records',
      ),
      fallbackUsed: map['fallback_used'] == true,
      generatedAt: _dateValueTime(map['generated_at'], 'generated_at'),
    );
  }

  static String _stringValue(dynamic value, String field) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    throw FormatException(
      'Surplus field "$field" must be a non-empty string.',
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
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }

    throw FormatException(
      'Surplus field "$field" must be an integer.',
    );
  }

  static double _doubleValue(dynamic value, String field) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }

    throw FormatException(
      'Surplus field "$field" must be a number.',
    );
  }

  static DateTime _dateValue(dynamic value, String field) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }

    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
    }

    throw FormatException(
      'Surplus field "$field" must be a valid date.',
    );
  }

  static DateTime _dateValueTime(dynamic value, String field) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }

    throw FormatException(
      'Surplus field "$field" must be a valid timestamp.',
    );
  }
}

String _dateOnly(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');

  return '${local.year}-$month-$day';
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
          Text(
            unit,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
