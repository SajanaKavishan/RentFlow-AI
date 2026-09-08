import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/application_document.dart';

class ApplicationDocumentApiService {
  const ApplicationDocumentApiService(this.apiClient);

  final ApiClient apiClient;

  Future<List<ApplicationDocument>> getDocumentsForApplication({
    required String applicationId,
    required String tenantId,
  }) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.rentalApplicationsPath}/$applicationId/documents',
      queryParameters: {'tenantId': tenantId},
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseDocumentList(response.body);
  }

  Future<ApplicationDocument> uploadDocument({
    required String applicationId,
    required String tenantId,
    required ApplicationDocumentType documentType,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.rentalApplicationsPath}/$applicationId/documents',
      queryParameters: {'tenantId': tenantId},
    );
    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..fields['documentType'] = documentType.value.toString()
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );

    final response = await _sendStreamed(() => apiClient.send(request));
    return _parseDocument(response.body);
  }

  Future<void> deleteDocument({
    required String documentId,
    required String tenantId,
  }) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.applicationDocumentsPath}/$documentId',
      queryParameters: {'tenantId': tenantId},
    );
    await _send(() => apiClient.delete(uri));
  }

  /// Requests the private backend download endpoint and returns its temporary
  /// redirect URL. The caller must use it immediately and must not persist it.
  Future<Uri> requestDownloadUrl({
    required String documentId,
    required String tenantId,
  }) async {
    final endpoint = apiClient.buildUri(
      '${ApiConstants.applicationDocumentsPath}/$documentId/download',
      queryParameters: {'tenantId': tenantId},
    );
    final request = http.Request('GET', endpoint)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';

    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await apiClient.send(request);
    } on http.ClientException {
      throw const ApplicationDocumentApiException(
        'Unable to connect to the document service.',
      );
    }

    if (streamedResponse.statusCode >= 300 &&
        streamedResponse.statusCode < 400) {
      final location = streamedResponse.headers['location'];
      await streamedResponse.stream.drain<void>();
      if (location != null && location.trim().isNotEmpty) {
        return endpoint.resolve(location);
      }
      throw const ApplicationDocumentApiException(
        'The document download link was invalid.',
      );
    }

    final response = await http.Response.fromStream(streamedResponse);
    _throwForError(response);
    throw const ApplicationDocumentApiException(
      'The document download link was invalid.',
    );
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const ApplicationDocumentApiException(
        'Unable to connect to the document service.',
      );
    }
    _throwForError(response);
    return response;
  }

  Future<http.Response> _sendStreamed(
    Future<http.StreamedResponse> Function() request,
  ) async {
    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await request();
    } on http.ClientException {
      throw const ApplicationDocumentApiException(
        'Unable to connect to the document service.',
      );
    }
    final response = await http.Response.fromStream(streamedResponse);
    _throwForError(response);
    return response;
  }

  void _throwForError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw ApplicationDocumentApiException(
      _readErrorMessage(response.body) ??
          'The document request failed. Please try again.',
      statusCode: response.statusCode,
    );
  }

  ApplicationDocument _parseDocument(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return ApplicationDocument.fromJson(decoded);
    } on FormatException {
      throw const ApplicationDocumentApiException(
        'The document service returned an invalid response.',
      );
    }
  }

  List<ApplicationDocument> _parseDocumentList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) throw const FormatException();
            return ApplicationDocument.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const ApplicationDocumentApiException(
        'The document service returned an invalid response.',
      );
    }
  }

  String? _readErrorMessage(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail.trim();

      final errors = decoded['errors'];
      if (errors is Map<String, dynamic>) {
        for (final value in errors.values) {
          if (value is List<dynamic>) {
            for (final message in value) {
              if (message is String && message.trim().isNotEmpty) {
                return message.trim();
              }
            }
          }
        }
      }

      for (final key in ['title', 'message']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class ApplicationDocumentApiException implements Exception {
  const ApplicationDocumentApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
