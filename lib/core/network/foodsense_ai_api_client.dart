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
/// - Supports both JSON-object and JSON-array responses.
/// - Keeps the backend base URL configurable.
class FoodSenseAiApiClient {
  FoodSenseAiApiClient({
    required String baseUrl,
    http.Client? httpClient,
    FirebaseAuth? firebaseAuth,
    this.timeout = const Duration(seconds: 30),
  }) : baseUrl = _normalizeBaseUrl(baseUrl),
       _httpClient = httpClient ?? http.Client(),
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final String baseUrl;
  final http.Client _httpClient;
  final FirebaseAuth _firebaseAuth;
  final Duration timeout;

  Future<Map<String, dynamic>> forecastHealth() {
    return _getObject('/forecast/health');
  }

  Future<Map<String, dynamic>> surplusHealth() {
    return _getObject('/surplus/health');
  }

  Future<Map<String, dynamic>> wasteHealth() {
    return _getObject('/waste/health');
  }

  Future<Map<String, dynamic>> forecast(Map<String, dynamic> request) {
    return _postAuthenticatedObject('/forecast', request);
  }

  Future<Map<String, dynamic>> surplus(Map<String, dynamic> request) {
    return _postAuthenticatedObject('/surplus', request);
  }

  /// Calls POST /surplus/scenarios.
  ///
  /// This endpoint returns a JSON array, unlike the other Phase 2 endpoints.
  Future<List<Map<String, dynamic>>> surplusScenarios(
    Map<String, dynamic> request,
  ) {
    return _postAuthenticatedList('/surplus/scenarios', request);
  }

  Future<Map<String, dynamic>> waste(Map<String, dynamic> request) {
    return _postAuthenticatedObject('/waste', request);
  }

  Future<Map<String, dynamic>> wasteTrend(Map<String, dynamic> request) {
    return _postAuthenticatedObject('/waste/trend', request);
  }

  Future<String> _getIdToken({bool forceRefresh = false}) async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const FoodSenseApiException(
        statusCode: 401,
        message: 'No authenticated Firebase user is signed in.',
      );
    }

    final String? token = await user.getIdToken(forceRefresh);

    if (token == null || token.isEmpty) {
      throw const FoodSenseApiException(
        statusCode: 401,
        message: 'Firebase ID token could not be obtained.',
      );
    }

    return token;
  }

  Future<Map<String, dynamic>> _getObject(String path) async {
    final dynamic decoded = await _getJson(path);
    return _asObject(decoded);
  }

  Future<Map<String, dynamic>> _postAuthenticatedObject(
    String path,
    Map<String, dynamic> body,
  ) async {
    final dynamic decoded = await _postAuthenticatedJson(path, body);

    return _asObject(decoded);
  }

  Future<List<Map<String, dynamic>>> _postAuthenticatedList(
    String path,
    Map<String, dynamic> body,
  ) async {
    final dynamic decoded = await _postAuthenticatedJson(path, body);

    if (decoded is! List) {
      throw FoodSenseApiException(
        statusCode: 200,
        message: 'Backend returned an unexpected list response format.',
        details: decoded,
      );
    }

    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];

    for (final dynamic item in decoded) {
      if (item is Map<String, dynamic>) {
        result.add(item);
      } else if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      } else {
        throw FoodSenseApiException(
          statusCode: 200,
          message: 'Backend returned an invalid item in the list response.',
          details: item,
        );
      }
    }

    return result;
  }

  Future<dynamic> _getJson(String path) async {
    final http.Response response = await _httpClient
        .get(
          _buildUri(path),
          headers: const <String, String>{'Accept': 'application/json'},
        )
        .timeout(timeout);

    return _decodeResponse(response);
  }

  Future<dynamic> _postAuthenticatedJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    String token = await _getIdToken();

    http.Response response = await _sendPost(
      path: path,
      body: body,
      token: token,
    );

    if (response.statusCode == 401) {
      token = await _getIdToken(forceRefresh: true);

      response = await _sendPost(path: path, body: body, token: token);
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
        .timeout(timeout);
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic decoded;

    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = response.body;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw FoodSenseApiException(
      statusCode: response.statusCode,
      message: _extractErrorMessage(decoded, response.statusCode),
      details: decoded,
    );
  }

  Map<String, dynamic> _asObject(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    throw FoodSenseApiException(
      statusCode: 200,
      message: 'Backend returned an unexpected object response format.',
      details: decoded,
    );
  }

  String _extractErrorMessage(dynamic decoded, int statusCode) {
    if (decoded is Map<String, dynamic>) {
      final dynamic detail = decoded['detail'];

      if (detail is String && detail.isNotEmpty) {
        return detail;
      }

      if (detail is List && detail.isNotEmpty) {
        return detail
            .map((dynamic item) {
              if (item is Map<String, dynamic>) {
                final dynamic message = item['msg'];
                final dynamic location = item['loc'];

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
    final String normalizedPath = path.startsWith('/') ? path : '/$path';

    return Uri.parse('$baseUrl$normalizedPath');
  }

  static String _normalizeBaseUrl(String value) {
    final String trimmed = value.trim();

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

  void dispose() {
    _httpClient.close();
  }
}
