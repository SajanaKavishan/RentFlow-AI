import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/rental_application.dart';

class RentalApplicationApiService {
  const RentalApplicationApiService(this.apiClient);

  final ApiClient apiClient;

  Future<RentalApplication> createApplication({
    required String propertyId,
    required DateTime moveInDate,
    required double monthlyIncome,
    required String occupation,
    required int numberOfOccupants,
    String? tenantNote,
  }) async {
    final uri = apiClient.buildUri(ApiConstants.rentalApplicationsPath);
    final response = await _send(
      () => apiClient.post(
        uri,
        body: _applicationBody(
          propertyId: propertyId,
          moveInDate: moveInDate,
          monthlyIncome: monthlyIncome,
          occupation: occupation,
          numberOfOccupants: numberOfOccupants,
          tenantNote: tenantNote,
        ),
      ),
    );
    return _parseApplication(response.body);
  }

  Future<RentalApplication> getApplicationById(String id) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.rentalApplicationsPath}/$id',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseApplication(response.body);
  }

  Future<List<RentalApplication>> getMyApplications() async {
    final uri = apiClient.buildUri(ApiConstants.rentalApplicationsPath);
    final response = await _send(() => apiClient.get(uri));
    return _parseApplicationList(response.body);
  }

  Future<RentalApplication> updateApplication({
    required String id,
    required DateTime moveInDate,
    required double monthlyIncome,
    required String occupation,
    required int numberOfOccupants,
    String? tenantNote,
  }) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.rentalApplicationsPath}/$id',
    );
    final response = await _send(
      () => apiClient.put(
        uri,
        body: _applicationBody(
          moveInDate: moveInDate,
          monthlyIncome: monthlyIncome,
          occupation: occupation,
          numberOfOccupants: numberOfOccupants,
          tenantNote: tenantNote,
        ),
      ),
    );
    return _parseApplication(response.body);
  }

  Future<RentalApplication?> submitApplication({required String id}) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.rentalApplicationsPath}/$id/submit',
    );
    final response = await _send(() => apiClient.patch(uri));
    if (response.body.trim().isEmpty) return null;
    return _parseApplication(response.body);
  }

  Future<RentalApplication> withdrawApplication({required String id}) {
    return _patchAction(id: id, action: 'withdraw');
  }

  Future<RentalApplication> _patchAction({
    required String id,
    required String action,
  }) async {
    final uri = apiClient.buildUri(
      '${ApiConstants.rentalApplicationsPath}/$id/$action',
    );
    final response = await _send(() => apiClient.patch(uri));
    return _parseApplication(response.body);
  }

  String _applicationBody({
    String? propertyId,
    required DateTime moveInDate,
    required double monthlyIncome,
    required String occupation,
    required int numberOfOccupants,
    String? tenantNote,
  }) {
    return jsonEncode({
      'propertyId': ?propertyId,
      'moveInDate': _formatDateOnly(moveInDate),
      'monthlyIncome': monthlyIncome,
      'occupation': occupation,
      'numberOfOccupants': numberOfOccupants,
      'tenantNote': tenantNote,
    });
  }

  String _formatDateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const RentalApplicationApiException(
        'Unable to connect to the rental application service.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RentalApplicationApiException(
        _safeErrorMessage(response) ??
            'The rental application request failed. Please try again.',
        statusCode: response.statusCode,
      );
    }

    return response;
  }

  String? _safeErrorMessage(http.Response response) {
    if (response.statusCode == 403) {
      return 'You do not have permission to access this resource.';
    }
    if (response.statusCode == 404) {
      return 'The requested resource is unavailable.';
    }
    if (response.statusCode >= 500) return null;
    return _readErrorMessage(response.body);
  }

  RentalApplication _parseApplication(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return RentalApplication.fromJson(decoded);
    } on FormatException {
      throw const RentalApplicationApiException(
        'The rental application service returned an invalid response.',
      );
    }
  }

  List<RentalApplication> _parseApplicationList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) throw const FormatException();
            return RentalApplication.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const RentalApplicationApiException(
        'The rental application service returned an invalid response.',
      );
    }
  }

  String? _readErrorMessage(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      for (final key in ['detail', 'title', 'message']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class RentalApplicationApiException implements Exception {
  const RentalApplicationApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
