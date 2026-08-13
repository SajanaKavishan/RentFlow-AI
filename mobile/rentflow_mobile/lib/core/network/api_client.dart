import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';

/// Shared HTTP client configuration for the application.
class ApiClient {
  ApiClient({this.baseUrl = ApiConstants.baseUrl, http.Client? httpClient})
    : httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client httpClient;

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

  Future<http.Response> get(Uri uri) => httpClient.get(uri);

  Future<http.Response> post(Uri uri, {Object? body}) {
    return httpClient.post(uri, headers: _jsonHeaders, body: body);
  }

  Future<http.Response> patch(Uri uri, {Object? body}) {
    return httpClient.patch(uri, headers: _jsonHeaders, body: body);
  }

  void close() => httpClient.close();

  static const Map<String, String> _jsonHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
}
