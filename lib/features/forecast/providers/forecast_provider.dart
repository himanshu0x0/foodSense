import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:foodsense/core/network/foodsense_ai_api_client.dart';
import 'package:foodsense/features/forecast/models/forecast_model.dart';
import 'package:foodsense/features/forecast/services/forecast_api_service.dart';

/// Base URL used by the Flutter app to reach the FoodSense FastAPI backend.
///
/// For a physical Android device with:
///   adb reverse tcp:8000 tcp:8000
/// use the default:
///   http://127.0.0.1:8000
///
/// For an Android emulator, override it at build/run time with:
///   --dart-define=FOODSENSE_API_BASE_URL=http://10.0.2.2:8000
///
/// For a production deployment, provide the HTTPS API URL using the same
/// dart-define instead of hard-coding it into feature code.
const String foodSenseApiBaseUrl = String.fromEnvironment(
  'FOODSENSE_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

/// Global FoodSense AI API client.
///
/// The provider owns the HTTP client lifecycle so feature providers can
/// reuse one client instead of creating a new HTTP connection pool for every
/// forecast request.
final foodSenseAiApiClientProvider = Provider<FoodSenseAiApiClient>((ref) {
  final client = FoodSenseAiApiClient(baseUrl: foodSenseApiBaseUrl);

  ref.onDispose(client.dispose);

  return client;
});

/// Typed demand-forecast service.
final forecastApiServiceProvider = Provider<ForecastApiService>((ref) {
  return ForecastApiService(apiClient: ref.watch(foodSenseAiApiClientProvider));
});

/// Immutable parameters used to request one demand forecast.
///
/// Keeping these parameters in a value object makes the Riverpod family key
/// stable and prevents widgets from passing loosely typed maps around.
class ForecastQuery {
  const ForecastQuery({
    required this.organizationId,
    required this.forecastDate,
    required this.mealType,
    required this.expectedPeople,
    this.specialEvent = false,
    this.menu,
  });

  final String organizationId;
  final DateTime forecastDate;
  final String mealType;
  final int expectedPeople;
  final bool specialEvent;
  final String? menu;

  ForecastQuery copyWith({
    String? organizationId,
    DateTime? forecastDate,
    String? mealType,
    int? expectedPeople,
    bool? specialEvent,
    String? menu,
  }) {
    return ForecastQuery(
      organizationId: organizationId ?? this.organizationId,
      forecastDate: forecastDate ?? this.forecastDate,
      mealType: mealType ?? this.mealType,
      expectedPeople: expectedPeople ?? this.expectedPeople,
      specialEvent: specialEvent ?? this.specialEvent,
      menu: menu ?? this.menu,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is ForecastQuery &&
        other.organizationId == organizationId &&
        _sameDate(other.forecastDate, forecastDate) &&
        other.mealType == mealType &&
        other.expectedPeople == expectedPeople &&
        other.specialEvent == specialEvent &&
        other.menu == menu;
  }

  @override
  int get hashCode {
    return Object.hash(
      organizationId,
      forecastDate.year,
      forecastDate.month,
      forecastDate.day,
      mealType,
      expectedPeople,
      specialEvent,
      menu,
    );
  }

  static bool _sameDate(DateTime left, DateTime right) {
    final a = left.toLocal();
    final b = right.toLocal();

    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  String toString() {
    return 'ForecastQuery('
        'organizationId: $organizationId, '
        'forecastDate: $forecastDate, '
        'mealType: $mealType, '
        'expectedPeople: $expectedPeople, '
        'specialEvent: $specialEvent, '
        'menu: $menu'
        ')';
  }
}

/// Fetches one demand forecast from the Phase 2 backend.
///
/// Riverpod exposes the request as [AsyncValue], giving the UI a clean
/// loading/data/error state without putting networking code in widgets.
final forecastProvider = FutureProvider.autoDispose
    .family<ForecastModel, ForecastQuery>((ref, query) async {
      final service = ref.watch(forecastApiServiceProvider);

      return service.getForecast(
        organizationId: query.organizationId,
        forecastDate: query.forecastDate,
        mealType: query.mealType,
        expectedPeople: query.expectedPeople,
        specialEvent: query.specialEvent,
        menu: query.menu,
      );
    });

/// Checks Forecast API health.
///
/// This provider is intentionally separate from [forecastProvider] because
/// the health endpoint is unauthenticated and does not require organization
/// parameters.
final forecastHealthProvider = FutureProvider.autoDispose<bool>((ref) async {
  final service = ref.watch(forecastApiServiceProvider);
  return service.isHealthy();
});
