import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/maintenance/models/maintenance_request.dart';
import 'package:rentflow_mobile/features/maintenance/models/repair_estimate.dart';
import 'package:rentflow_mobile/features/maintenance/screens/assigned_work_screen.dart';
import 'package:rentflow_mobile/features/maintenance/screens/create_maintenance_request_screen.dart';
import 'package:rentflow_mobile/features/maintenance/screens/landlord_maintenance_screen.dart';
import 'package:rentflow_mobile/features/maintenance/screens/my_maintenance_requests_screen.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';
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
          if (request.url.path.endsWith('/request-1')) {
            return http.Response(jsonEncode(requests[0]), 200);
          }
          if (request.url.path.endsWith('/request-2')) {
            return http.Response(jsonEncode(requests[1]), 200);
          }
          if (request.url.path.endsWith('/history')) {
            return http.Response('[]', 200);
          }
          if (request.url.path.endsWith('/estimates/latest')) {
            return http.Response(
              jsonEncode(
                _repairEstimate(status: RepairEstimateStatus.approved.value),
              ),
              200,
            );
          }
          if (request.url.path.endsWith('/estimates')) {
            return http.Response(
              jsonEncode([
                _repairEstimate(status: RepairEstimateStatus.approved.value),
              ]),
              200,
            );
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
      expect(find.text('A clear issue description.'), findsOneWidget);
      expect(find.text('Approved request · approved'), findsOneWidget);
      await tester.tap(find.text('Approved request · approved'));
      await tester.pumpAndSettle();
      final startWorkButton = find.byKey(
        const ValueKey('start-maintenance-work'),
      );
      await tester.ensureVisible(startWorkButton);
      await tester.tap(startWorkButton);
      await tester.pumpAndSettle();
      expect(find.text('Start work?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('confirm-start-maintenance-work')),
      );
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
      expect(find.text('Complete work?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('confirm-complete-maintenance-work')),
      );
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

  testWidgets('landlord requests revision for a submitted estimate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var requestStatus = MaintenanceRequestStatus.awaitingLandlordApproval.value;
    var estimateStatus = RepairEstimateStatus.submitted.value;
    String? submittedReviewNotes;
    final request = _maintenanceRequest(
      id: 'landlord-request',
      title: 'Kitchen sink leak',
      status: requestStatus,
    );
    final estimate = _repairEstimate()
      ..['maintenanceRequestId'] = 'landlord-request';
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: fixtures.MemoryTokenStorage('token'),
      httpClient: MockClient((httpRequest) async {
        final path = httpRequest.url.path;
        if (path == '/api/properties') {
          return http.Response(
            jsonEncode([
              _landlordProperty(
                'property-1',
                'Owned property',
                landlordId: '11111111-1111-1111-1111-111111111112',
              ),
            ]),
            200,
          );
        }
        if (path.endsWith('/property/property-1')) {
          return http.Response(jsonEncode([request]), 200);
        }
        if (path.endsWith('/landlord-request')) {
          request['status'] = requestStatus;
          return http.Response(jsonEncode(request), 200);
        }
        if (path.endsWith('/history')) {
          return http.Response('[]', 200);
        }
        if (path.endsWith('/estimates/latest')) {
          estimate['status'] = estimateStatus;
          estimate['reviewNotes'] = submittedReviewNotes;
          return http.Response(jsonEncode(estimate), 200);
        }
        if (path.endsWith('/request-revision')) {
          expect(httpRequest.method, 'PATCH');
          final body = jsonDecode(httpRequest.body) as Map<String, dynamic>;
          submittedReviewNotes = body['reviewNotes'] as String?;
          requestStatus = MaintenanceRequestStatus.estimatePending.value;
          estimateStatus = RepairEstimateStatus.revisionRequested.value;
          estimate
            ..['status'] = estimateStatus
            ..['reviewNotes'] = submittedReviewNotes
            ..['reviewedAt'] = '2026-09-20T08:20:00Z';
          return http.Response(jsonEncode(estimate), 200);
        }
        return http.Response('', 404);
      }),
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LandlordMaintenanceScreen(
          landlordId: '11111111-1111-1111-1111-111111111112',
          propertyApiService: PropertyApiService(apiClient),
          maintenanceApiService: MaintenanceApiService(apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen sink leak'));
    await tester.pumpAndSettle();

    expect(find.text('Repair Estimate'), findsOneWidget);
    expect(find.text('LKR 125.00'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approve-repair-estimate')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reject-repair-estimate')),
      findsOneWidget,
    );
    final revisionButton = find.byKey(
      const ValueKey('request-estimate-revision'),
    );
    await tester.scrollUntilVisible(
      revisionButton,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(revisionButton);
    await tester.pumpAndSettle();

    final confirm = find.widgetWithText(FilledButton, 'Request Revision');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Review notes are required.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('estimate-review-notes')),
      'Please include the replacement valve cost.',
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(submittedReviewNotes, 'Please include the replacement valve cost.');
    expect(find.text('Revision Requested'), findsOneWidget);
    expect(find.byKey(const ValueKey('approve-repair-estimate')), findsNothing);
    expect(find.byKey(const ValueKey('reject-repair-estimate')), findsNothing);
    expect(
      find.byKey(const ValueKey('request-estimate-revision')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

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
          if (request.url.path.endsWith('/created-request')) {
            return http.Response(jsonEncode(createdRequest), 200);
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
              title: 'Leaking kitchen tap',
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
      expect(find.byType(SimpleDialog), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('maintenance-property-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garden apartment'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('maintenance-description')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-description')),
        'Water is dripping under the kitchen sink.',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('access-morning')));
      await tester.tap(find.byKey(const ValueKey('access-morning')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit Request'));
      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      expect(find.text('Request Submitted'), findsOneWidget);
      await tester.tap(find.text('Track Request'));
      await tester.pumpAndSettle();
      expect(submittedPropertyId, 'property-occupied-b');
      expect(find.text('Leaking kitchen tap'), findsOneWidget);
      expect(find.byType(CreateMaintenanceRequestScreen), findsNothing);
      expect(find.text('A clear issue description.'), findsOneWidget);
      expect(find.text('DESCRIPTION'), findsOneWidget);
      expect(find.text('UPDATES'), findsNothing);
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
    'technician creates a revised estimate after landlord requests changes',
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
      Map<String, dynamic> latestEstimate = _repairEstimate(
        status: 2,
        reviewNotes: 'Please include the replacement valve cost.',
      );
      var createCount = 0;
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
                  id: 'revision-request',
                  title: 'Boiler repair',
                  status: requestStatus,
                ),
              ]),
              200,
            );
          }
          if (path.endsWith('/estimates/latest')) {
            return http.Response(jsonEncode(latestEstimate), 200);
          }
          if (path.endsWith('/estimates') && request.method == 'GET') {
            return http.Response(jsonEncode([latestEstimate]), 200);
          }
          if (path.endsWith('/estimates') && request.method == 'POST') {
            createCount++;
            latestEstimate = {
              ..._repairEstimate(status: 1, version: 2),
              'id': 'estimate-2',
              'maintenanceRequestId': 'revision-request',
            };
            requestStatus = 4;
            return http.Response(jsonEncode(latestEstimate), 201);
          }
          if (path.endsWith('/estimates/estimate-2/submit-for-review')) {
            reviewSubmissionCount++;
            requestStatus = 5;
            return http.Response(
              jsonEncode(
                _maintenanceRequest(
                  id: 'revision-request',
                  title: 'Boiler repair',
                  status: requestStatus,
                ),
              ),
              200,
            );
          }
          if (path.endsWith('/revision-request')) {
            return http.Response(
              jsonEncode(
                _maintenanceRequest(
                  id: 'revision-request',
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

      expect(find.text('Revision requested by landlord'), findsOneWidget);
      expect(
        find.text(
          'Requested changes: Please include the replacement valve cost.',
        ),
        findsOneWidget,
      );
      final createButton = find.byKey(
        const ValueKey('create-maintenance-estimate'),
      );
      expect(createButton, findsOneWidget);
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      for (final field in [
        ('Labor cost', '130'),
        ('Parts cost', '45'),
        ('Additional cost', '0'),
      ]) {
        await tester.enterText(
          find.widgetWithText(TextFormField, field.$1),
          field.$2,
        );
      }
      final saveButton = find.byKey(
        const ValueKey('save-maintenance-estimate'),
      );
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(createCount, 1);
      expect(reviewSubmissionCount, 0);
      expect(
        find.byKey(const ValueKey('create-maintenance-estimate')),
        findsNothing,
      );
      final submitButton = find.byKey(
        const ValueKey('submit-maintenance-estimate-for-review'),
      );
      expect(submitButton, findsOneWidget);
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(reviewSubmissionCount, 1);
      expect(find.text('awaiting Landlord Approval'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
      final saveButton = find.byKey(
        const ValueKey('save-maintenance-estimate'),
      );
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Enter a valid currency amount with up to two decimal places.',
        ),
        findsNWidgets(3),
      );
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
        if (request.url.path.endsWith('/rejected-request')) {
          return http.Response(
            jsonEncode(
              _maintenanceRequest(
                id: 'rejected-request',
                title: 'Replacement part',
                status: 7,
              ),
            ),
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

  testWidgets('tenant opens a request and sees its status history', (
    tester,
  ) async {
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(storage, role: UserRole.tenant);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final request = _maintenanceRequest(
      id: 'history-request',
      title: 'Kitchen sink leak',
      status: 1,
    );
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((httpRequest) async {
        if (httpRequest.url.path.endsWith(
          '/tenant/11111111-1111-1111-1111-111111111112',
        )) {
          return http.Response(jsonEncode([request]), 200);
        }
        if (httpRequest.url.path.endsWith('/history-request')) {
          return http.Response(jsonEncode(request), 200);
        }
        if (httpRequest.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'history-1',
                'fromStatus': 0,
                'toStatus': 1,
                'changedByUserId': null,
                'changedAt': '2026-09-18T10:00:00Z',
                'notes': 'Request triaged.',
              },
            ]),
            200,
          );
        }
        if (httpRequest.url.path.endsWith('/attachments')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'attachment-1',
                'maintenanceRequestId': 'history-request',
                'fileName': 'leak-photo.jpg',
                'contentType': 'image/jpeg',
                'fileSize': 2048,
                'attachmentType': 'damage photo',
                'uploadedByUserId': '11111111-1111-1111-1111-111111111112',
                'createdAt': '2026-09-18T10:00:00Z',
              },
            ]),
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
          home: MyMaintenanceRequestsScreen(
            maintenanceApiService: MaintenanceApiService(apiClient),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen sink leak'));
    await tester.pumpAndSettle();

    expect(find.text('UPDATES'), findsOneWidget);
    expect(find.textContaining('Submitted → Triaged'), findsOneWidget);
    expect(find.textContaining('Request triaged.'), findsOneWidget);
    expect(find.text('leak-photo.jpg'), findsOneWidget);
    expect(find.textContaining('image/jpeg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('technician sees assigned request status history', (
    tester,
  ) async {
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(
      storage,
      role: UserRole.maintenanceTechnician,
    );
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final request = _maintenanceRequest(
      id: 'technician-history-request',
      title: 'Broken tap',
      status: 2,
    );
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((httpRequest) async {
        if (httpRequest.url.path.endsWith('/technician/technician-1')) {
          return http.Response(jsonEncode([request]), 200);
        }
        if (httpRequest.url.path.endsWith('/technician-history-request')) {
          return http.Response(jsonEncode(request), 200);
        }
        if (httpRequest.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'technician-history-1',
                'fromStatus': 1,
                'toStatus': 2,
                'changedByUserId': null,
                'changedAt': '2026-09-18T10:00:00Z',
                'notes': 'Assigned to technician.',
              },
            ]),
            200,
          );
        }
        if (httpRequest.url.path.endsWith('/estimates')) {
          return http.Response('[]', 200);
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
            requestId: 'technician-history-request',
            technicianId: 'technician-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Status history'), findsOneWidget);
    expect(find.textContaining('triaged → assigned'), findsOneWidget);
    expect(find.textContaining('Assigned to technician.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('technician attachment section reflects backend access policy', (
    tester,
  ) async {
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(
      storage,
      role: UserRole.maintenanceTechnician,
    );
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final request = _maintenanceRequest(
      id: 'technician-attachment-request',
      title: 'Leaking pipe',
      status: 2,
    );
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((httpRequest) async {
        if (httpRequest.url.path.endsWith('/technician-attachment-request')) {
          return http.Response(jsonEncode(request), 200);
        }
        if (httpRequest.url.path.endsWith('/history') ||
            httpRequest.url.path.endsWith('/estimates')) {
          return http.Response('[]', 200);
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
            requestId: 'technician-attachment-request',
            technicianId: 'technician-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attachments'), findsOneWidget);
    expect(
      find.text('Attachments are currently available to tenants only.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Delete attachment'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landlord maintenance navigation loads owned property requests', (
    tester,
  ) async {
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(
      storage,
      role: UserRole.landlord,
    );
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final requestPaths = <String>[];
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/properties') {
          return http.Response(
            jsonEncode([
              _landlordProperty(
                'property-1',
                'Owned property',
                landlordId: '11111111-1111-1111-1111-111111111112',
              ),
              _landlordProperty(
                'property-2',
                'Second owned property',
                landlordId: '11111111-1111-1111-1111-111111111112',
              ),
              _landlordProperty(
                'property-other',
                'Other property',
                landlordId: 'another-landlord',
              ),
            ]),
            200,
          );
        }
        if (request.url.path.contains('/maintenance-requests/property/')) {
          requestPaths.add(request.url.path);
          if (request.url.path.endsWith('/property-2')) {
            return http.Response('[]', 200);
          }
          return http.Response(
            jsonEncode([
              _maintenanceRequest(
                id: 'landlord-request',
                title: 'Kitchen sink leak',
                status: 0,
              )..['propertyId'] = 'property-1',
            ]),
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
          home: SharedAppShell(
            user: CurrentUser.fromJson(fixtures.userJson(UserRole.landlord)),
            propertyApiService: PropertyApiService(apiClient),
            maintenanceApiService: MaintenanceApiService(apiClient),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is NavigationDestination && widget.label == 'Maintenance',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Landlord Maintenance'), findsOneWidget);
    expect(find.text('Owned property'), findsOneWidget);
    expect(find.text('Kitchen sink leak'), findsOneWidget);
    expect(requestPaths, ['/api/maintenance-requests/property/property-1']);
    await tester.tap(
      find.byKey(const ValueKey('landlord-maintenance-property')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second owned property').last);
    await tester.pumpAndSettle();

    expect(find.text('No maintenance requests'), findsOneWidget);
    expect(requestPaths, [
      '/api/maintenance-requests/property/property-1',
      '/api/maintenance-requests/property/property-2',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landlord property selector handles long names without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: fixtures.MemoryTokenStorage('token'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/properties') {
          return http.Response(
            jsonEncode([
              _landlordProperty(
                'property-1',
                'A very long property name that should remain usable in the selector',
                landlordId: '11111111-1111-1111-1111-111111111112',
              ),
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LandlordMaintenanceScreen(
          landlordId: '11111111-1111-1111-1111-111111111112',
          propertyApiService: PropertyApiService(apiClient),
          maintenanceApiService: MaintenanceApiService(apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'A very long property name that should remain usable in the selector',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('landlord opens a request detail with history and identifiers', (
    tester,
  ) async {
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(
      storage,
      role: UserRole.landlord,
    );
    await controller.restoreSession();
    addTearDown(controller.dispose);

    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/properties') {
          return http.Response(
            jsonEncode([
              _landlordProperty(
                'property-1',
                'Owned property',
                landlordId: '11111111-1111-1111-1111-111111111112',
              ),
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'landlord-history-1',
                'fromStatus': 0,
                'toStatus': 1,
                'changedAt': '2026-09-18T10:00:00Z',
                'notes': 'Triage completed.',
              },
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/landlord-request')) {
          final detail = _maintenanceRequest(
            id: 'landlord-request',
            title: 'Kitchen sink leak',
            status: 1,
          )..['propertyId'] = 'property-1';
          return http.Response(jsonEncode(detail), 200);
        }
        if (request.url.path.endsWith('/property/property-1')) {
          return http.Response(
            jsonEncode([
              _maintenanceRequest(
                id: 'landlord-request',
                title: 'Kitchen sink leak',
                status: 1,
              )..['propertyId'] = 'property-1',
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      }),
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LandlordMaintenanceScreen(
          landlordId: '11111111-1111-1111-1111-111111111112',
          propertyApiService: PropertyApiService(apiClient),
          maintenanceApiService: MaintenanceApiService(apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen sink leak'));
    await tester.pumpAndSettle();

    expect(find.text('A clear issue description.'), findsOneWidget);
    expect(find.text('Tenant ID'), findsOneWidget);
    expect(find.text('tenant-1'), findsOneWidget);
    expect(find.text('Technician ID'), findsOneWidget);
    expect(find.textContaining('Submitted → Triaged'), findsOneWidget);
    expect(find.textContaining('Triage completed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'submitted landlord request shows controls and submits triage to the API',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = fixtures.MemoryTokenStorage('token');
      final controller = fixtures.buildController(
        storage,
        role: UserRole.landlord,
      );
      await controller.restoreSession();
      addTearDown(controller.dispose);

      Map<String, dynamic>? triageBody;
      var triageCalls = 0;
      final request = _maintenanceRequest(
        id: 'landlord-request',
        title: 'Kitchen sink leak',
        status: 0,
      )..['propertyId'] = 'property-1';
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: storage,
        httpClient: MockClient((httpRequest) async {
          if (httpRequest.url.path == '/api/properties') {
            return http.Response(
              jsonEncode([
                _landlordProperty(
                  'property-1',
                  'Owned property',
                  landlordId: '11111111-1111-1111-1111-111111111112',
                ),
              ]),
              200,
            );
          }
          if (httpRequest.url.path.endsWith('/triage')) {
            triageCalls++;
            expect(httpRequest.method, 'PATCH');
            triageBody = jsonDecode(httpRequest.body) as Map<String, dynamic>;
            request
              ..['category'] = triageBody!['category']
              ..['priority'] = triageBody!['priority']
              ..['triageNotes'] = triageBody!['triageNotes']
              ..['status'] = 1;
            return http.Response(jsonEncode(request), 200);
          }
          if (httpRequest.url.path.endsWith('/history')) {
            return http.Response('[]', 200);
          }
          if (httpRequest.url.path.endsWith('/landlord-request')) {
            return http.Response(jsonEncode(request), 200);
          }
          if (httpRequest.url.path.endsWith('/property/property-1')) {
            return http.Response(jsonEncode([request]), 200);
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(apiClient.close);

      await tester.pumpWidget(
        MaterialApp(
          home: LandlordMaintenanceScreen(
            landlordId: '11111111-1111-1111-1111-111111111112',
            propertyApiService: PropertyApiService(apiClient),
            maintenanceApiService: MaintenanceApiService(apiClient),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen sink leak'));
      await tester.pumpAndSettle();

      expect(find.text('Triage Request'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('landlord-triage-category')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('landlord-triage-priority')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('landlord-triage-notes')),
        findsOneWidget,
      );
      expect(find.text('Submit Triage'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final categoryDropdown = find.byKey(
        const ValueKey('landlord-triage-category'),
      );
      await tester.ensureVisible(categoryDropdown);
      await tester.tap(categoryDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Electrical').last);
      await tester.pumpAndSettle();
      final priorityDropdown = find.byKey(
        const ValueKey('landlord-triage-priority'),
      );
      await tester.ensureVisible(priorityDropdown);
      await tester.tap(priorityDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emergency').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('landlord-triage-notes')),
        'Shut off the water supply immediately.',
      );
      final submit = find.byKey(const ValueKey('submit-landlord-triage'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(triageBody, {
        'category': 1,
        'priority': 3,
        'triageNotes': 'Shut off the water supply immediately.',
      });
      expect(triageCalls, 1);
      expect(find.text('Triage Request'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('successful landlord triage refreshes list detail and history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(
      storage,
      role: UserRole.landlord,
    );
    await controller.restoreSession();
    addTearDown(controller.dispose);

    var listLoads = 0;
    var detailLoads = 0;
    var historyLoads = 0;
    final request = _maintenanceRequest(
      id: 'landlord-request',
      title: 'Kitchen sink leak',
      status: 0,
    )..['propertyId'] = 'property-1';
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((httpRequest) async {
        if (httpRequest.url.path == '/api/properties') {
          return http.Response(
            jsonEncode([
              _landlordProperty(
                'property-1',
                'Owned property',
                landlordId: '11111111-1111-1111-1111-111111111112',
              ),
            ]),
            200,
          );
        }
        if (httpRequest.url.path.endsWith('/triage')) {
          request['status'] = 1;
          request['triageNotes'] = 'Plumber scheduled.';
          return http.Response(jsonEncode(request), 200);
        }
        if (httpRequest.url.path.endsWith('/history')) {
          historyLoads++;
          return http.Response(
            jsonEncode(
              request['status'] == 0
                  ? []
                  : [
                      {
                        'id': 'landlord-history-1',
                        'fromStatus': 0,
                        'toStatus': 1,
                        'changedAt': '2026-09-18T10:00:00Z',
                        'notes': 'Plumber scheduled.',
                      },
                    ],
            ),
            200,
          );
        }
        if (httpRequest.url.path.endsWith('/landlord-request')) {
          detailLoads++;
          return http.Response(jsonEncode(request), 200);
        }
        if (httpRequest.url.path.endsWith('/property/property-1')) {
          listLoads++;
          return http.Response(jsonEncode([request]), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LandlordMaintenanceScreen(
          landlordId: '11111111-1111-1111-1111-111111111112',
          propertyApiService: PropertyApiService(apiClient),
          maintenanceApiService: MaintenanceApiService(apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen sink leak'));
    await tester.pumpAndSettle();
    expect(find.text('Triage Request'), findsOneWidget);

    final submit = find.byKey(const ValueKey('submit-landlord-triage'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(listLoads, 2);
    expect(detailLoads, 2);
    expect(historyLoads, 2);
    expect(find.text('Triage Request'), findsNothing);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Triaged'), findsOneWidget);
    expect(find.textContaining('Plumber scheduled.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landlord assigns a technician and requests an estimate', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = fixtures.MemoryTokenStorage('token');
    final controller = fixtures.buildController(
      storage,
      role: UserRole.landlord,
    );
    await controller.restoreSession();
    addTearDown(controller.dispose);

    var listLoads = 0;
    var detailLoads = 0;
    var historyLoads = 0;
    final request =
        _maintenanceRequest(
            id: 'landlord-request',
            title: 'Kitchen sink leak',
            status: 1,
          )
          ..['technicianId'] = null
          ..['assignmentNotes'] = null;
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      tokenStorage: storage,
      httpClient: MockClient((httpRequest) async {
        if (httpRequest.url.path == '/api/properties') {
          return http.Response(
            jsonEncode([
              _landlordProperty(
                'property-1',
                'Owned property',
                landlordId: '11111111-1111-1111-1111-111111111112',
              ),
            ]),
            200,
          );
        }
        if (httpRequest.url.path == '/api/maintenance-requests/technicians') {
          return http.Response(
            jsonEncode([
              {'id': 'technician-1', 'name': 'Ari Technician'},
            ]),
            200,
          );
        }
        if (httpRequest.url.path.endsWith('/assign-technician')) {
          expect(httpRequest.method, 'PATCH');
          expect(jsonDecode(httpRequest.body), {
            'technicianId': 'technician-1',
            'assignmentNotes': 'Call before arrival.',
          });
          request
            ..['technicianId'] = 'technician-1'
            ..['assignmentNotes'] = 'Call before arrival.'
            ..['status'] = 2;
          return http.Response(jsonEncode(request), 200);
        }
        if (httpRequest.url.path.endsWith('/estimate-pending')) {
          expect(httpRequest.method, 'PATCH');
          expect(httpRequest.body, isEmpty);
          request['status'] = 3;
          return http.Response(jsonEncode(request), 200);
        }
        if (httpRequest.url.path.endsWith('/history')) {
          historyLoads++;
          return http.Response('[]', 200);
        }
        if (httpRequest.url.path.endsWith('/landlord-request')) {
          detailLoads++;
          return http.Response(jsonEncode(request), 200);
        }
        if (httpRequest.url.path.endsWith('/property/property-1')) {
          listLoads++;
          return http.Response(jsonEncode([request]), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    addTearDown(apiClient.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LandlordMaintenanceScreen(
          landlordId: '11111111-1111-1111-1111-111111111112',
          propertyApiService: PropertyApiService(apiClient),
          maintenanceApiService: MaintenanceApiService(apiClient),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen sink leak'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('assign-maintenance-technician')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('landlord-technician-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ari Technician').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('landlord-assignment-notes')),
      'Call before arrival.',
    );
    final assign = find.byKey(const ValueKey('assign-maintenance-technician'));
    await tester.ensureVisible(assign);
    await tester.tap(assign);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign').last);
    await tester.pumpAndSettle();

    expect(find.text('Estimate workflow'), findsOneWidget);
    final requestEstimate = find.byKey(
      const ValueKey('request-maintenance-estimate'),
    );
    await tester.ensureVisible(requestEstimate);
    await tester.tap(requestEstimate);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request estimate').last);
    await tester.pumpAndSettle();

    expect(find.text('Assigned'), findsNothing);
    expect(find.text('Estimate Pending'), findsOneWidget);
    expect(listLoads, 3);
    expect(detailLoads, 3);
    expect(historyLoads, 3);
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

Map<String, dynamic> _landlordProperty(
  String id,
  String title, {
  required String landlordId,
}) => {..._tenantProperty(id, title), 'landlordId': landlordId};

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
