import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/maintenance/screens/assigned_work_screen.dart';
import 'package:rentflow_mobile/features/maintenance/screens/create_maintenance_request_screen.dart';
import 'package:rentflow_mobile/features/maintenance/screens/my_maintenance_requests_screen.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/shared/shell/shared_app_shell.dart';

import 'widget_test.dart' as fixtures;

void main() {
  testWidgets(
    'technician selects assigned work, starts it, completes it, and refreshes the queue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = fixtures.MemoryTokenStorage('token');
      final controller = fixtures.buildController(
        storage,
        role: UserRole.maintenanceTechnician,
      );
      await controller.restoreSession();
      addTearDown(controller.dispose);

      final requests = <Map<String, dynamic>>[
        _maintenanceRequest(
          id: 'request-1',
          title: 'Assigned request',
          status: 2,
        ),
        _maintenanceRequest(
          id: 'request-2',
          title: 'Approved request',
          status: 6,
        ),
      ];
      final queuePaths = <String>[];
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/technician/')) {
            queuePaths.add(request.url.path);
            return http.Response(jsonEncode(requests), 200);
          }
          if (request.url.path.endsWith('/start-work')) {
            requests[1] = {...requests[1], 'status': 8};
            return http.Response(jsonEncode(requests[1]), 200);
          }
          if (request.url.path.endsWith('/complete-work')) {
            requests[1] = {
              ...requests[1],
              'status': 9,
              'completedAt': '2026-09-19T14:30:00Z',
            };
            return http.Response(jsonEncode(requests[1]), 200);
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(apiClient.close);

      await tester.pumpWidget(
        AuthScope(
          controller: controller,
          child: MaterialApp(
            home: SharedAppShell(
              user: CurrentUser.fromJson(
                fixtures.userJson(UserRole.maintenanceTechnician),
              ),
              maintenanceApiService: MaintenanceApiService(apiClient),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is NavigationDestination &&
              widget.label == 'Assigned Work',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assigned request'), findsOneWidget);
      expect(find.text('Approved request · approved'), findsOneWidget);
      await tester.tap(find.text('Approved request · approved'));
      await tester.pumpAndSettle();
      final startWorkButton = find.byKey(
        const ValueKey('start-maintenance-work'),
      );
      await tester.ensureVisible(startWorkButton);
      await tester.tap(startWorkButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('complete-maintenance-work')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final completeWorkButton = find.byKey(
        const ValueKey('complete-maintenance-work'),
      );
      await tester.ensureVisible(completeWorkButton);
      await tester.tap(completeWorkButton);
      await tester.pumpAndSettle();

      expect(find.text('Approved request · completed'), findsOneWidget);
      expect(queuePaths, hasLength(3));
      expect(
        queuePaths.every(
          (path) =>
              path.endsWith('/technician/11111111-1111-1111-1111-111111111112'),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tenant selects an associated property and submits its actual ID',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = fixtures.MemoryTokenStorage('token');
      final controller = fixtures.buildController(
        storage,
        role: UserRole.tenant,
      );
      await controller.restoreSession();
      addTearDown(controller.dispose);

      String? submittedPropertyId;
      Map<String, dynamic>? createdRequest;
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/properties/tenant/mine')) {
            return http.Response(
              jsonEncode([
                _tenantProperty('property-occupied-a', 'Lake apartment'),
                _tenantProperty('property-occupied-b', 'Garden apartment'),
              ]),
              200,
            );
          }
          if (request.url.path.contains('/maintenance-requests/tenant/')) {
            return http.Response(
              jsonEncode(createdRequest == null ? [] : [createdRequest]),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path.endsWith('/maintenance-requests')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            submittedPropertyId = body['propertyId'] as String?;
            expect(
              request.url.queryParameters['tenantId'],
              '11111111-1111-1111-1111-111111111112',
            );
            createdRequest = _maintenanceRequest(
              id: 'created-request',
              title: body['title'] as String,
              status: 0,
            )..['propertyId'] = submittedPropertyId;
            return http.Response(jsonEncode(createdRequest), 201);
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(apiClient.close);

      await tester.pumpWidget(
        AuthScope(
          controller: controller,
          child: MaterialApp(
            home: MyMaintenanceRequestsScreen(
              maintenanceApiService: MaintenanceApiService(apiClient),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Create maintenance request'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a property'), findsOneWidget);
      await tester.tap(find.text('Garden apartment'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Leaking kitchen tap',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Water is dripping under the kitchen sink.',
      );
      await tester.ensureVisible(find.text('Submit request'));
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();

      expect(submittedPropertyId, 'property-occupied-b');
      expect(find.text('Leaking kitchen tap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tenant cannot create a request without an associated property', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(storage, role: UserRole.tenant);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((request) async => http.Response('[]', 200)),
    );
    addTearDown(apiClient.close);
    await tester.pumpWidget(
      AuthScope(
        controller: controller,
        child: MaterialApp(
          home: MyMaintenanceRequestsScreen(
            maintenanceApiService: MaintenanceApiService(apiClient),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Create maintenance request'));
    await tester.pumpAndSettle();

    expect(find.text('No associated properties'), findsOneWidget);
    expect(find.text('Property ID'), findsNothing);
    expect(find.byType(CreateMaintenanceRequestScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'technician creates and submits a persisted estimate for review',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = fixtures.MemoryTokenStorage('token');
      final controller = fixtures.buildController(
        storage,
        role: UserRole.maintenanceTechnician,
      );
      await controller.restoreSession();
      addTearDown(controller.dispose);

      var requestStatus = 3;
      Map<String, dynamic>? estimate;
      var reviewSubmissionCount = 0;
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: storage,
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith(
            '/technician/11111111-1111-1111-1111-111111111112',
          )) {
            return http.Response(
              jsonEncode([
                _maintenanceRequest(
                  id: 'estimate-request',
                  title: 'Boiler repair',
                  status: requestStatus,
                ),
              ]),
              200,
            );
          }
          if (path.endsWith('/estimates/latest')) {
            return estimate == null
                ? http.Response('', 204)
                : http.Response(jsonEncode(estimate), 200);
          }
          if (path.endsWith('/estimates') && request.method == 'GET') {
            return http.Response(
              jsonEncode(estimate == null ? [] : [estimate]),
              200,
            );
          }
          if (path.endsWith('/estimates') && request.method == 'POST') {
            expect(
              request.url.queryParameters['technicianId'],
              '11111111-1111-1111-1111-111111111112',
            );
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['laborCost'], 100);
            expect(body['partsCost'], 20);
            expect(body['additionalCost'], 5);
            expect(body['notes'], 'Replace the valve.');
            estimate = _repairEstimate();
            requestStatus = 4;
            return http.Response(jsonEncode(estimate), 201);
          }
          if (path.endsWith('/estimates/estimate-1/submit-for-review')) {
            reviewSubmissionCount++;
            requestStatus = 5;
            return http.Response(
              jsonEncode(
                _maintenanceRequest(
                  id: 'estimate-request',
                  title: 'Boiler repair',
                  status: requestStatus,
                ),
              ),
              200,
            );
          }
          if (path.endsWith('/estimate-request')) {
            return http.Response(
              jsonEncode(
                _maintenanceRequest(
                  id: 'estimate-request',
                  title: 'Boiler repair',
                  status: requestStatus,
                ),
              ),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(apiClient.close);

      await tester.pumpWidget(
        AuthScope(
          controller: controller,
          child: MaterialApp(
            home: AssignedWorkScreen(
              maintenanceApiService: MaintenanceApiService(apiClient),
              technicianId: '11111111-1111-1111-1111-111111111112',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final createButton = find.byKey(
        const ValueKey('create-maintenance-estimate'),
      );
      expect(createButton, findsOneWidget);
      await tester.tap(createButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Labor cost'),
        '100',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Parts cost'),
        '20',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Additional cost'),
        '5',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes (optional)'),
        'Replace the valve.',
      );
      final saveButton = find.byKey(
        const ValueKey('save-maintenance-estimate'),
      );
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(reviewSubmissionCount, 0);
      expect(
        find.text(
          'Estimate created. Submit it for landlord review when ready.',
        ),
        findsOneWidget,
      );
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('LKR 125.00'), findsOneWidget);
      final submitButton = find.byKey(
        const ValueKey('submit-maintenance-estimate-for-review'),
      );
      expect(submitButton, findsOneWidget);
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      expect(reviewSubmissionCount, 1);
      expect(find.text('awaiting Landlord Approval'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('submit-maintenance-estimate-for-review')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('technician sees rejected estimate and review notes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(
      storage,
      role: UserRole.maintenanceTechnician,
    );
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final rejectedEstimate = _repairEstimate(
      status: 4,
      reviewNotes: 'Please use the approved supplier.',
    );
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith(
          '/technician/11111111-1111-1111-1111-111111111112',
        )) {
          return http.Response(
            jsonEncode([
              _maintenanceRequest(
                id: 'rejected-request',
                title: 'Replacement part',
                status: 7,
              ),
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/estimates/latest')) {
          return http.Response(jsonEncode(rejectedEstimate), 200);
        }
        if (request.url.path.endsWith('/estimates')) {
          return http.Response(jsonEncode([rejectedEstimate]), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(
      AuthScope(
        controller: controller,
        child: MaterialApp(
          home: AssignedWorkScreen(
            maintenanceApiService: MaintenanceApiService(apiClient),
            technicianId: '11111111-1111-1111-1111-111111111112',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rejected'), findsOneWidget);
    expect(
      find.text('Review notes: Please use the approved supplier.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('create-maintenance-estimate')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('start-maintenance-work')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _maintenanceRequest({
  required String id,
  required String title,
  required int status,
}) => {
  'id': id,
  'propertyId': 'property-1',
  'tenantId': 'tenant-1',
  'technicianId': '11111111-1111-1111-1111-111111111112',
  'title': title,
  'description': 'A clear issue description.',
  'category': 0,
  'priority': 1,
  'status': status,
  'tenantAccessNotes': 'Use the back door.',
  'triageNotes': null,
  'assignmentNotes': 'Visit during daytime.',
  'cancellationReason': null,
  'completedAt': null,
  'createdAt': '2026-09-17T08:15:00Z',
  'updatedAt': null,
};

Map<String, dynamic> _tenantProperty(String id, String title) => {
  'id': id,
  'landlordId': 'landlord-1',
  'title': title,
  'description': 'A tenant-associated rental property.',
  'address': '12 Garden Road',
  'city': 'Colombo',
  'monthlyRent': 85000,
  'bedrooms': 2,
  'bathrooms': 1,
  'isAvailable': false,
  'createdAt': '2026-09-17T08:15:00Z',
  'updatedAt': null,
  'amenities': <String>[],
};

Map<String, dynamic> _repairEstimate({
  int status = 1,
  int version = 1,
  String? reviewNotes,
}) => {
  'id': 'estimate-1',
  'maintenanceRequestId': 'estimate-request',
  'technicianId': '11111111-1111-1111-1111-111111111112',
  'versionNumber': version,
  'laborCost': 100,
  'partsCost': 20,
  'additionalCost': 5,
  'totalCost': 125,
  'notes': 'Replace the valve.',
  'status': status,
  'createdAt': '2026-09-19T08:15:00Z',
  'submittedAt': '2026-09-19T08:20:00Z',
  'reviewedAt': reviewNotes == null ? null : '2026-09-20T08:20:00Z',
  'reviewNotes': reviewNotes,
};
