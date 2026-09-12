import 'dart:async';

import 'package:http/http.dart' as http;

import '../auth/token_storage.dart';
import '../constants/api_constants.dart';

typedef UnauthorizedHandler = FutureOr<void> Function();

/// Shared transport that attaches the stored bearer token to authenticated calls.
class ApiClient {
  ApiClient({
    this.baseUrl = ApiConstants.baseUrl,
    http.Client? httpClient,
    TokenStorage? tokenStorage,
  }) : httpClient = httpClient ?? http.Client(),
       tokenStorage = tokenStorage ?? const SecureTokenStorage();

  final String baseUrl;
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

  Future<http.Response> get(Uri uri, {bool authenticated = true}) async =>
      _check(
        await httpClient.get(
          uri,
          headers: await _headers(authenticated: authenticated),
        ),
        authenticated,
      );

  Future<http.Response> post(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) async => _check(
    await httpClient.post(
      uri,
      headers: await _headers(authenticated: authenticated, json: true),
      body: body,
    ),
    authenticated,
  );

  Future<http.Response> put(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) async => _check(
    await httpClient.put(
      uri,
      headers: await _headers(authenticated: authenticated, json: true),
      body: body,
    ),
    authenticated,
  );

  Future<http.Response> patch(
    Uri uri, {
    Object? body,
    bool authenticated = true,
  }) async => _check(
    await httpClient.patch(
      uri,
      headers: await _headers(authenticated: authenticated, json: true),
      body: body,
    ),
    authenticated,
  );

  Future<http.Response> delete(Uri uri, {bool authenticated = true}) async =>
      _check(
        await httpClient.delete(
          uri,
          headers: await _headers(authenticated: authenticated, json: true),
        ),
        authenticated,
      );

  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    bool authenticated = true,
  }) async {
    request.headers.addAll(await _headers(authenticated: authenticated));
    final response = await httpClient.send(request);
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

  Future<void> _handleUnauthorized() async {
    await tokenStorage.deleteToken();
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
