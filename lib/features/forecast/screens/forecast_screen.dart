import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:foodsense/core/network/foodsense_ai_api_client.dart';
import 'package:foodsense/features/forecast/models/forecast_model.dart';
import 'package:foodsense/features/forecast/providers/forecast_provider.dart';

/// Phase 2 demand-forecast screen.
///
/// The screen intentionally accepts the organization ID from the caller so
/// organization selection/ownership stays in the existing FoodSense app state
/// rather than being duplicated inside the forecasting feature.
class ForecastScreen extends ConsumerStatefulWidget {
  const ForecastScreen({required this.organizationId, super.key});

  final String organizationId;

  @override
  ConsumerState<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends ConsumerState<ForecastScreen> {
  late final TextEditingController _peopleController;
  late final TextEditingController _menuController;

  DateTime _forecastDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  String _mealType = 'Lunch';
  bool _specialEvent = false;
  ForecastQuery? _query;

  @override
  void initState() {
    super.initState();
    _peopleController = TextEditingController(text: '1800');
    _menuController = TextEditingController();
  }

  @override
  void dispose() {
    _peopleController.dispose();
    _menuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Demand Forecast')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(theme),
              const SizedBox(height: 20),
              _buildInputCard(theme),
              const SizedBox(height: 20),
              if (_query == null)
                _buildInitialState(theme)
              else
                _buildForecastState(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'AI-powered production planning',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'FoodSense uses historical kitchen data and expected attendance '
          'to estimate demand and recommended production.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
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
              'Forecast inputs',
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
                  labelText: 'Forecast date',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(_formatDate(_forecastDate)),
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
              items:
                  const <String>[
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
                hintText: 'Example: 1800',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _menuController,
              decoration: const InputDecoration(
                labelText: 'Menu (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.menu_book_outlined),
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
              onPressed: _requestForecast,
              icon: const Icon(Icons.auto_graph),
              label: const Text('Generate forecast'),
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
              Icons.analytics_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Ready for a forecast',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the expected attendance and meal details, then generate '
              'a demand forecast from the FoodSense AI backend.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastState(ThemeData theme) {
    final ForecastQuery query = _query!;
    final forecastAsync = ref.watch(forecastProvider(query));

    return forecastAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Column(
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Generating forecast...'),
              ],
            ),
          ),
        ),
      ),
      error: (Object error, StackTrace stackTrace) {
        final message = _friendlyError(error);

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
                  'Forecast failed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(message),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.invalidate(forecastProvider(query));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      },
      data: (ForecastModel forecast) => _buildResultCard(theme, forecast),
    );
  }

  Widget _buildResultCard(ThemeData theme, ForecastModel forecast) {
    final bool historical = forecast.hasHistoricalTrainingData;

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
                    Icon(Icons.auto_graph, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${forecast.mealType} forecast',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StatusChip(
                      label: historical ? 'Historical AI' : 'Fallback',
                      icon: historical
                          ? Icons.history
                          : Icons.restart_alt_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDate(forecast.forecastDate),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                _MetricTile(
                  label: 'Predicted demand',
                  value: '${forecast.predictedDemand}',
                  unit: 'meals',
                  icon: Icons.restaurant_outlined,
                ),
                const SizedBox(height: 10),
                _MetricTile(
                  label: 'Safety buffer',
                  value: '${forecast.safetyBuffer}',
                  unit: '${forecast.safetyBufferPercent.toStringAsFixed(1)}%',
                  icon: Icons.shield_outlined,
                ),
                const SizedBox(height: 10),
                _MetricTile(
                  label: 'Recommended production',
                  value: '${forecast.recommendedProduction}',
                  unit: 'meals',
                  icon: Icons.local_dining_outlined,
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
                  'Forecast details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'Expected people',
                  value: '${forecast.expectedPeople}',
                ),
                _DetailRow(
                  label: 'Training records',
                  value: '${forecast.trainingRecords}',
                ),
                _DetailRow(
                  label: 'Method',
                  value: _formatMethod(forecast.method),
                ),
                _DetailRow(
                  label: 'Confidence',
                  value: forecast.confidence == null
                      ? 'Not available'
                      : '${(forecast.confidence! * 100).toStringAsFixed(1)}%',
                ),
                _DetailRow(
                  label: 'Generated',
                  value: _formatDateTime(forecast.generatedAt),
                ),
              ],
            ),
          ),
        ),
        if (forecast.fallbackUsed) ...<Widget>[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'There is not enough historical data for this forecast yet. '
                'FoodSense used the expected attendance as a fallback.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickDate() async {
    final DateTime today = DateTime.now();
    final DateTime todayOnly = DateTime(today.year, today.month, today.day);

    final DateTime initialDate = _forecastDate.isBefore(todayOnly)
        ? todayOnly
        : _forecastDate;

    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: todayOnly,
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      setState(() {
        _forecastDate = selected;
      });
    }
  }

  void _requestForecast() {
    final int? expectedPeople = int.tryParse(_peopleController.text.trim());

    if (expectedPeople == null || expectedPeople < 0) {
      _showMessage('Enter a valid non-negative number of people.');
      return;
    }

    final DateTime today = DateTime.now();
    final DateTime todayOnly = DateTime(today.year, today.month, today.day);

    if (_forecastDate.isBefore(todayOnly)) {
      _showMessage(
        'Forecast date cannot be earlier than today. Please select '
        'today or a future date.',
      );

      setState(() {
        _forecastDate = todayOnly;
      });

      return;
    }

    setState(() {
      _query = ForecastQuery(
        organizationId: widget.organizationId,
        forecastDate: _forecastDate,
        mealType: _mealType,
        expectedPeople: expectedPeople,
        specialEvent: _specialEvent,
        menu: _menuController.text.trim().isEmpty
            ? null
            : _menuController.text.trim(),
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
        .map((String part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
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
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.icon});

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
