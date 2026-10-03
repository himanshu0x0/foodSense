import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'place_search.dart';

class PlacesSearchException implements Exception {
  const PlacesSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlacesSearchApiService {
  PlacesSearchApiService({
    required String baseUrl,
    http.Client? httpClient,
    FirebaseAuth? firebaseAuth,
  })  : baseUrl = _normalizeBaseUrl(baseUrl),
        _httpClient = httpClient ?? http.Client(),
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final String baseUrl;
  final http.Client _httpClient;
  final FirebaseAuth _firebaseAuth;

  Future<List<PlaceSearchResult>> searchPlaces({
    required String organizationId,
    required String query,
    double? latitude,
    double? longitude,
  }) async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const PlacesSearchException(
        'Please sign in again before searching for a location.',
      );
    }

    final String trimmedQuery = query.trim();
    if (trimmedQuery.length < 2) {
      return <PlaceSearchResult>[];
    }

    String? token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const PlacesSearchException(
        'Firebase authentication token is unavailable.',
      );
    }

    Future<http.Response> send(String accessToken) {
      return _httpClient.post(
        Uri.parse('$baseUrl/places/search'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(<String, Object?>{
          'organizationId': organizationId,
          'query': trimmedQuery,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
        }),
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
      String message = 'Unable to search for this location.';

      if (decoded is Map && decoded['detail'] is String) {
        message = decoded['detail'] as String;
      }

      throw PlacesSearchException(message);
    }

    if (decoded is! Map) {
      throw const PlacesSearchException(
        'Backend returned an invalid place-search response.',
      );
    }

    final dynamic rawResults = decoded['results'];
    if (rawResults is! List) {
      return <PlaceSearchResult>[];
    }

    return rawResults
        .whereType<Map>()
        .map(
          (Map item) => PlaceSearchResult(
            placeId: item['placeId']?.toString() ?? '',
            name: item['name']?.toString() ?? 'Place',
            address: item['address']?.toString() ?? '',
            latitude: (item['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (item['longitude'] as num?)?.toDouble() ?? 0,
          ),
        )
        .where(
          (PlaceSearchResult item) =>
              item.placeId.isNotEmpty &&
              item.address.isNotEmpty &&
              item.latitude >= -90 &&
              item.latitude <= 90 &&
              item.longitude >= -180 &&
              item.longitude <= 180,
        )
        .toList(growable: false);
  }

  void dispose() => _httpClient.close();

  static String _normalizeBaseUrl(String value) {
    final String trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError('Places search API base URL is empty.');
    }

    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
