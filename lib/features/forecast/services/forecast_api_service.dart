import 'package:foodsense/core/network/foodsense_ai_api_client.dart';
import 'package:foodsense/features/forecast/models/forecast_model.dart';

/// Typed service for the FoodSense demand-forecast API.
///
/// This layer converts application-level forecast parameters into the
/// backend request shape and converts the JSON response into [ForecastModel].
/// UI/widgets should depend on this service rather than constructing API
/// payloads directly.
class ForecastApiService {
  ForecastApiService({required FoodSenseAiApiClient apiClient})
    : _apiClient = apiClient;

  final FoodSenseAiApiClient _apiClient;

  /// Requests a demand forecast for one organization, date and meal.
  ///
  /// The backend remains the source of truth for the actual prediction.
  /// Flutter is responsible only for building a valid request and parsing the
  /// typed response.
  Future<ForecastModel> getForecast({
    required String organizationId,
    required DateTime forecastDate,
    required String mealType,
    required int expectedPeople,
    bool specialEvent = false,
    String? menu,
  }) async {
    _validateRequest(
      organizationId: organizationId,
      mealType: mealType,
      expectedPeople: expectedPeople,
    );

    final response = await _apiClient.forecast(<String, dynamic>{
      'organization_id': organizationId.trim(),
      'forecast_date': _dateOnly(forecastDate),
      'meal_type': mealType,
      'expected_people': expectedPeople,
      'special_event': specialEvent,
      if (menu != null && menu.trim().isNotEmpty) 'menu': menu.trim(),
    });

    return ForecastModel.fromMap(response);
  }

  /// Checks whether the Forecast backend module is reachable.
  ///
  /// This endpoint does not require Firebase authentication.
  Future<bool> isHealthy() async {
    try {
      final response = await _apiClient.forecastHealth();
      final status = response['status'];

      if (status == null) {
        return true;
      }

      return status.toString().toLowerCase() == 'healthy' ||
          status.toString().toLowerCase() == 'ok';
    } on Object {
      return false;
    }
  }

  void _validateRequest({
    required String organizationId,
    required String mealType,
    required int expectedPeople,
  }) {
    if (organizationId.trim().isEmpty) {
      throw ArgumentError.value(
        organizationId,
        'organizationId',
        'Organization ID cannot be empty.',
      );
    }

    const allowedMealTypes = <String>{
      'Breakfast',
      'Lunch',
      'Dinner',
      'Snack',
      'Other',
    };

    if (!allowedMealTypes.contains(mealType)) {
      throw ArgumentError.value(
        mealType,
        'mealType',
        'Meal type must be one of: '
            'Breakfast, Lunch, Dinner, Snack, Other.',
      );
    }

    if (expectedPeople < 0) {
      throw ArgumentError.value(
        expectedPeople,
        'expectedPeople',
        'Expected people cannot be negative.',
      );
    }
  }

  String _dateOnly(DateTime value) {
    final localDate = value.toLocal();

    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');

    return '${localDate.year}-$month-$day';
  }
}
