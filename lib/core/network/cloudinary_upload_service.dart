import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Exception raised when a Cloudinary upload cannot be completed.
class CloudinaryUploadException implements Exception {
  const CloudinaryUploadException({
    required this.message,
    this.statusCode,
    this.details,
  });

  final String message;
  final int? statusCode;
  final Object? details;

  @override
  String toString() {
    final String suffix = statusCode == null ? '' : ' (HTTP $statusCode)';
    return 'CloudinaryUploadException: $message$suffix';
  }
}

/// Result returned after a successful Cloudinary upload.
class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
    required this.resourceType,
    this.assetId,
    this.version,
    this.format,
    this.bytes,
    this.width,
    this.height,
  });

  final String secureUrl;
  final String publicId;
  final String resourceType;
  final String? assetId;
  final int? version;
  final String? format;
  final int? bytes;
  final int? width;
  final int? height;

  factory CloudinaryUploadResult.fromJson(Map<String, dynamic> json) {
    final String secureUrl = json['secure_url'] as String? ?? '';
    final String publicId = json['public_id'] as String? ?? '';
    final String resourceType = json['resource_type'] as String? ?? 'image';

    if (secureUrl.isEmpty || publicId.isEmpty) {
      throw const CloudinaryUploadException(
        message: 'Cloudinary returned an incomplete upload response.',
      );
    }

    return CloudinaryUploadResult(
      secureUrl: secureUrl,
      publicId: publicId,
      resourceType: resourceType,
      assetId: json['asset_id'] as String?,
      version: _intValue(json['version']),
      format: json['format'] as String?,
      bytes: _intValue(json['bytes']),
      width: _intValue(json['width']),
      height: _intValue(json['height']),
    );
  }

  static int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }
}

/// Client-side Cloudinary image uploader for FoodSense.
///
/// Upload flow:
/// 1. Get a Firebase ID token from the signed-in user.
/// 2. Ask FastAPI for a short-lived signed Cloudinary upload payload.
/// 3. Upload the selected file directly to Cloudinary.
/// 4. Return the secure URL and public ID so the caller can persist them
///    in Firestore.
//
/// The Cloudinary API secret is never stored or used in Flutter.
class CloudinaryUploadService {
  CloudinaryUploadService({
    required String backendBaseUrl,
    http.Client? httpClient,
    FirebaseAuth? firebaseAuth,
    Duration timeout = const Duration(seconds: 60),
  }) : backendBaseUrl = _normalizeBaseUrl(backendBaseUrl),
       _httpClient = httpClient ?? http.Client(),
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _timeout = timeout;

  final String backendBaseUrl;
  final http.Client _httpClient;
  final FirebaseAuth _firebaseAuth;
  final Duration _timeout;

  /// Uploads a food-record image.
  Future<CloudinaryUploadResult> uploadFoodRecordImage({
    required File file,
    required String organizationId,
    required String recordId,
  }) {
    return uploadImage(
      file: file,
      organizationId: organizationId,
      mediaType: 'food_records',
      entityId: recordId,
    );
  }

  /// Uploads an inventory image.
  Future<CloudinaryUploadResult> uploadInventoryImage({
    required File file,
    required String organizationId,
    required String itemId,
  }) {
    return uploadImage(
      file: file,
      organizationId: organizationId,
      mediaType: 'inventory',
      entityId: itemId,
    );
  }

  /// Uploads a surplus evidence image.
  Future<CloudinaryUploadResult> uploadSurplusImage({
    required File file,
    required String organizationId,
    required String surplusId,
  }) {
    return uploadImage(
      file: file,
      organizationId: organizationId,
      mediaType: 'surplus',
      entityId: surplusId,
    );
  }

  /// Deletes a Cloudinary asset through the authenticated FoodSense backend.
  ///
  /// The backend verifies that the public ID is linked to the requested
  /// organization record before performing the deletion with Cloudinary.
  Future<bool> deleteAsset({
    required String organizationId,
    required String mediaType,
    required String entityId,
    required String publicId,
    String resourceType = 'image',
  }) async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const CloudinaryUploadException(
        statusCode: 401,
        message: 'You must be signed in before deleting an image.',
      );
    }

    String token = await _getIdToken();

    http.Response response = await _requestDeleteAsset(
      token: token,
      organizationId: organizationId,
      mediaType: mediaType,
      entityId: entityId,
      publicId: publicId,
      resourceType: resourceType,
    );

    // Retry once with a refreshed Firebase token if the first token expired.
    if (response.statusCode == 401) {
      token = await _getIdToken(forceRefresh: true);

      response = await _requestDeleteAsset(
        token: token,
        organizationId: organizationId,
        mediaType: mediaType,
        entityId: entityId,
        publicId: publicId,
        resourceType: resourceType,
      );
    }

    final Map<String, dynamic> payload = _decodeBackendResponse(response);

    return payload['deleted'] == true;
  }

  Future<http.Response> _requestDeleteAsset({
    required String token,
    required String organizationId,
    required String mediaType,
    required String entityId,
    required String publicId,
    required String resourceType,
  }) async {
    try {
      return await _httpClient
          .post(
            Uri.parse('$backendBaseUrl/cloudinary/delete-asset'),
            headers: <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{
              'organization_id': organizationId.trim(),
              'media_type': mediaType.trim(),
              'entity_id': entityId.trim(),
              'public_id': publicId.trim(),
              'resource_type': resourceType.trim(),
            }),
          )
          .timeout(_timeout);
    } on SocketException catch (error) {
      throw CloudinaryUploadException(
        message: 'Could not reach the FoodSense backend.',
        details: error,
      );
    } on TimeoutException catch (error) {
      throw CloudinaryUploadException(
        message: 'The FoodSense backend request timed out.',
        details: error,
      );
    } catch (error) {
      throw CloudinaryUploadException(
        message: 'Could not request Cloudinary asset deletion.',
        details: error,
      );
    }
  }

  /// Uploads an image using the authenticated FoodSense backend signer.
  Future<CloudinaryUploadResult> uploadImage({
    required File file,
    required String organizationId,
    required String mediaType,
    required String entityId,
  }) async {
    await _validateFile(file);

    final String token = await _getIdToken();

    final Map<String, dynamic> signedPayload = await _requestSignedUpload(
      token: token,
      organizationId: organizationId,
      mediaType: mediaType,
      entityId: entityId,
    );

    try {
      return await _uploadToCloudinary(
        file: file,
        cloudName: _requiredString(
          signedPayload['cloud_name'],
          field: 'cloud_name',
        ),
        apiKey: _requiredString(signedPayload['api_key'], field: 'api_key'),
        timestamp: _requiredInt(signedPayload['timestamp'], field: 'timestamp'),
        signature: _requiredString(
          signedPayload['signature'],
          field: 'signature',
        ),
        assetFolder: _requiredString(
          signedPayload['asset_folder'],
          field: 'asset_folder',
        ),
        publicId: _requiredString(
          signedPayload['public_id'],
          field: 'public_id',
        ),
        resourceType: _requiredString(
          signedPayload['resource_type'],
          field: 'resource_type',
        ),
      );
    } on CloudinaryUploadException {
      rethrow;
    } on SocketException catch (error) {
      throw CloudinaryUploadException(
        message: 'Could not reach Cloudinary. Check your internet connection.',
        details: error,
      );
    } on TimeoutException catch (error) {
      throw CloudinaryUploadException(
        message: 'Cloudinary upload timed out. Please try again.',
        details: error,
      );
    } catch (error) {
      throw CloudinaryUploadException(
        message: 'Cloudinary upload failed.',
        details: error,
      );
    }
  }

  Future<Map<String, dynamic>> _requestSignedUpload({
    required String token,
    required String organizationId,
    required String mediaType,
    required String entityId,
  }) async {
    final List<String> candidateBaseUrls = <String>[
      backendBaseUrl,
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        'http://10.0.2.2:8000',
    ].toSet().toList();

    SocketException? lastSocketError;

    for (final String baseUrl in candidateBaseUrls) {
      try {
        debugPrint(
          'FoodSense Cloudinary: requesting signed upload from '
          '$baseUrl/cloudinary/sign-upload',
        );

        final http.Response response = await _httpClient
            .post(
              Uri.parse('$baseUrl/cloudinary/sign-upload'),
              headers: <String, String>{
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(<String, dynamic>{
                'organization_id': organizationId.trim(),
                'media_type': mediaType.trim(),
                'entity_id': entityId.trim(),
              }),
            )
            .timeout(_timeout);

        return _decodeBackendResponse(response);
      } on SocketException catch (error) {
        lastSocketError = error;
        debugPrint('FoodSense Cloudinary: could not reach $baseUrl: $error');
      } on TimeoutException catch (error) {
        throw CloudinaryUploadException(
          message: 'The FoodSense backend request timed out at $baseUrl.',
          details: error,
        );
      } on CloudinaryUploadException {
        rethrow;
      } catch (error) {
        throw CloudinaryUploadException(
          message:
              'Could not request a Cloudinary upload signature from '
              '$baseUrl.',
          details: error,
        );
      }
    }

    throw CloudinaryUploadException(
      message:
          'Could not reach the FoodSense backend. Tried: '
          '${candidateBaseUrls.join(', ')}',
      details: lastSocketError,
    );
  }

  Future<CloudinaryUploadResult> _uploadToCloudinary({
    required File file,
    required String cloudName,
    required String apiKey,
    required int timestamp,
    required String signature,
    required String assetFolder,
    required String publicId,
    required String resourceType,
  }) async {
    final Uri uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/'
      '$cloudName/$resourceType/upload',
    );

    final http.MultipartRequest request = http.MultipartRequest('POST', uri);

    request.fields.addAll(<String, String>{
      'api_key': apiKey,
      'timestamp': timestamp.toString(),
      'signature': signature,
      'asset_folder': assetFolder,
      'public_id': publicId,
    });

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    http.StreamedResponse streamedResponse;

    try {
      streamedResponse = await request.send().timeout(_timeout);
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    }

    final String responseBody = await streamedResponse.stream.bytesToString();

    Object? decoded;
    if (responseBody.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(responseBody);
      } on FormatException {
        decoded = responseBody;
      }
    }

    if (streamedResponse.statusCode >= 200 &&
        streamedResponse.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        try {
          return CloudinaryUploadResult.fromJson(decoded);
        } on CloudinaryUploadException {
          rethrow;
        }
      }

      throw CloudinaryUploadException(
        statusCode: streamedResponse.statusCode,
        message: 'Cloudinary returned an unexpected response format.',
        details: decoded,
      );
    }

    throw CloudinaryUploadException(
      statusCode: streamedResponse.statusCode,
      message: _extractCloudinaryError(decoded),
      details: decoded,
    );
  }

  Future<String> _getIdToken({bool forceRefresh = false}) async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const CloudinaryUploadException(
        statusCode: 401,
        message: 'You must be signed in before uploading an image.',
      );
    }

    final String? token = await user.getIdToken(forceRefresh);

    if (token == null || token.isEmpty) {
      throw const CloudinaryUploadException(
        statusCode: 401,
        message: 'Firebase authentication token could not be obtained.',
      );
    }

    return token;
  }

  Map<String, dynamic> _decodeBackendResponse(http.Response response) {
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

      throw CloudinaryUploadException(
        statusCode: response.statusCode,
        message: 'FoodSense backend returned an unexpected response.',
        details: decoded,
      );
    }

    throw CloudinaryUploadException(
      statusCode: response.statusCode,
      message: _extractBackendError(decoded, response.statusCode),
      details: decoded,
    );
  }

  String _extractBackendError(Object? decoded, int statusCode) {
    if (decoded is Map<String, dynamic>) {
      final Object? detail = decoded['detail'];

      if (detail is String && detail.isNotEmpty) {
        return detail;
      }

      if (detail is List && detail.isNotEmpty) {
        return detail
            .map((Object? item) {
              if (item is Map<String, dynamic>) {
                return item['msg']?.toString() ?? item.toString();
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
        return 'The Cloudinary upload request is invalid.';
      case 503:
        return 'Cloudinary is not configured on the FoodSense backend.';
      default:
        return 'FoodSense backend returned HTTP $statusCode.';
    }
  }

  String _extractCloudinaryError(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      final Object? error = decoded['error'];

      if (error is Map<String, dynamic>) {
        final String? message = error['message'] as String?;
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }

      if (error is String && error.isNotEmpty) {
        return error;
      }
    }

    return 'Cloudinary rejected the image upload.';
  }

  Future<void> _validateFile(File file) async {
    final bool exists = await file.exists();

    if (!exists) {
      throw const CloudinaryUploadException(
        message: 'The selected image file no longer exists.',
      );
    }

    final int length = await file.length();

    if (length <= 0) {
      throw const CloudinaryUploadException(
        message: 'The selected image file is empty.',
      );
    }
  }

  static String _normalizeBaseUrl(String value) {
    final String trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        value,
        'backendBaseUrl',
        'FoodSense backend URL cannot be empty.',
      );
    }

    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  static String _requiredString(Object? value, {required String field}) {
    final String text = value?.toString().trim() ?? '';

    if (text.isEmpty) {
      throw CloudinaryUploadException(
        message: 'Signed upload response is missing "$field".',
      );
    }

    return text;
  }

  static int _requiredInt(Object? value, {required String field}) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    final int? parsed = int.tryParse(value?.toString() ?? '');

    if (parsed == null) {
      throw CloudinaryUploadException(
        message: 'Signed upload response contains an invalid "$field".',
      );
    }

    return parsed;
  }

  /// Releases the underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }
}

/// Backward-compatible alias for older code using the misspelled type name.
typedef CloudinarUploadService = CloudinaryUploadService;
