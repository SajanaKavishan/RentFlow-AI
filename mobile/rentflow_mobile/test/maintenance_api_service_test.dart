import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/maintenance/models/maintenance_request.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage([this._token]);

  String? _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> deleteToken() async {
    _token = null;
  }
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responses);

  final Map<String, http.Response> _responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) {
    final response = _responses[url.toString()];
    if (response == null) {
      return Future.value(
        http.Response(
          jsonEncode({'detail': 'Not found'}),
          404,
        ),
      );
    }
    return Future.value(response);
  }

  @override
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    final response = _responses[url.toString()];
    if (response == null) {
      return Future.value(
        http.Response(
          jsonEncode({'detail': 'Not found'}),
          404,
        ),
      );
    }
    return Future.value(response);
  }

  @override
  Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    final response = _responses[url.toString()];
    if (response == null) {
      return Future.value(
        http.Response(
          jsonEncode({'detail': 'Not found'}),
          404,
        ),
      );
    }
    return Future.value(response);
  }
}

void main() {
  group('MaintenanceApiService', () {
    test('parses a tenant maintenance request list', () async {
      final json = [
        {
          'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
          'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
          'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
          'technicianId': 'd0f76d69-b415-4900-a6a8-7d11df8bb34c',
          'title': 'Kitchen sink leak',
          'description': 'Water is leaking under the sink cabinet.',
          'category': 0,
          'priority': 2,
          'status': 3,
          'tenantAccessNotes': 'Use the back door.',
          'triageNotes': 'Check the pipe seal.',
          'assignmentNotes': 'Technician to visit Monday morning.',
          'cancellationReason': null,
          'completedAt': null,
          'createdAt': '2026-09-17T08:15:00Z',
          'updatedAt': '2026-09-18T10:00:00Z',
        },
      ];

      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/tenant/a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff':
                http.Response(jsonEncode(json), 200),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      final requests = await service.getMyMaintenanceRequests(
        tenantId: 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
      );

      expect(requests, hasLength(1));
      expect(requests.first.title, 'Kitchen sink leak');
      expect(requests.first.category, MaintenanceCategory.plumbing);
      expect(requests.first.priority, MaintenancePriority.high);
      expect(requests.first.status, MaintenanceRequestStatus.estimatePending);
    });

    test('parses a created maintenance request', () async {
      final payload = {
        'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
        'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        'technicianId': null,
        'title': 'Boiler noise',
        'description': 'Heating unit is making a loud knocking sound.',
        'category': 1,
        'priority': 1,
        'status': 0,
        'tenantAccessNotes': 'Please ring the front bell.',
        'triageNotes': null,
        'assignmentNotes': null,
        'cancellationReason': null,
        'completedAt': null,
        'createdAt': '2026-09-17T08:15:00Z',
        'updatedAt': null,
      };

      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests?tenantId=a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff':
                http.Response(jsonEncode(payload), 201),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      final request = await service.createMaintenanceRequest(
        tenantId: 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        propertyId: 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        title: 'Boiler noise',
        description: 'Heating unit is making a loud knocking sound.',
        category: MaintenanceCategory.electrical,
        priority: MaintenancePriority.normal,
        tenantAccessNotes: 'Please ring the front bell.',
      );

      expect(request.title, 'Boiler noise');
      expect(request.category, MaintenanceCategory.electrical);
      expect(request.priority, MaintenancePriority.normal);
      expect(request.status, MaintenanceRequestStatus.submitted);
      expect(request.tenantAccessNotes, 'Please ring the front bell.');
    });

    test('parses a maintenance request detail payload', () async {
      final payload = {
        'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
        'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        'technicianId': null,
        'title': 'Boiler noise',
        'description': 'Heating unit is making a loud knocking sound.',
        'category': 1,
        'priority': 1,
        'status': 0,
        'tenantAccessNotes': null,
        'triageNotes': null,
        'assignmentNotes': null,
        'cancellationReason': null,
        'completedAt': null,
        'createdAt': '2026-09-17T08:15:00Z',
        'updatedAt': null,
      };

      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200':
                http.Response(jsonEncode(payload), 200),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      final request = await service.getMaintenanceRequestById(
        '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
      );

      expect(request.id, '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200');
      expect(request.description, 'Heating unit is making a loud knocking sound.');
      expect(request.category, MaintenanceCategory.electrical);
      expect(request.status, MaintenanceRequestStatus.submitted);
    });

    test('starts maintenance work when the technician confirms the job', () async {
      final payload = {
        'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
        'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        'technicianId': 'd0f76d69-b415-4900-a6a8-7d11df8bb34c',
        'title': 'Boiler noise',
        'description': 'Heating unit is making a loud knocking sound.',
        'category': 1,
        'priority': 1,
        'status': 8,
        'tenantAccessNotes': null,
        'triageNotes': null,
        'assignmentNotes': null,
        'cancellationReason': null,
        'completedAt': null,
        'createdAt': '2026-09-17T08:15:00Z',
        'updatedAt': '2026-09-19T12:00:00Z',
      };

      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200/start-work':
                http.Response(jsonEncode(payload), 200),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      final request = await service.startWork(
        id: '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
      );

      expect(request.status, MaintenanceRequestStatus.inProgress);
      expect(request.technicianId, 'd0f76d69-b415-4900-a6a8-7d11df8bb34c');
    });

    test('completes maintenance work once the technician has finished', () async {
      final payload = {
        'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
        'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        'technicianId': 'd0f76d69-b415-4900-a6a8-7d11df8bb34c',
        'title': 'Boiler noise',
        'description': 'Heating unit is making a loud knocking sound.',
        'category': 1,
        'priority': 1,
        'status': 9,
        'tenantAccessNotes': null,
        'triageNotes': null,
        'assignmentNotes': null,
        'cancellationReason': null,
        'completedAt': '2026-09-19T14:30:00Z',
        'createdAt': '2026-09-17T08:15:00Z',
        'updatedAt': '2026-09-19T14:30:00Z',
      };

      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200/complete-work':
                http.Response(jsonEncode(payload), 200),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      final request = await service.completeWork(
        id: '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
      );

      expect(request.status, MaintenanceRequestStatus.completed);
      expect(request.completedAt, isNotNull);
    });

    test('throws an API exception on backend error responses', () async {
      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/tenant/a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff':
                http.Response(jsonEncode({'detail': 'Bad request'}), 400),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      expect(
        () => service.getMyMaintenanceRequests(
          tenantId: 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        ),
        throwsA(isA<MaintenanceApiException>()),
      );
    });

    test('throws an API exception for malformed JSON responses', () async {
      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/tenant/a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff':
                http.Response('not-json', 200),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      expect(
        () => service.getMyMaintenanceRequests(
          tenantId: 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
        ),
        throwsA(isA<MaintenanceApiException>()),
      );
    });
  });
}
