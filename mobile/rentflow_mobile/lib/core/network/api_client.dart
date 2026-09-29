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
    final token = authenticated ? await tokenStorage.readToken() : null;
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
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
    return _check(response, authenticated);
  }

  Future<http.Response> post(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) async => _check(
    await _withTimeout(
      () async => httpClient.post(
        uri,
        headers: await _headers(authenticated: authenticated, json: true),
        body: body,
      ),
      uri,
    ),
    authenticated,
  );

  Future<http.Response> put(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) async => _check(
    await _withTimeout(
      () async => httpClient.put(
        uri,
        headers: await _headers(authenticated: authenticated, json: true),
        body: body,
      ),
      uri,
    ),
    authenticated,
  );

  Future<http.Response> patch(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) async => _check(
    await _withTimeout(
      () async => httpClient.patch(
        uri,
        headers: await _headers(authenticated: authenticated, json: true),
        body: body,
      ),
      uri,
    ),
    authenticated,
  );

  Future<http.Response> delete(Uri uri, {bool authenticated = true}) async =>
      _check(
        await _withTimeout(
          () async => httpClient.delete(
            uri,
            headers: await _headers(authenticated: authenticated, json: true),
          ),
          uri,
        ),
        authenticated,
      );

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
      await _handleUnauthorized();
    }
    return response;
  }

  Future<http.Response> _check(
    FutureOr<http.Response> responseValue,
    bool authenticated,
  ) async {
    final response = await responseValue;
    if (response.statusCode == 401 && authenticated) {
      await _handleUnauthorized();
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

  Future<void> _handleUnauthorized() async {
    try {
      await tokenStorage.deleteToken().timeout(requestTimeout);
    } on TimeoutException {
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
