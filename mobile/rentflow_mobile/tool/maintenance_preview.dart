// Standalone UI preview. All responses are in memory; no backend is contacted.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/services/auth_service.dart';
import 'package:rentflow_mobile/features/maintenance/screens/my_maintenance_requests_screen.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

const _tenantId = '11111111-1111-1111-1111-111111111112';
const _propertyId = '22222222-2222-2222-2222-222222222222';

class _PreviewTokenStorage implements TokenStorage {
  String? _token = 'preview-only';
  @override
  Future<String?> readToken() async => _token;
  @override
  Future<void> saveToken(String token) async => _token = token;
  @override
  Future<void> deleteToken() async => _token = null;
}

Map<String, dynamic> _sampleRequest(String id, String title, int status) => {
  'id': id,
  'propertyId': _propertyId,
  'tenantId': _tenantId,
  'title': title,
  'description': 'Sample maintenance request for the preview apartment.',
  'category': 0,
  'priority': 1,
  'status': status,
  'createdAt': DateTime.now().toUtc().toIso8601String(),
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const noProperty = bool.fromEnvironment('PREVIEW_NO_PROPERTY');
  const empty = bool.fromEnvironment('PREVIEW_EMPTY');
  final requests = <Map<String, dynamic>>[
    if (!empty && !noProperty) ...[
      _sampleRequest('preview-1', 'Kitchen tap leaking', 0),
      _sampleRequest('preview-2', 'Bathroom pipe repair', 8),
      _sampleRequest('preview-3', 'Sink drain cleared', 9),
    ],
  ];
  final storage = _PreviewTokenStorage();
  final client = ApiClient(
    baseUrl: 'https://preview.invalid',
    tokenStorage: storage,
    httpClient: MockClient((request) async {
      Object body;
      final path = request.url.path;
      if (path == '/api/auth/me') {
        body = {
          'id': _tenantId,
          'fullName': 'Preview Tenant',
          'email': 'tenant@example.com',
          'phoneNumber': '+94 77 123 4567',
          'role': 'Tenant',
        };
      } else if (path == '/api/properties/tenant/mine') {
        body = [
          if (!noProperty)
            {
              'id': _propertyId,
              'landlordId': '33333333-3333-3333-3333-333333333333',
              'title': 'Preview Apartment',
              'description': 'Sample assigned property',
              'address': '12 Lake Road',
              'city': 'Colombo',
              'monthlyRent': 65000,
              'bedrooms': 2,
              'bathrooms': 1,
              'isAvailable': false,
              'createdAt': '2026-09-01T00:00:00Z',
              'amenities': <String>[],
            },
        ];
      } else if (path == '/api/maintenance-requests/tenant/$_tenantId') {
        body = requests;
      } else if (path == '/api/maintenance-requests' &&
          request.method == 'POST' &&
          !noProperty) {
        final fields = jsonDecode(request.body) as Map<String, dynamic>;
        final created = {
          ..._sampleRequest(
            'preview-${requests.length + 1}',
            fields['title'] as String,
            0,
          ),
          ...fields,
        };
        requests.insert(0, created);
        body = created;
      } else {
        final matches = requests.where(
          (item) => path == '/api/maintenance-requests/${item['id']}',
        );
        if (request.method != 'GET' || matches.isEmpty) {
          return http.Response('{"message":"Unsupported preview action"}', 404);
        }
        body = matches.first;
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final auth = AuthController(
    authService: AuthService(client),
    tokenStorage: storage,
  );
  await auth.restoreSession();
  runApp(
    AuthScope(
      controller: auth,
      child: MaterialApp(
        title: 'Tenant Maintenance Preview',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: MyMaintenanceRequestsScreen(
          maintenanceApiService: MaintenanceApiService(client),
        ),
      ),
    ),
  );
}
