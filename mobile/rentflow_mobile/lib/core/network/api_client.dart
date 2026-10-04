import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/token_storage.dart';
import '../constants/api_constants.dart';

typedef UnauthorizedHandler = FutureOr<void> Function();

/// Shared transport that attaches the stored bearer token to authenticated calls.
class ApiClient {
  ApiClient({
    this.baseUrl = ApiConstants.baseUrl,
    this.requestTimeout = const Duration(seconds: 20),
    http.Client? httpClient,
    TokenStorage? tokenStorage,
  }) : httpClient = httpClient ?? http.Client(),
       tokenStorage = tokenStorage ?? const SecureTokenStorage();

  final String baseUrl;
  final Duration requestTimeout;
  final http.Client httpClient;
  final TokenStorage tokenStorage;
  UnauthorizedHandler? _unauthorizedHandler;
  bool _handlingUnauthorized = false;
  bool _authenticationSuspended = false;
  Completer<void>? _tokenReplacement;

  // Prevent stale storage reads while a rotated session is being installed or
  // after local persistence fails. The token itself remains solely in storage.
  void beginTokenReplacement() => _tokenReplacement = Completer<void>();
  void _finishTokenReplacement() {
    _tokenReplacement?.complete();
    _tokenReplacement = null;
  }

  void suspendAuthentication() {
    _authenticationSuspended = true;
    _finishTokenReplacement();
  }

  void resumeAuthentication() {
    _authenticationSuspended = false;
    _finishTokenReplacement();
  }

  void setUnauthorizedHandler(UnauthorizedHandler handler) {
    _unauthorizedHandler = handler;
  }

  Uri buildUri(String path, {Map<String, String>? queryParameters}) {
    final baseUri = Uri.parse(baseUrl);
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final resourcePath = path.startsWith('/') ? path : '/$path';
    return baseUri.replace(
      path: '$basePath$resourcePath',
      queryParameters: queryParameters,
    );
  }

  Future<Map<String, String>> _headers({
    required bool authenticated,
    bool json = false,
  }) async {
    if (authenticated) await _tokenReplacement?.future;
    final token = authenticated && !_authenticationSuspended
        ? await tokenStorage.readToken()
        : null;
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty && !_authenticationSuspended)
        'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> get(Uri uri, {bool authenticated = true}) async {
    final headers = await _withTimeout(
      () => _headers(authenticated: authenticated),
      uri,
    );
    if (kDebugMode) {
      debugPrint(
        '[ApiClient] GET $uri '
        'authorizationBearerPresent=${headers['Authorization']?.startsWith('Bearer ') ?? false}',
      );
    }
    final response = await _withTimeout(
      () => httpClient.get(uri, headers: headers),
      uri,
    );
    if (kDebugMode) {
      debugPrint('[ApiClient] GET $uri status=${response.statusCode}');
    }
    return _check(response, authenticated, headers['Authorization']);
  }

  Future<http.Response> post(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) => _jsonRequest('POST', uri, body: body, authenticated: authenticated);

  Future<http.Response> put(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) => _jsonRequest('PUT', uri, body: body, authenticated: authenticated);

  Future<http.Response> patch(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) => _jsonRequest('PATCH', uri, body: body, authenticated: authenticated);

  Future<http.Response> delete(Uri uri, {bool authenticated = true}) =>
      _jsonRequest('DELETE', uri, authenticated: authenticated);

  Future<http.Response> _jsonRequest(
    String method,
    Uri uri, {
    Object? body,
    required bool authenticated,
  }) async {
    final headers = await _withTimeout(
      () => _headers(authenticated: authenticated, json: true),
      uri,
    );
    final response = await _withTimeout(() {
      switch (method) {
        case 'POST':
          return httpClient.post(uri, headers: headers, body: body);
        case 'PUT':
          return httpClient.put(uri, headers: headers, body: body);
        case 'PATCH':
          return httpClient.patch(uri, headers: headers, body: body);
        default:
          return httpClient.delete(uri, headers: headers);
      }
    }, uri);
    return _check(response, authenticated, headers['Authorization']);
  }

  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    bool authenticated = true,
  }) async {
    request.headers.addAll(
      await _withTimeout(
        () => _headers(authenticated: authenticated),
        request.url,
      ),
    );
    final response = await _withTimeout(
      () => httpClient.send(request),
      request.url,
    );
    if (response.statusCode == 401 && authenticated) {
      await _handleUnauthorized(request.headers['Authorization']);
    }
    return response;
  }

  Future<http.Response> _check(
    FutureOr<http.Response> responseValue,
    bool authenticated,
    String? authorization,
  ) async {
    final response = await responseValue;
    if (response.statusCode == 401 && authenticated) {
      await _handleUnauthorized(authorization);
    }
    return response;
  }

  Future<T> _withTimeout<T>(Future<T> Function() request, Uri uri) async {
    try {
      return await request().timeout(requestTimeout);
    } on TimeoutException {
      throw http.ClientException('The request timed out.', uri);
    }
  }

  Future<void> _handleUnauthorized(String? authorization) async {
    // An old request can return 401 after TokenVersion changes. Its rejection
    // must not delete the replacement token or sign out the initiating session.
    if (_tokenReplacement != null) {
      try {
        await _tokenReplacement!.future.timeout(requestTimeout);
      } on TimeoutException {
        return;
      }
    }
    if (_authenticationSuspended) return;
    try {
      final currentToken = await tokenStorage.readToken().timeout(
        requestTimeout,
      );
      final currentAuthorization = currentToken == null || currentToken.isEmpty
          ? null
          : 'Bearer $currentToken';
      if (_tokenReplacement != null) return _handleUnauthorized(authorization);
      if (authorization != currentAuthorization) return;
    } catch (_) {
      // Storage failure must not leave an already rejected session signed in.
    }
    try {
      await tokenStorage.deleteToken().timeout(requestTimeout);
    } catch (_) {
      // Still run the session handler so the app can leave authenticated UI.
    }
    if (_handlingUnauthorized || _unauthorizedHandler == null) return;
    _handlingUnauthorized = true;
    try {
      await _unauthorizedHandler!();
    } finally {
      _handlingUnauthorized = false;
    }
  }

  void close() => httpClient.close();
}
