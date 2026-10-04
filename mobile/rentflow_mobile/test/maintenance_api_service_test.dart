import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/maintenance/models/maintenance_attachment.dart';
import 'package:rentflow_mobile/features/maintenance/models/maintenance_request.dart';
import 'package:rentflow_mobile/features/maintenance/models/repair_estimate.dart';
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
        http.Response(jsonEncode({'detail': 'Not found'}), 404),
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
        http.Response(jsonEncode({'detail': 'Not found'}), 404),
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
        http.Response(jsonEncode({'detail': 'Not found'}), 404),
      );
    }
    return Future.value(response);
  }
}

class _AttachmentHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      final body = await request.finalize().toBytes();
      final payload = utf8.decode(body);
      expect(payload, contains('photo.jpg'));
      expect(payload, contains('damage photo'));
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'id': 'attachment-1',
              'maintenanceRequestId': 'request-1',
              'fileName': 'photo.jpg',
              'contentType': 'image/jpeg',
              'fileSize': 3,
              'attachmentType': 'damage photo',
              'uploadedByUserId': 'tenant-1',
              'createdAt': '2026-09-18T10:00:00Z',
            }),
          ),
        ),
        201,
      );
    }
    if (request.method == 'GET') {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        302,
        headers: {'location': 'https://downloads.example/photo.jpg'},
      );
    }
    if (request.method == 'DELETE') {
      return http.StreamedResponse(const Stream<List<int>>.empty(), 204);
    }
    return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
  }
}

void main() {
  group('MaintenanceApiService', () {
    test('loads the authenticated tenant property choices', () async {
      final property = {
        'id': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
        'landlordId': 'd0f76d69-b415-4900-a6a8-7d11df8bb34c',
        'title': 'Garden apartment',
        'description': 'Two bedroom apartment.',
        'address': '12 Garden Road',
        'city': 'Colombo',
        'latitude': null,
        'longitude': null,
        'googlePlaceId': null,
        'monthlyRent': 85000,
        'advertisedSecurityDeposit': null,
        'preferredLeaseTermMonths': null,
        'petPolicy': null,
        'petPolicyNotes': null,
        'includedUtilities': null,
        'bedrooms': 2,
        'bathrooms': 1,
        'area': 1450,
        'areaUnit': 'sqft',
        'areaType': 'FloorArea',
        'availableFrom': '2026-10-01',
        'isAvailable': false,
        'createdAt': '2026-09-17T08:15:00Z',
        'updatedAt': null,
        'amenities': ['Parking'],
        'amenityDetails': [
          {'canonicalKey': 'parking', 'name': 'Parking'},
        ],
      };
      final apiClient = ApiClient(
        httpClient: _FakeHttpClient({
          'http://10.0.2.2:5277/api/properties/tenant/mine': http.Response(
            jsonEncode([property]),
            200,
          ),
        }),
        tokenStorage: _MemoryTokenStorage('token'),
      );
      final service = MaintenanceApiService(apiClient);

      final properties = await service.getTenantProperties();

      expect(properties, hasLength(1));
      expect(properties.single.id, 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0');
      expect(properties.single.title, 'Garden apartment');
      apiClient.close();
    });

    test('parses a tenant maintenance request list', () async {
      final json = [
        {
          'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
          'propertyId': 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0',
          'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
          'technicianId': 'd0f76d69-b415-4900-a6a8-7d11df8bb34c',
          'title': 'Kitchen sink leak',
          'category': 0,
          'priority': 2,
          'status': 3,
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
      expect(requests.first.description, isEmpty);
    });

    test('parses the technician assigned-work summary contract', () async {
      const technicianId = 'd0f76d69-b415-4900-a6a8-7d11df8bb34c';
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: _MemoryTokenStorage('token'),
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/api/maintenance-requests/technician/$technicianId',
          );
          return http.Response(
            jsonEncode([
              {
                'id': 'request-1',
                'propertyId': 'property-1',
                'tenantId': 'tenant-1',
                'technicianId': technicianId,
                'title': 'Kitchen sink leak',
                'category': 0,
                'priority': 2,
                'status': MaintenanceRequestStatus.estimatePending.value,
                'createdAt': '2026-09-17T08:15:00Z',
                'updatedAt': null,
              },
            ]),
            200,
          );
        }),
      );
      final service = MaintenanceApiService(apiClient);

      final requests = await service.getAssignedWork(
        technicianId: technicianId,
      );

      expect(requests, hasLength(1));
      expect(requests.single.id, 'request-1');
      expect(requests.single.description, isEmpty);
      expect(requests.single.status, MaintenanceRequestStatus.estimatePending);
      apiClient.close();
    });

    test('parses the backend property maintenance summary response', () async {
      const propertyId = 'c4a9b4ec-74aa-4d2d-9aae-18a63a7637e0';
      final responseJson = [
        {
          'id': '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
          'propertyId': propertyId,
          'tenantId': 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff',
          'technicianId': null,
          'title': 'Kitchen sink leak',
          'category': 0,
          'priority': 2,
          'status': 1,
          'createdAt': '2026-09-17T08:15:00Z',
          'updatedAt': null,
        },
      ];
      final apiClient = ApiClient(
        httpClient: _FakeHttpClient({
          'http://10.0.2.2:5277/api/maintenance-requests/property/$propertyId':
              http.Response(jsonEncode(responseJson), 200),
        }),
        tokenStorage: _MemoryTokenStorage('token'),
      );
      addTearDown(apiClient.close);
      final service = MaintenanceApiService(apiClient);

      final requests = await service.getMaintenanceRequestsByProperty(
        propertyId: propertyId,
      );

      expect(requests, hasLength(1));
      expect(requests.single.title, 'Kitchen sink leak');
      expect(requests.single.category, MaintenanceCategory.plumbing);
      expect(requests.single.priority, MaintenancePriority.high);
      expect(requests.single.status, MaintenanceRequestStatus.triaged);
      expect(requests.single.description, isEmpty);
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
      expect(
        request.description,
        'Heating unit is making a loud knocking sound.',
      );
      expect(request.category, MaintenanceCategory.electrical);
      expect(request.status, MaintenanceRequestStatus.submitted);
    });

    test(
      'triages a request with the existing triage endpoint contract',
      () async {
        final payload = {
          'id': 'request-1',
          'propertyId': 'property-1',
          'tenantId': 'tenant-1',
          'technicianId': null,
          'title': 'Boiler noise',
          'description': 'Heating unit is making a loud knocking sound.',
          'category': 1,
          'priority': 3,
          'status': 1,
          'tenantAccessNotes': null,
          'triageNotes': 'Inspect the electrical connection.',
          'assignmentNotes': null,
          'cancellationReason': null,
          'completedAt': null,
          'createdAt': '2026-09-17T08:15:00Z',
          'updatedAt': '2026-09-18T10:00:00Z',
        };
        final apiClient = ApiClient(
          baseUrl: 'http://test',
          tokenStorage: _MemoryTokenStorage('token'),
          httpClient: MockClient((request) async {
            expect(request.method, 'PATCH');
            expect(
              request.url.path,
              '/api/maintenance-requests/request-1/triage',
            );
            expect(jsonDecode(request.body), {
              'category': MaintenanceCategory.electrical.value,
              'priority': MaintenancePriority.emergency.value,
              'triageNotes': 'Inspect the electrical connection.',
            });
            return http.Response(jsonEncode(payload), 200);
          }),
        );
        final service = MaintenanceApiService(apiClient);

        final triaged = await service.triageMaintenanceRequest(
          id: 'request-1',
          category: MaintenanceCategory.electrical,
          priority: MaintenancePriority.emergency,
          triageNotes: '  Inspect the electrical connection.  ',
        );

        expect(triaged.status, MaintenanceRequestStatus.triaged);
        expect(triaged.triageNotes, 'Inspect the electrical connection.');
        apiClient.close();
      },
    );

    test(
      'loads technicians, assigns one, and requests an estimate using landlord contracts',
      () async {
        final payload = {
          'id': 'request-1',
          'propertyId': 'property-1',
          'tenantId': 'tenant-1',
          'technicianId': null,
          'title': 'Boiler noise',
          'description': 'Heating unit is making a loud knocking sound.',
          'category': 1,
          'priority': 3,
          'status': MaintenanceRequestStatus.triaged.value,
          'tenantAccessNotes': null,
          'triageNotes': 'Inspect the electrical connection.',
          'assignmentNotes': null,
          'cancellationReason': null,
          'completedAt': null,
          'createdAt': '2026-09-17T08:15:00Z',
          'updatedAt': null,
        };
        final apiClient = ApiClient(
          baseUrl: 'http://test',
          tokenStorage: _MemoryTokenStorage('token'),
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/maintenance-requests/technicians') {
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode([
                  {'id': 'technician-1', 'name': 'Ari Technician'},
                ]),
                200,
              );
            }
            if (request.url.path.endsWith('/assign-technician')) {
              expect(request.method, 'PATCH');
              expect(jsonDecode(request.body), {
                'technicianId': 'technician-1',
                'assignmentNotes': 'Visit during daytime.',
              });
              payload
                ..['technicianId'] = 'technician-1'
                ..['assignmentNotes'] = 'Visit during daytime.'
                ..['status'] = MaintenanceRequestStatus.assigned.value;
              return http.Response(jsonEncode(payload), 200);
            }
            if (request.url.path.endsWith('/estimate-pending')) {
              expect(request.method, 'PATCH');
              expect(request.body, isEmpty);
              payload['status'] =
                  MaintenanceRequestStatus.estimatePending.value;
              return http.Response(jsonEncode(payload), 200);
            }
            return http.Response('', 404);
          }),
        );
        final service = MaintenanceApiService(apiClient);

        final technicians = await service.getMaintenanceTechnicians();
        final assigned = await service.assignMaintenanceTechnician(
          id: 'request-1',
          technicianId: 'technician-1',
          assignmentNotes: '  Visit during daytime.  ',
        );
        final estimatePending = await service.requestMaintenanceEstimate(
          id: 'request-1',
        );

        expect(technicians, hasLength(1));
        expect(technicians.single.id, 'technician-1');
        expect(technicians.single.name, 'Ari Technician');
        expect(assigned.status, MaintenanceRequestStatus.assigned);
        expect(assigned.technicianId, 'technician-1');
        expect(
          estimatePending.status,
          MaintenanceRequestStatus.estimatePending,
        );
        apiClient.close();
      },
    );

    test(
      'parses repair estimate history and an absent latest estimate',
      () async {
        final estimate = _estimatePayload(
          status: RepairEstimateStatus.approved,
        );
        final apiClient = ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/request-1/estimates':
                http.Response(jsonEncode([estimate]), 200),
            'http://10.0.2.2:5277/api/maintenance-requests/request-2/estimates/latest':
                http.Response('', 204),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        );
        final service = MaintenanceApiService(apiClient);

        final estimates = await service.getRepairEstimates(
          maintenanceRequestId: 'request-1',
        );
        final latest = await service.getLatestRepairEstimate(
          maintenanceRequestId: 'request-2',
        );

        expect(estimates, hasLength(1));
        expect(estimates.single.status, RepairEstimateStatus.approved);
        expect(estimates.single.totalCost, 150.5);
        expect(latest, isNull);
        apiClient.close();
      },
    );

    test('reviews an estimate using the landlord review contracts', () async {
      final actions = [
        (
          'approve',
          RepairEstimateStatus.approved,
          'approveRepairEstimate',
          '  Looks good.  ',
          'Looks good.',
        ),
        (
          'reject',
          RepairEstimateStatus.rejected,
          'rejectRepairEstimate',
          'Please provide a clearer cost breakdown.',
          'Please provide a clearer cost breakdown.',
        ),
        (
          'request-revision',
          RepairEstimateStatus.revisionRequested,
          'requestRepairEstimateRevision',
          'Please include the replacement valve cost.',
          'Please include the replacement valve cost.',
        ),
      ];
      var calls = 0;
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: _MemoryTokenStorage('token'),
        httpClient: MockClient((request) async {
          calls++;
          expect(request.method, 'PATCH');
          expect(
            request.url.path,
            '/api/maintenance-requests/request-1/estimates/'
            'estimate-1/${request.url.pathSegments.last}',
          );
          final action = request.url.pathSegments.last;
          final scenario = actions.singleWhere((item) => item.$1 == action);
          expect(request.url.queryParameters, isEmpty);
          expect(jsonDecode(request.body), {'reviewNotes': scenario.$5});
          return http.Response(
            jsonEncode(_estimatePayload(status: scenario.$2)),
            200,
          );
        }),
      );
      addTearDown(apiClient.close);
      final service = MaintenanceApiService(apiClient);

      final approved = await service.approveRepairEstimate(
        maintenanceRequestId: 'request-1',
        estimateId: 'estimate-1',
        reviewNotes: actions[0].$4,
      );
      final rejected = await service.rejectRepairEstimate(
        maintenanceRequestId: 'request-1',
        estimateId: 'estimate-1',
        reviewNotes: actions[1].$4,
      );
      final revisionRequested = await service.requestRepairEstimateRevision(
        maintenanceRequestId: 'request-1',
        estimateId: 'estimate-1',
        reviewNotes: actions[2].$4,
      );

      expect(approved.status, RepairEstimateStatus.approved);
      expect(rejected.status, RepairEstimateStatus.rejected);
      expect(revisionRequested.status, RepairEstimateStatus.revisionRequested);
      expect(calls, 3);
      await expectLater(
        service.rejectRepairEstimate(
          maintenanceRequestId: 'request-1',
          estimateId: 'estimate-1',
          reviewNotes: ' ',
        ),
        throwsA(isA<MaintenanceApiException>()),
      );
      expect(calls, 3);
    });

    test(
      'creates a breakdown and submits a persisted estimate for review',
      () async {
        final estimate = _estimatePayload(
          status: RepairEstimateStatus.submitted,
        );
        final maintenanceRequestPayload = {
          'id': 'request-1',
          'propertyId': 'property-1',
          'tenantId': 'tenant-1',
          'technicianId': 'technician-1',
          'title': 'Boiler noise',
          'description': 'Heating unit is making a loud knocking sound.',
          'category': 1,
          'priority': 1,
          'status': MaintenanceRequestStatus.awaitingLandlordApproval.value,
          'tenantAccessNotes': null,
          'triageNotes': null,
          'assignmentNotes': null,
          'cancellationReason': null,
          'completedAt': null,
          'createdAt': '2026-09-17T08:15:00Z',
          'updatedAt': null,
        };
        final apiClient = ApiClient(
          baseUrl: 'http://test',
          httpClient: MockClient((httpRequest) async {
            if (httpRequest.method == 'POST') {
              expect(
                httpRequest.url.path,
                '/api/maintenance-requests/request-1/estimates',
              );
              expect(
                httpRequest.url.queryParameters['technicianId'],
                'technician-1',
              );
              expect(jsonDecode(httpRequest.body), {
                'laborCost': 100.5,
                'partsCost': 40,
                'additionalCost': 10,
                'notes': 'Replace the valve.',
              });
              return http.Response(jsonEncode(estimate), 201);
            }
            if (httpRequest.method == 'PATCH') {
              expect(
                httpRequest.url.path,
                '/api/maintenance-requests/request-1/estimates/estimate-1/submit-for-review',
              );
              return http.Response(jsonEncode(maintenanceRequestPayload), 200);
            }
            return http.Response('', 404);
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        );
        final service = MaintenanceApiService(apiClient);

        final created = await service.createRepairEstimate(
          maintenanceRequestId: 'request-1',
          technicianId: 'technician-1',
          laborCost: 100.5,
          partsCost: 40,
          additionalCost: 10,
          notes: 'Replace the valve.',
        );
        final submitted = await service.submitEstimateForReview(
          maintenanceRequestId: 'request-1',
          estimateId: created.id,
        );

        expect(created.status, RepairEstimateStatus.submitted);
        expect(created.totalCost, 150.5);
        expect(
          submitted.status,
          MaintenanceRequestStatus.awaitingLandlordApproval,
        );
        apiClient.close();
      },
    );

    test(
      'starts maintenance work when the technician confirms the job',
      () async {
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

        final apiClient = ApiClient(
          baseUrl: 'http://test',
          httpClient: MockClient((httpRequest) async {
            expect(httpRequest.method, 'PATCH');
            expect(
              httpRequest.url.path,
              '/api/maintenance-requests/'
              '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200/start-work',
            );
            expect(httpRequest.body, isEmpty);
            return http.Response(jsonEncode(payload), 200);
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        );
        addTearDown(apiClient.close);
        final service = MaintenanceApiService(apiClient);

        final request = await service.startWork(
          id: '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200',
        );

        expect(request.status, MaintenanceRequestStatus.inProgress);
        expect(request.technicianId, 'd0f76d69-b415-4900-a6a8-7d11df8bb34c');
      },
    );

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

      final apiClient = ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((httpRequest) async {
          expect(httpRequest.method, 'PATCH');
          expect(
            httpRequest.url.path,
            '/api/maintenance-requests/'
            '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200/complete-work',
          );
          expect(httpRequest.body, isEmpty);
          return http.Response(jsonEncode(payload), 200);
        }),
        tokenStorage: _MemoryTokenStorage('token'),
      );
      addTearDown(apiClient.close);
      final service = MaintenanceApiService(apiClient);

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

    test('parses maintenance request history', () async {
      final requestId = '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200';
      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/$requestId/history':
                http.Response(
                  jsonEncode([
                    {
                      'id': 'history-1',
                      'fromStatus': null,
                      'toStatus': 0,
                      'changedByUserId': null,
                      'changedAt': '2026-09-17T08:15:00Z',
                      'notes': 'Request submitted.',
                    },
                    {
                      'id': 'history-2',
                      'fromStatus': 0,
                      'toStatus': 1,
                      'changedByUserId': 'landlord-1',
                      'changedAt': '2026-09-18T10:00:00Z',
                      'notes': null,
                    },
                  ]),
                  200,
                ),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      final history = await service.getMaintenanceRequestHistory(
        maintenanceRequestId: requestId,
      );

      expect(history, hasLength(2));
      expect(history.first.fromStatus, isNull);
      expect(history.first.toStatus, MaintenanceRequestStatus.submitted);
      expect(history.first.notes, 'Request submitted.');
      expect(history.last.fromStatus, MaintenanceRequestStatus.submitted);
      expect(history.last.toStatus, MaintenanceRequestStatus.triaged);
    });

    test('loads maintenance attachment metadata for a tenant request', () async {
      const requestId = '7d4d0f16-1a1d-442a-8c1f-cf6c0b66b200';
      const tenantId = 'a8160d5a-3e08-4de6-8f6d-1bb1d0ee13ff';
      final service = MaintenanceApiService(
        ApiClient(
          httpClient: _FakeHttpClient({
            'http://10.0.2.2:5277/api/maintenance-requests/$requestId/attachments'
                '?tenantId=$tenantId': http.Response(
              jsonEncode([
                {
                  'id': 'attachment-1',
                  'maintenanceRequestId': requestId,
                  'fileName': 'leak-photo.webp',
                  'contentType': 'image/webp',
                  'fileSize': 4096,
                  'attachmentType': 'damage photo',
                  'uploadedByUserId': tenantId,
                  'createdAt': '2026-09-18T10:00:00Z',
                },
              ]),
              200,
            ),
          }),
          tokenStorage: _MemoryTokenStorage('token'),
        ),
      );

      final attachments = await service.getMaintenanceRequestAttachments(
        maintenanceRequestId: requestId,
        tenantId: tenantId,
      );

      expect(attachments, hasLength(1));
      expect(attachments.single, isA<MaintenanceAttachment>());
      expect(attachments.single.fileName, 'leak-photo.webp');
      expect(attachments.single.contentType, 'image/webp');
      expect(attachments.single.fileSize, 4096);
      expect(attachments.single.attachmentType, 'damage photo');
    });

    test('uploads, downloads, and deletes a maintenance attachment', () async {
      const requestId = 'request-1';
      const tenantId = 'tenant-1';
      const attachmentId = 'attachment-1';
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        httpClient: _AttachmentHttpClient(),
        tokenStorage: _MemoryTokenStorage('token'),
      );
      final service = MaintenanceApiService(apiClient);

      final uploaded = await service.uploadMaintenanceAttachment(
        maintenanceRequestId: requestId,
        tenantId: tenantId,
        fileName: 'photo.jpg',
        contentType: 'image/jpeg',
        bytes: Uint8List.fromList([1, 2, 3]),
        attachmentType: 'damage photo',
      );
      final downloadUrl = await service.requestMaintenanceAttachmentDownloadUrl(
        maintenanceRequestId: requestId,
        attachmentId: attachmentId,
        tenantId: tenantId,
      );
      await service.deleteMaintenanceAttachment(
        maintenanceRequestId: requestId,
        attachmentId: attachmentId,
        tenantId: tenantId,
      );

      expect(uploaded.id, attachmentId);
      expect(downloadUrl.toString(), 'https://downloads.example/photo.jpg');
      apiClient.close();
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

Map<String, dynamic> _estimatePayload({
  required RepairEstimateStatus status,
}) => {
  'id': 'estimate-1',
  'maintenanceRequestId': 'request-1',
  'technicianId': 'technician-1',
  'versionNumber': 1,
  'laborCost': 100.5,
  'partsCost': 40,
  'additionalCost': 10,
  'totalCost': 150.5,
  'notes': 'Replace the valve.',
  'status': status.value,
  'createdAt': '2026-09-19T08:15:00Z',
  'submittedAt': '2026-09-19T08:20:00Z',
  'reviewedAt': status == RepairEstimateStatus.approved
      ? '2026-09-20T08:20:00Z'
      : null,
  'reviewNotes': status == RepairEstimateStatus.approved ? 'Approved.' : null,
};
