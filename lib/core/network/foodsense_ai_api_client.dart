import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Exception thrown when the FoodSense backend returns an error.
class FoodSenseApiException implements Exception {
  const FoodSenseApiException({
    required this.statusCode,
    required this.message,
    this.details,
  });

  final int statusCode;
  final String message;
  final Object? details;

  @override
  String toString() {
    return 'FoodSenseApiException($statusCode): $message';
  }
}

/// Authenticated HTTP client for the FoodSense Phase 2 AI backend.
///
/// The client:
/// - Gets a Firebase ID token from the currently signed-in user.
/// - Sends it as `Authorization: Bearer <token>`.
/// - Handles 401/403/422/server errors consistently.
/// - Retries a 401 once with a refreshed Firebase token.
/// - Keeps the backend base URL configurable for emulator, physical device,
///   and production environments.
///
/// Example:
/// ```dart
/// final api = FoodSenseAiApiClient(
///   baseUrl: 'http://10.0.2.2:8000',
/// );
///
/// final forecast = await api.forecast({
///   'organization_id': organizationId,
///   'forecast_date': '2026-09-26',
///   'meal_type': 'Lunch',
///   'expected_people': 1800,
///   'special_event': false,
///   'menu': 'Standard Lunch',
/// });
/// ```
class FoodSenseAiApiClient {
  FoodSenseAiApiClient({
    required String baseUrl,
    http.Client? httpClient,
    FirebaseAuth? firebaseAuth,
    Duration timeout = const Duration(seconds: 30),
  })  : baseUrl = _normalizeBaseUrl(baseUrl),
        _httpClient = httpClient ?? http.Client(),
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _timeout = timeout;

  final String baseUrl;
  final http.Client _httpClient;
  final FirebaseAuth _firebaseAuth;
  final Duration _timeout;

  /// Calls GET /forecast/health without Firebase authentication.
  Future<Map<String, dynamic>> forecastHealth() {
    return _get('/forecast/health');
  }

  /// Calls GET /surplus/health without Firebase authentication.
  Future<Map<String, dynamic>> surplusHealth() {
    return _get('/surplus/health');
  }

  /// Calls GET /waste/health without Firebase authentication.
  Future<Map<String, dynamic>> wasteHealth() {
    return _get('/waste/health');
  }

  /// Calls POST /forecast with the current Firebase user's ID token.
  Future<Map<String, dynamic>> forecast(
    Map<String, dynamic> request,
  ) {
    return _postAuthenticated('/forecast', request);
  }

  /// Calls POST /surplus with the current Firebase user's ID token.
  Future<Map<String, dynamic>> surplus(
    Map<String, dynamic> request,
  ) {
    return _postAuthenticated('/surplus', request);
  }

  /// Calls POST /surplus/scenarios with the current Firebase user's ID token.
  Future<Map<String, dynamic>> surplusScenarios(
    Map<String, dynamic> request,
  ) {
    return _postAuthenticated('/surplus/scenarios', request);
  }

  /// Calls POST /waste with the current Firebase user's ID token.
  Future<Map<String, dynamic>> waste(
    Map<String, dynamic> request,
  ) {
    return _postAuthenticated('/waste', request);
  }

  /// Calls POST /waste/trend with the current Firebase user's ID token.
  Future<Map<String, dynamic>> wasteTrend(
    Map<String, dynamic> request,
  ) {
    return _postAuthenticated('/waste/trend', request);
  }

  /// Gets the current user's Firebase ID token.
  ///
  /// Throws [FoodSenseApiException] when no user is signed in.
  Future<String> _getIdToken({bool forceRefresh = false}) async {
    final user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const FoodSenseApiException(
        statusCode: 401,
        message: 'No authenticated Firebase user is signed in.',
      );
    }

    final token = await user.getIdToken(forceRefresh);

    if (token == null || token.isEmpty) {
      throw const FoodSenseApiException(
        statusCode: 401,
        message: 'Firebase ID token could not be obtained.',
      );
    }

    return token;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _httpClient
        .get(
          _buildUri(path),
          headers: const <String, String>{
            'Accept': 'application/json',
          },
        )
        .timeout(_timeout);

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postAuthenticated(
    String path,
    Map<String, dynamic> body,
  ) async {
    String token = await _getIdToken();

    http.Response response = await _sendPost(
      path: path,
      body: body,
      token: token,
    );

    // If the token has expired between Firebase and the backend, refresh it
    // once and retry. Other errors are returned immediately.
    if (response.statusCode == 401) {
      token = await _getIdToken(forceRefresh: true);

      response = await _sendPost(
        path: path,
        body: body,
        token: token,
      );
    }

    return _decodeResponse(response);
  }

  Future<http.Response> _sendPost({
    required String path,
    required Map<String, dynamic> body,
    required String token,
  }) {
    return _httpClient
        .post(
          _buildUri(path),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Object? decoded;

    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = response.body;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw FoodSenseApiException(
        statusCode: response.statusCode,
        message: 'Backend returned an unexpected response format.',
        details: decoded,
      );
    }

    throw FoodSenseApiException(
      statusCode: response.statusCode,
      message: _extractErrorMessage(decoded, response.statusCode),
      details: decoded,
    );
  }

  String _extractErrorMessage(Object? decoded, int statusCode) {
    if (decoded is Map<String, dynamic>) {
      final detail = decoded['detail'];

      if (detail is String && detail.isNotEmpty) {
        return detail;
      }

      if (detail is List && detail.isNotEmpty) {
        return detail
            .map((item) {
              if (item is Map<String, dynamic>) {
                final message = item['msg'];
                final location = item['loc'];

                if (message != null && location != null) {
                  return '${location.toString()}: $message';
                }

                if (message != null) {
                  return message.toString();
                }
              }

              return item.toString();
            })
            .join('; ');
      }
    }

    switch (statusCode) {
      case 401:
        return 'Authentication failed. Please sign in again.';
      case 403:
        return 'You do not have access to this organization.';
      case 422:
        return 'The request data is invalid.';
      case 429:
        return 'Too many requests. Please try again shortly.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'FoodSense backend is temporarily unavailable.';
      default:
        return 'FoodSense backend request failed with status $statusCode.';
    }
  }

  Uri _buildUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        value,
        'baseUrl',
        'FoodSense API base URL cannot be empty.',
      );
    }

    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// Releases the underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }
}
