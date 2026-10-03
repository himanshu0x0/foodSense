import 'dart:convert';

/// Represents the result returned by the FoodSense forecasting API.
///
/// This model mirrors the backend `ForecastResponse` schema so Flutter can
/// safely consume forecast results without exposing JSON parsing details to
/// the presentation layer.
class ForecastModel {
  const ForecastModel({
    required this.organizationId,
    required this.forecastDate,
    required this.mealType,
    required this.expectedPeople,
    required this.predictedDemand,
    required this.safetyBuffer,
    required this.recommendedProduction,
    required this.safetyBufferPercent,
    required this.confidence,
    required this.method,
    required this.trainingRecords,
    required this.fallbackUsed,
    required this.generatedAt,
  });

  final String organizationId;
  final DateTime forecastDate;
  final String mealType;

  final int expectedPeople;

  /// Predicted number of meals likely to be consumed.
  final int predictedDemand;

  /// Additional meals added to absorb forecast uncertainty.
  final int safetyBuffer;

  /// Suggested number of meals to prepare.
  final int recommendedProduction;

  final double safetyBufferPercent;

  /// Nullable because the current baseline engine does not produce a
  /// statistically calibrated confidence value yet.
  final double? confidence;

  /// Example: `recency_weighted_baseline`.
  final String method;

  /// Number of historical records used for this forecast.
  final int trainingRecords;

  /// True when the backend used its cold-start fallback.
  final bool fallbackUsed;

  /// UTC timestamp returned by the backend.
  final DateTime generatedAt;

  /// Creates a model from an API response map.
  factory ForecastModel.fromMap(Map<String, dynamic> map) {
    return ForecastModel(
      organizationId: _stringValue(
        map['organization_id'],
        field: 'organization_id',
      ),
      forecastDate: _dateValue(map['forecast_date'], field: 'forecast_date'),
      mealType: _stringValue(map['meal_type'], field: 'meal_type'),
      expectedPeople: _intValue(
        map['expected_people'],
        field: 'expected_people',
      ),
      predictedDemand: _intValue(
        map['predicted_demand'],
        field: 'predicted_demand',
      ),
      safetyBuffer: _intValue(map['safety_buffer'], field: 'safety_buffer'),
      recommendedProduction: _intValue(
        map['recommended_production'],
        field: 'recommended_production',
      ),
      safetyBufferPercent: _doubleValue(
        map['safety_buffer_percent'],
        field: 'safety_buffer_percent',
      ),
      confidence: map['confidence'] == null
          ? null
          : _doubleValue(map['confidence'], field: 'confidence'),
      method: _stringValue(map['method'], field: 'method'),
      trainingRecords: _intValue(
        map['training_records'],
        field: 'training_records',
      ),
      fallbackUsed: map['fallback_used'] == true,
      generatedAt: _dateTimeValue(map['generated_at'], field: 'generated_at'),
    );
  }

  /// Creates a model from a JSON response.
  factory ForecastModel.fromJson(String source) {
    final dynamic decoded = jsonDecode(source);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Forecast response must be a JSON object.');
    }

    return ForecastModel.fromMap(decoded);
  }

  /// Converts the model into a JSON-compatible map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'organization_id': organizationId,
      'forecast_date': _dateOnlyString(forecastDate),
      'meal_type': mealType,
      'expected_people': expectedPeople,
      'predicted_demand': predictedDemand,
      'safety_buffer': safetyBuffer,
      'recommended_production': recommendedProduction,
      'safety_buffer_percent': safetyBufferPercent,
      'confidence': confidence,
      'method': method,
      'training_records': trainingRecords,
      'fallback_used': fallbackUsed,
      'generated_at': generatedAt.toUtc().toIso8601String(),
    };
  }

  /// Converts the model to JSON.
  String toJson() {
    return jsonEncode(toMap());
  }

  /// Creates a modified copy of this forecast.
  ForecastModel copyWith({
    String? organizationId,
    DateTime? forecastDate,
    String? mealType,
    int? expectedPeople,
    int? predictedDemand,
    int? safetyBuffer,
    int? recommendedProduction,
    double? safetyBufferPercent,
    double? confidence,
    String? method,
    int? trainingRecords,
    bool? fallbackUsed,
    DateTime? generatedAt,
  }) {
    return ForecastModel(
      organizationId: organizationId ?? this.organizationId,
      forecastDate: forecastDate ?? this.forecastDate,
      mealType: mealType ?? this.mealType,
      expectedPeople: expectedPeople ?? this.expectedPeople,
      predictedDemand: predictedDemand ?? this.predictedDemand,
      safetyBuffer: safetyBuffer ?? this.safetyBuffer,
      recommendedProduction:
          recommendedProduction ?? this.recommendedProduction,
      safetyBufferPercent: safetyBufferPercent ?? this.safetyBufferPercent,
      confidence: confidence ?? this.confidence,
      method: method ?? this.method,
      trainingRecords: trainingRecords ?? this.trainingRecords,
      fallbackUsed: fallbackUsed ?? this.fallbackUsed,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  /// Predicted demand divided by expected people.
  double get predictedDemandRate {
    if (expectedPeople <= 0) {
      return 0;
    }

    return predictedDemand / expectedPeople;
  }

  /// Difference between recommended production and expected attendance.
  int get productionDifferenceFromExpected {
    return recommendedProduction - expectedPeople;
  }

  /// True when historical training data was actually used.
  bool get hasHistoricalTrainingData {
    return trainingRecords > 0 && !fallbackUsed;
  }

  /// True when the current recency-weighted baseline was used.
  bool get isBaselineForecast {
    return method.contains('baseline');
  }

  @override
  String toString() {
    return 'ForecastModel('
        'organizationId: $organizationId, '
        'forecastDate: $forecastDate, '
        'mealType: $mealType, '
        'expectedPeople: $expectedPeople, '
        'predictedDemand: $predictedDemand, '
        'safetyBuffer: $safetyBuffer, '
        'recommendedProduction: $recommendedProduction, '
        'trainingRecords: $trainingRecords, '
        'fallbackUsed: $fallbackUsed'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is ForecastModel &&
        other.organizationId == organizationId &&
        other.forecastDate == forecastDate &&
        other.mealType == mealType &&
        other.expectedPeople == expectedPeople &&
        other.predictedDemand == predictedDemand &&
        other.safetyBuffer == safetyBuffer &&
        other.recommendedProduction == recommendedProduction &&
        other.safetyBufferPercent == safetyBufferPercent &&
        other.confidence == confidence &&
        other.method == method &&
        other.trainingRecords == trainingRecords &&
        other.fallbackUsed == fallbackUsed &&
        other.generatedAt == generatedAt;
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    forecastDate,
    mealType,
    expectedPeople,
    predictedDemand,
    safetyBuffer,
    recommendedProduction,
    safetyBufferPercent,
    confidence,
    method,
    trainingRecords,
    fallbackUsed,
    generatedAt,
  );

  static String _stringValue(dynamic value, {required String field}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    throw FormatException(
      'Forecast field "$field" must be a non-empty string.',
    );
  }

  static int _intValue(dynamic value, {required String field}) {
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

    throw FormatException('Forecast field "$field" must be an integer.');
  }

  static double _doubleValue(dynamic value, {required String field}) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final double? parsed = double.tryParse(value);

      if (parsed != null) {
        return parsed;
      }
    }

    throw FormatException('Forecast field "$field" must be a number.');
  }

  static DateTime _dateValue(dynamic value, {required String field}) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }

    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);

      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
    }

    throw FormatException('Forecast field "$field" must be a valid date.');
  }

  static DateTime _dateTimeValue(dynamic value, {required String field}) {
    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);

      if (parsed != null) {
        return parsed.toLocal();
      }
    }

    throw FormatException('Forecast field "$field" must be a valid timestamp.');
  }

  static String _dateOnlyString(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
