import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'delivery_route.dart';

class DeliveryRoutingException implements Exception {
  const DeliveryRoutingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DeliveryRoutingApiService {
  DeliveryRoutingApiService({
    required String baseUrl,
    http.Client? httpClient,
    FirebaseAuth? firebaseAuth,
  })  : baseUrl = _normalizeBaseUrl(baseUrl),
        _httpClient = httpClient ?? http.Client(),
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final String baseUrl;
  final http.Client _httpClient;
  final FirebaseAuth _firebaseAuth;

  Future<DeliveryRouteResult> computeRoute({
    required String organizationId,
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const DeliveryRoutingException(
        'Please sign in again before calculating a route.',
      );
    }

    String? token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw const DeliveryRoutingException(
        'Firebase authentication token is unavailable.',
      );
    }

    Future<http.Response> send(String accessToken) {
      return _httpClient.post(
        Uri.parse('$baseUrl/delivery-routing/compute'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(
          <String, Object?>{
            'organizationId': organizationId,
            'origin': <String, Object?>{
              'latitude': originLatitude,
              'longitude': originLongitude,
            },
            'destination': <String, Object?>{
              'latitude': destinationLatitude,
              'longitude': destinationLongitude,
            },
          },
        ),
      );
    }

    http.Response response = await send(token);

    if (response.statusCode == 401) {
      token = await user.getIdToken(true);

      if (token != null && token.isNotEmpty) {
        response = await send(token);
      }
    }

    dynamic decoded;

    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Unable to calculate the delivery route.';

      if (decoded is Map && decoded['detail'] is String) {
        message = decoded['detail'] as String;
      }

      throw DeliveryRoutingException(message);
    }

    if (decoded is! Map) {
      throw const DeliveryRoutingException(
        'Backend returned an invalid routing response.',
      );
    }

    return DeliveryRouteResult.fromMap(
      Map<String, dynamic>.from(decoded),
    );
  }

  void dispose() {
    _httpClient.close();
  }

  static String _normalizeBaseUrl(String value) {
    final String trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError('Delivery routing API base URL is empty.');
    }

    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
