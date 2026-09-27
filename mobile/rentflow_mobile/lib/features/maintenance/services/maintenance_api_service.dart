import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../properties/models/property.dart';
import '../models/repair_estimate.dart';
import '../models/maintenance_request.dart';

class MaintenanceApiService {
  const MaintenanceApiService(this.apiClient);

  final ApiClient apiClient;

  Future<List<Property>> getTenantProperties() async {
    final uri = apiClient.buildUri('/api/properties/tenant/mine');
    final response = await _send(() => apiClient.get(uri));
    return _parsePropertyList(response.body);
  }

  Future<List<MaintenanceRequest>> getMyMaintenanceRequests({
    required String tenantId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/tenant/$tenantId',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseList(response.body);
  }

  Future<List<MaintenanceRequest>> getAssignedWork({
    required String technicianId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/technician/$technicianId',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseList(response.body);
  }

  Future<MaintenanceRequest> createMaintenanceRequest({
    required String tenantId,
    required String propertyId,
    required String title,
    required String description,
    required MaintenanceCategory category,
    required MaintenancePriority priority,
    String? tenantAccessNotes,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests',
      queryParameters: {'tenantId': tenantId},
    );

    final response = await _send(
      () => apiClient.post(
        uri,
        body: jsonEncode({
          'propertyId': propertyId,
          'title': title,
          'description': description,
          'category': category.value,
          'priority': priority.value,
          'tenantAccessNotes': tenantAccessNotes,
        }),
      ),
    );

    return _parseObject(response.body);
  }

  Future<MaintenanceRequest> getMaintenanceRequestById(String id) async {
    final uri = apiClient.buildUri('/api/maintenance-requests/$id');
    final response = await _send(() => apiClient.get(uri));
    return _parseObject(response.body);
  }

  Future<List<RepairEstimate>> getRepairEstimates({
    required String maintenanceRequestId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/estimates',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseEstimateList(response.body);
  }

  Future<RepairEstimate?> getLatestRepairEstimate({
    required String maintenanceRequestId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/estimates/latest',
    );
    final response = await _send(() => apiClient.get(uri));
    if (response.statusCode == 204 || response.body.trim().isEmpty) return null;
    return _parseNullableEstimate(response.body);
  }

  Future<RepairEstimate> createRepairEstimate({
    required String maintenanceRequestId,
    required String technicianId,
    required double laborCost,
    required double partsCost,
    required double additionalCost,
    String? notes,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/estimates',
      queryParameters: {'technicianId': technicianId},
    );
    final response = await _send(
      () => apiClient.post(
        uri,
        body: jsonEncode({
          'laborCost': laborCost,
          'partsCost': partsCost,
          'additionalCost': additionalCost,
          'notes': notes,
        }),
      ),
    );
    return _parseEstimate(response.body);
  }

  Future<MaintenanceRequest> submitEstimateForReview({
    required String maintenanceRequestId,
    required String estimateId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/estimates/'
      '$estimateId/submit-for-review',
    );
    final response = await _send(() => apiClient.patch(uri));
    return _parseStatusTransition(
      response.body,
      expectedStatus: MaintenanceRequestStatus.awaitingLandlordApproval,
    );
  }

  Future<MaintenanceRequest> startWork({required String id}) async {
    final uri = apiClient.buildUri('/api/maintenance-requests/$id/start-work');
    final response = await _send(() => apiClient.patch(uri));
    return _parseStatusTransition(
      response.body,
      expectedStatus: MaintenanceRequestStatus.inProgress,
    );
  }

  Future<MaintenanceRequest> completeWork({required String id}) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$id/complete-work',
    );
    final response = await _send(() => apiClient.patch(uri));
    return _parseStatusTransition(
      response.body,
      expectedStatus: MaintenanceRequestStatus.completed,
    );
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const MaintenanceApiException(
        'Unable to connect to the maintenance service.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MaintenanceApiException(
        _safeErrorMessage(response) ??
            'The maintenance request could not be completed. Please try again.',
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

  MaintenanceRequest _parseObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return MaintenanceRequest.fromJson(decoded);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid response.',
      );
    }
  }

  MaintenanceRequest _parseStatusTransition(
    String body, {
    required MaintenanceRequestStatus expectedStatus,
  }) {
    final request = _parseObject(body);
    if (request.status != expectedStatus) {
      throw const MaintenanceApiException(
        'The maintenance service did not confirm the requested status change.',
      );
    }
    return request;
  }

  RepairEstimate _parseEstimate(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return RepairEstimate.fromJson(decoded);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid estimate.',
      );
    }
  }

  RepairEstimate? _parseNullableEstimate(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded == null) return null;
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return RepairEstimate.fromJson(decoded);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid estimate.',
      );
    }
  }

  List<RepairEstimate> _parseEstimateList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) {
        throw const FormatException();
      }
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException();
            }
            return RepairEstimate.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned invalid estimates.',
      );
    }
  }

  List<Property> _parsePropertyList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) {
        throw const FormatException();
      }
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException();
            }
            return Property.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const MaintenanceApiException(
        'The property service returned an invalid response.',
      );
    }
  }

  List<MaintenanceRequest> _parseList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List<dynamic>) {
        throw const FormatException();
      }

      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException();
            }
            return MaintenanceRequest.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid response.',
      );
    }
  }

  String? _readErrorMessage(String body) {
    if (body.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      for (final key in ['detail', 'title', 'message']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      final errors = decoded['errors'];
      if (errors is Map<String, dynamic>) {
        for (final value in errors.values) {
          if (value is List && value.isNotEmpty && value.first is String) {
            return (value.first as String).trim();
          }
        }
      }
    } on FormatException {
      return null;
    }

    return null;
  }
}

class MaintenanceApiException implements Exception {
  const MaintenanceApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
