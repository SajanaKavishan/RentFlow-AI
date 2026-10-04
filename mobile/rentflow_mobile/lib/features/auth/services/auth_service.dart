import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/current_user.dart';
import '../models/profile_image_file.dart';
import '../models/password_change_result.dart';

class AuthResult {
  const AuthResult({required this.accessToken, required this.user});
  final String accessToken;
  final CurrentUser user;
}

class AuthService {
  const AuthService(this.apiClient);
  final ApiClient apiClient;

  Future<PasswordChangeResult> changePassword({
    required String currentPassword,
    required String newPassword,
    required String newPasswordConfirmation,
  }) async {
    try {
      final response = await apiClient.put(
        apiClient.buildUri('${ApiConstants.authPath}/change-password'),
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
          'newPasswordConfirmation': newPasswordConfirmation,
        }),
      );
      _throwForError(
        response,
        fallback: 'Unable to change your password. Please try again.',
        sensitiveValues: [
          currentPassword,
          newPassword,
          newPasswordConfirmation,
        ],
      );
      try {
        final json = _object(response.body);
        final token = json['accessToken'];
        final message = json['message'];
        final expiry = json['expiresAt'];
        final expiresAt = expiry is String ? DateTime.tryParse(expiry) : null;
        if (token is! String ||
            token.trim() != token ||
            !RegExp(r'^[A-Za-z0-9\-._~+/]+=*$').hasMatch(token) ||
            message is! String ||
            message.trim().isEmpty ||
            expiresAt == null) {
          throw const FormatException();
        }
        return PasswordChangeResult(
          message: message,
          accessToken: token,
          expiresAt: expiresAt,
        );
      } on FormatException {
        // A 2xx may already have invalidated the old JWT. Never keep using it.
        throw const PasswordChangeSessionException(
          'Your password may have changed. Please sign in again.',
        );
      }
    } on http.ClientException {
      throw const AuthException(
        'Unable to connect. Please try again.',
        isConnectionFailure: true,
      );
    }
  }

  Future<AuthResult> login({required String email, required String password}) =>
      _authenticate('${ApiConstants.authPath}/login', {
        'email': email,
        'password': password,
      });

  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required UserRole role,
  }) => _authenticate('${ApiConstants.authPath}/register', {
    'fullName': fullName,
    'email': email,
    'phoneNumber': phoneNumber,
    'password': password,
    'role': role.value,
  });

  Future<AuthResult> _authenticate(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await apiClient.post(
        apiClient.buildUri(path),
        body: jsonEncode(body),
        authenticated: false,
      );
      if (kDebugMode) {
        debugPrint('[AuthService] $path status=${response.statusCode}');
      }
      _throwForError(
        response,
        fallback: 'Authentication could not be completed.',
      );
      final json = _object(response.body);
      final token = json['accessToken'];
      final userJson = json['user'];
      if (token is! String ||
          token.isEmpty ||
          userJson is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return AuthResult(
        accessToken: token,
        user: CurrentUser.fromJson(userJson),
      );
    } on http.ClientException catch (error) {
      if (kDebugMode) {
        debugPrint('[AuthService] $path network error: $error');
      }
      throw const AuthException(
        'Unable to connect. Please try again.',
        isConnectionFailure: true,
      );
    } on FormatException {
      throw const AuthException(
        'The authentication service returned an invalid response.',
      );
    }
  }

  Future<CurrentUser> getCurrentUser() async {
    try {
      final response = await apiClient.get(
        apiClient.buildUri('${ApiConstants.authPath}/me'),
      );
      _throwForError(response, fallback: 'Your session is no longer valid.');
      return CurrentUser.fromJson(_object(response.body));
    } on http.ClientException catch (error) {
      if (kDebugMode) {
        debugPrint('[AuthService] /api/auth/me network error: $error');
      }
      throw const AuthException(
        'Unable to connect. Please try again.',
        isConnectionFailure: true,
      );
    } on FormatException {
      throw const AuthException(
        'The authentication service returned an invalid response.',
      );
    }
  }

  Future<CurrentUser> updateProfile({
    required String fullName,
    required String phoneNumber,
  }) => _saveProfile({
    'fullName': fullName.trim(),
    'phoneNumber': phoneNumber.trim(),
    // Omission preserves the server's published contact snapshot.
  }, 'Your profile could not be updated.');

  Future<Uint8List> getProfileImage() async {
    try {
      final response = await apiClient.get(
        apiClient.buildUri('${ApiConstants.authPath}/profile-image'),
      );
      _throwForError(
        response,
        fallback: 'Your profile photo could not be loaded.',
      );
      final bytes = response.bodyBytes;
      if (bytes.isEmpty || bytes.length > ProfileImageFile.maximumBytes) {
        throw const FormatException();
      }
      return bytes;
    } on http.ClientException {
      throw const AuthException(
        'Unable to load your photo.',
        isConnectionFailure: true,
      );
    } on FormatException {
      throw const AuthException('The profile photo response was invalid.');
    }
  }

  Future<CurrentUser> uploadProfileImage(ProfileImageFile image) async {
    final error = image.validate();
    if (error != null) throw AuthException(error);
    try {
      final request =
          http.MultipartRequest(
              'POST',
              apiClient.buildUri('${ApiConstants.authPath}/profile-image'),
            )
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                image.bytes,
                filename: image.name,
                contentType: MediaType.parse(image.contentType!),
              ),
            );
      final response = await http.Response.fromStream(
        await apiClient.send(request),
      );
      _throwForError(
        response,
        fallback: 'Your profile photo could not be uploaded.',
      );
      return CurrentUser.fromJson(_object(response.body));
    } on http.ClientException {
      throw const AuthException(
        'Unable to upload your photo. Please try again.',
        isConnectionFailure: true,
      );
    } on FormatException {
      throw const AuthException(
        'The profile service returned an invalid response.',
      );
    }
  }

  Future<CurrentUser> updatePublicContact(
    CurrentUser user,
    String phone,
    bool enabled,
  ) => _saveProfile({
    'fullName': user.fullName,
    'phoneNumber': user.phoneNumber,
    'publicContactPhone': phone.trim(),
    'publicContactEnabled': enabled,
  }, 'Your public contact could not be updated.');

  Future<CurrentUser> _saveProfile(
    Map<String, dynamic> details,
    String fallback,
  ) async {
    try {
      final response = await apiClient.put(
        apiClient.buildUri('${ApiConstants.authPath}/profile'),
        body: jsonEncode(details),
      );
      _throwForError(response, fallback: fallback);
      return CurrentUser.fromJson(_object(response.body));
    } on http.ClientException {
      throw const AuthException(
        'Unable to connect. Please try again.',
        isConnectionFailure: true,
      );
    } on FormatException {
      throw const AuthException(
        'The profile service returned an invalid response.',
      );
    }
  }

  Map<String, dynamic> _object(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    return decoded;
  }

  void _throwForError(
    http.Response response, {
    required String fallback,
    List<String>? sensitiveValues,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String? safeMessage;
    try {
      final body = _object(response.body);
      for (final key in ['detail', 'title', 'message']) {
        final value = body[key];
        if (value is String && value.trim().isNotEmpty) {
          safeMessage = value.trim();
          break;
        }
      }
      final errors = body['errors'];
      if (safeMessage == null && errors is Map<String, dynamic>) {
        for (final value in errors.values) {
          if (value is List && value.isNotEmpty && value.first is String) {
            safeMessage = (value.first as String).trim();
            break;
          }
        }
      }
    } on FormatException {
      // Never expose non-JSON response bodies or raw server traces.
    }
    if (sensitiveValues != null && safeMessage != null) {
      final leaksSecret =
          sensitiveValues.any(
            (value) => value.isNotEmpty && safeMessage!.contains(value),
          ) ||
          RegExp(
            r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
          ).hasMatch(safeMessage) ||
          safeMessage.toLowerCase().contains('bearer ');
      if (leaksSecret ||
          safeMessage.length > 512 ||
          response.statusCode >= 500) {
        safeMessage = null;
      }
    }
    throw AuthException(
      safeMessage ?? fallback,
      statusCode: response.statusCode,
    );
  }
}

class AuthException implements Exception {
  const AuthException(
    this.message, {
    this.statusCode,
    this.isConnectionFailure = false,
  });
  final String message;
  final int? statusCode;
  final bool isConnectionFailure;
  @override
  String toString() => message;
}

class PasswordChangeSessionException extends AuthException {
  const PasswordChangeSessionException(super.message);
}
