import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../../properties/models/property.dart';
import '../models/maintenance_attachment.dart';
import '../models/maintenance_status_history.dart';
import '../models/maintenance_technician_choice.dart';
import '../models/repair_estimate.dart';
import '../models/maintenance_request.dart';

class MaintenanceApiService {
  const MaintenanceApiService(this.apiClient);

  final ApiClient apiClient;

  Future<List<Property>> getTenantProperties() async {
    final uri = apiClient.buildUri('/api/properties/tenant/mine');
    final response = await _send(
      () => apiClient.get(uri),
      onResponse: _logTenantPropertyLookupResponse,
    );
    return _parsePropertyList(response.body);
  }

  void _logTenantPropertyLookupResponse(http.Response response) {
    if (!kDebugMode) return;
    final contentType = response.headers['content-type'] ?? '(missing)';
    debugPrint(
      '[MaintenanceApiService] GET /api/properties/tenant/mine '
      'status=${response.statusCode} content-type=$contentType '
      'body=${_sanitizeDiagnosticBody(response.body)}',
    );
  }

  String _sanitizeDiagnosticBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return jsonEncode(_sanitizeDiagnosticValue(decoded));
    } on FormatException {
      return '"[REDACTED non-JSON response]"';
    }
  }

  Object? _sanitizeDiagnosticValue(Object? value, {String? fieldName}) {
    if (value is Map<String, dynamic>) {
      return value.map(
        (key, entry) =>
            MapEntry(key, _sanitizeDiagnosticValue(entry, fieldName: key)),
      );
    }
    if (value is List) {
      return value
          .map((entry) => _sanitizeDiagnosticValue(entry, fieldName: fieldName))
          .toList(growable: false);
    }
    if (value is String) {
      final field = fieldName?.toLowerCase() ?? '';
      if (RegExp(
        r'(id|name|email|phone|address|description|title|token|password|secret|authorization|tenant|landlord|property|user|instance)',
      ).hasMatch(field)) {
        return '[REDACTED]';
      }
      if (field == 'code' || field == 'errorcode') return value;
      return '[REDACTED]';
    }
    return value;
  }

  MaintenanceAttachment _parseAttachment(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return MaintenanceAttachment.fromJson(decoded);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid attachment.',
      );
    }
  }

  List<MaintenanceAttachment> _parseAttachmentList(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) throw const FormatException();
            return MaintenanceAttachment.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid attachment list.',
      );
    }
  }

  Future<List<MaintenanceRequest>> getMyMaintenanceRequests({
    required String tenantId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/tenant/$tenantId',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseSummaryList(response.body);
  }

  Future<List<MaintenanceRequest>> getAssignedWork({
    required String technicianId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/technician/$technicianId',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseSummaryList(response.body);
  }

  Future<List<MaintenanceRequest>> getMaintenanceRequestsByProperty({
    required String propertyId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/property/$propertyId',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseSummaryList(response.body);
  }

  Future<MaintenanceRequest> createMaintenanceRequest({
    required String tenantId,
    required String propertyId,
    String? title,
    required String description,
    required MaintenanceCategory category,
    required MaintenancePriority priority,
    required PreferredAccessWindow preferredAccessWindow,
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
          'title': ?title,
          'description': description,
          'category': category.value,
          'priority': priority.value,
          'preferredAccessWindow': preferredAccessWindow.apiValue,
          'tenantAccessNotes': ?tenantAccessNotes,
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

  Future<MaintenanceRequest> triageMaintenanceRequest({
    required String id,
    required MaintenanceCategory category,
    required MaintenancePriority priority,
    String? triageNotes,
  }) async {
    final uri = apiClient.buildUri('/api/maintenance-requests/$id/triage');
    final notes = triageNotes?.trim();
    final response = await _send(
      () => apiClient.patch(
        uri,
        body: jsonEncode({
          'category': category.value,
          'priority': priority.value,
          'triageNotes': notes == null || notes.isEmpty ? null : notes,
        }),
      ),
    );
    return _parseStatusTransition(
      response.body,
      expectedStatus: MaintenanceRequestStatus.triaged,
    );
  }

  Future<List<MaintenanceTechnicianChoice>> getMaintenanceTechnicians() async {
    final uri = apiClient.buildUri('/api/maintenance-requests/technicians');
    final response = await _send(() => apiClient.get(uri));
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List<dynamic>) throw const FormatException();
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException();
            }
            return MaintenanceTechnicianChoice.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid technician list.',
      );
    }
  }

  Future<MaintenanceRequest> assignMaintenanceTechnician({
    required String id,
    required String technicianId,
    String? assignmentNotes,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$id/assign-technician',
    );
    final notes = assignmentNotes?.trim();
    final response = await _send(
      () => apiClient.patch(
        uri,
        body: jsonEncode({
          'technicianId': technicianId,
          'assignmentNotes': notes == null || notes.isEmpty ? null : notes,
        }),
      ),
    );
    return _parseStatusTransition(
      response.body,
      expectedStatus: MaintenanceRequestStatus.assigned,
    );
  }

  Future<MaintenanceRequest> requestMaintenanceEstimate({
    required String id,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$id/estimate-pending',
    );
    final response = await _send(() => apiClient.patch(uri));
    return _parseStatusTransition(
      response.body,
      expectedStatus: MaintenanceRequestStatus.estimatePending,
    );
  }

  Future<List<MaintenanceStatusHistory>> getMaintenanceRequestHistory({
    required String maintenanceRequestId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/history',
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseHistoryList(response.body);
  }

  Future<List<MaintenanceAttachment>> getMaintenanceRequestAttachments({
    required String maintenanceRequestId,
    required String tenantId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/attachments',
      queryParameters: {'tenantId': tenantId},
    );
    final response = await _send(() => apiClient.get(uri));
    return _parseAttachmentList(response.body);
  }

  Future<MaintenanceAttachment> uploadMaintenanceAttachment({
    required String maintenanceRequestId,
    required String tenantId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
    String? attachmentType,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/attachments',
      queryParameters: {'tenantId': tenantId},
    );
    final multipart = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );
    if (attachmentType != null && attachmentType.trim().isNotEmpty) {
      multipart.fields['attachmentType'] = attachmentType;
    }
    final response = await _sendStreamed(() => apiClient.send(multipart));
    return _parseAttachment(response.body);
  }

  Future<Uri> requestMaintenanceAttachmentDownloadUrl({
    required String maintenanceRequestId,
    required String attachmentId,
    required String tenantId,
  }) async {
    final endpoint = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/attachments/'
      '$attachmentId',
      queryParameters: {'tenantId': tenantId},
    );
    final request = http.Request('GET', endpoint)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await apiClient.send(request);
    } on http.ClientException {
      throw const MaintenanceApiException(
        'Unable to connect to the maintenance service.',
      );
    }
    if (streamedResponse.statusCode >= 300 &&
        streamedResponse.statusCode < 400) {
      final location = streamedResponse.headers['location'];
      await streamedResponse.stream.drain<void>();
      if (location != null && location.trim().isNotEmpty) {
        return endpoint.resolve(location);
      }
    }
    final response = await http.Response.fromStream(streamedResponse);
    throw MaintenanceApiException(
      _safeErrorMessage(response) ??
          'The attachment download link was invalid.',
      statusCode: response.statusCode,
    );
  }

  Future<void> deleteMaintenanceAttachment({
    required String maintenanceRequestId,
    required String attachmentId,
    required String tenantId,
  }) async {
    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/attachments/'
      '$attachmentId',
      queryParameters: {'tenantId': tenantId},
    );
    await _send(() => apiClient.delete(uri));
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

  Future<RepairEstimate> approveRepairEstimate({
    required String maintenanceRequestId,
    required String estimateId,
    String? reviewNotes,
  }) => _reviewRepairEstimate(
    maintenanceRequestId: maintenanceRequestId,
    estimateId: estimateId,
    action: 'approve',
    reviewNotes: reviewNotes,
    expectedStatus: RepairEstimateStatus.approved,
  );

  Future<RepairEstimate> rejectRepairEstimate({
    required String maintenanceRequestId,
    required String estimateId,
    required String reviewNotes,
  }) => _reviewRepairEstimate(
    maintenanceRequestId: maintenanceRequestId,
    estimateId: estimateId,
    action: 'reject',
    reviewNotes: reviewNotes,
    expectedStatus: RepairEstimateStatus.rejected,
  );

  Future<RepairEstimate> requestRepairEstimateRevision({
    required String maintenanceRequestId,
    required String estimateId,
    required String reviewNotes,
  }) => _reviewRepairEstimate(
    maintenanceRequestId: maintenanceRequestId,
    estimateId: estimateId,
    action: 'request-revision',
    reviewNotes: reviewNotes,
    expectedStatus: RepairEstimateStatus.revisionRequested,
  );

  Future<RepairEstimate> _reviewRepairEstimate({
    required String maintenanceRequestId,
    required String estimateId,
    required String action,
    required RepairEstimateStatus expectedStatus,
    String? reviewNotes,
  }) async {
    final notes = reviewNotes?.trim();
    if ((action == 'reject' || action == 'request-revision') &&
        (notes == null || notes.isEmpty)) {
      throw const MaintenanceApiException(
        'Review notes are required for this estimate decision.',
      );
    }
    if (notes != null && notes.length > 2000) {
      throw const MaintenanceApiException(
        'Review notes cannot exceed 2000 characters.',
      );
    }

    final uri = apiClient.buildUri(
      '/api/maintenance-requests/$maintenanceRequestId/estimates/'
      '$estimateId/$action',
    );
    final response = await _send(
      () => apiClient.patch(
        uri,
        body: jsonEncode({
          'reviewNotes': notes == null || notes.isEmpty ? null : notes,
        }),
      ),
    );
    final estimate = _parseEstimate(response.body);
    if (estimate.status != expectedStatus) {
      throw const MaintenanceApiException(
        'The maintenance service did not confirm the estimate review.',
      );
    }
    return estimate;
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

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    void Function(http.Response)? onResponse,
  }) async {
    late final http.Response response;
    try {
      response = await request();
    } on http.ClientException {
      throw const MaintenanceApiException(
        'Unable to connect to the maintenance service.',
      );
    }

    onResponse?.call(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MaintenanceApiException(
        _safeErrorMessage(response) ??
            'The maintenance request could not be completed. Please try again.',
        statusCode: response.statusCode,
      );
    }

    return response;
  }

  Future<http.Response> _sendStreamed(
    Future<http.StreamedResponse> Function() request,
  ) async {
    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await request();
    } on http.ClientException {
      throw const MaintenanceApiException(
        'Unable to connect to the maintenance service.',
      );
    }
    final response = await http.Response.fromStream(streamedResponse);
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

  List<MaintenanceRequest> _parseSummaryList(String body) {
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
            return MaintenanceRequest.fromSummaryJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid response.',
      );
    }
  }

  List<MaintenanceStatusHistory> _parseHistoryList(String body) {
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
            return MaintenanceStatusHistory.fromJson(item);
          })
          .toList(growable: false);
    } on FormatException {
      throw const MaintenanceApiException(
        'The maintenance service returned an invalid history response.',
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
