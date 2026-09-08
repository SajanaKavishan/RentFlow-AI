import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/current_user.dart';

class AuthResult {
  const AuthResult({required this.accessToken, required this.user});
  final String accessToken;
  final CurrentUser user;
}

class AuthService {
  const AuthService(this.apiClient);
  final ApiClient apiClient;

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
    } on http.ClientException {
      throw const AuthException('Unable to connect. Please try again.');
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
    } on http.ClientException {
      throw const AuthException('Unable to connect. Please try again.');
    } on FormatException {
      throw const AuthException(
        'The authentication service returned an invalid response.',
      );
    }
  }

  Map<String, dynamic> _object(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    return decoded;
  }

  void _throwForError(http.Response response, {required String fallback}) {
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
    throw AuthException(
      safeMessage ?? fallback,
      statusCode: response.statusCode,
    );
  }
}

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
