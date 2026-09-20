import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/rental_applications/models/rental_application.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/landlord_rental_application_details_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/screens/landlord_rental_applications_screen.dart';
import 'package:rentflow_mobile/features/rental_applications/services/rental_application_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _Tokens implements TokenStorage {
  @override
  Future<String?> readToken() async => 'landlord-test-token';
  @override
  Future<void> saveToken(String value) async {}
  @override
  Future<void> deleteToken() async {}
}

const _property = '22222222-2222-4222-8222-222222222222';
const _tenant = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _application(int status) => {
  'id': '33333333-3333-4333-8333-33333333333$status',
  'propertyId': _property,
  'tenantId': _tenant,
  'moveInDate': '2026-12-01',
  'monthlyIncome': 2500,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': null,
  'status': status,
  'landlordResponse': status == 3 ? 'Please update your income proof.' : null,
  'createdAt': '2026-09-14T10:00:00Z',
  'submittedAt': status == 0 ? null : '2026-09-15T10:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> _run(int status, {bool summary = true}) => {
  'id': 'internal-workflow-id',
  'objective': 'internal orchestration objective',
  'steps': [
    {'toolName': 'private-tool', 'agentName': 'private-agent'},
  ],
  'status': status,
  'requiresHumanApproval': true,
  'createdAt': '2026-09-15T11:00:00Z',
  'updatedAt': '2026-09-15T11:05:00Z',
  'summary': summary
      ? {
          'applicationData': {
            'isValid': false,
            'missingFields': ['Occupation'],
            'warnings': ['Confirm the move-in date.'],
          },
          'documents': {
            'isValid': false,
            'presentDocumentTypes': ['IdentityDocument'],
            'missingDocumentTypes': ['IncomeProof'],
            'warnings': ['Employment evidence needs review.'],
          },
          'deterministicRules': {
            'passed': false,
            'passedRules': ['Move-in date provided'],
            'failedRules': ['Required income proof is missing.'],
            'warnings': ['Confirm the move-in date.'],
          },
        }
      : null,
};

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

Future<void> _pump(
  WidgetTester tester, {
  bool queue = false,
  String? propertyId = _property,
  int applicationStatus = 1,
  int validationStatus = 2,
  double width = 360,
  double scale = 1,
  Future<http.Response> Function(http.Request)? handler,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  final client = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: _Tokens(),
    httpClient: MockClient(
      handler ??
          (request) async {
            if (request.url.path.endsWith('/validation-runs')) {
              return _json([_run(validationStatus)]);
            }
            if (request.url.path.endsWith('/documents')) {
              return _json([
                {
                  'id': 'document-id',
                  'applicationId': _application(applicationStatus)['id'],
                  'documentType': 0,
                  'originalFileName':
                      'identity-document-with-a-long-file-name.pdf',
                  'contentType': 'application/pdf',
                  'fileSizeBytes': 2048,
                  'uploadedAt': '2026-09-15T10:00:00Z',
                },
              ]);
            }
            return _json([
              for (final status in [4, 3, 2, 1]) _application(status),
            ]);
          },
    ),
  );
  addTearDown(client.close);
  final service = RentalApplicationApiService(client);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: queue
          ? LandlordRentalApplicationsScreen(
              propertyId: propertyId,
              rentalApplicationApiService: service,
            )
          : LandlordRentalApplicationDetailsScreen(
              application: RentalApplication.fromJson(
                _application(applicationStatus),
              ),
              rentalApplicationApiService: service,
            ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _reveal(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    350,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('queue prioritizes active statuses at $width px', (
      tester,
    ) async {
      await _pump(tester, queue: true, width: width);
      expect(find.text('4 total · 2 ready for your decision'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text(_property), findsWidgets);
      expect(find.text(_tenant), findsWidgets);
      final positions = <double>[];
      for (final status in [
        'Submitted',
        'Under Review',
        'Changes Requested',
        'Approved',
      ]) {
        await _reveal(tester, status);
        positions.add(
          tester.getTopLeft(find.text(status)).dy +
              tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .pixels,
        );
        expect(tester.takeException(), isNull);
      }
      for (var index = 1; index < positions.length; index++) {
        expect(positions[index - 1], lessThan(positions[index]));
      }
      expect(find.text('Updated Not recorded'), findsWidgets);
    });

    testWidgets('details and findings fit $width px with enlarged text', (
      tester,
    ) async {
      await _pump(tester, width: width, scale: 1.3);
      expect(find.text(_property), findsOneWidget);
      expect(find.text(_tenant), findsOneWidget);
      for (final label in [
        'Created',
        'Submitted',
        'Updated',
        'Documents',
        'AI Findings',
        'Awaiting Human Review',
        'Missing required items',
        'Document: Income proof',
        'Deterministic checks',
        '1 passed · 1 failed',
        'Important warnings',
        'Document findings',
        'Present: Identity document',
        'Human Decision',
        'Approve',
      ]) {
        await _reveal(tester, label);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Request Changes'), findsOneWidget);
      expect(find.text('internal-workflow-id'), findsNothing);
      expect(find.textContaining('private-tool'), findsNothing);
      expect(find.textContaining('private-agent'), findsNothing);
      expect(find.textContaining('orchestration'), findsNothing);
    });
  }

  testWidgets(
    'missing property makes no request and shows integration pending',
    (tester) async {
      var requests = 0;
      await _pump(
        tester,
        queue: true,
        propertyId: null,
        handler: (_) async {
          requests++;
          return _json([]);
        },
      );
      expect(requests, 0);
      expect(find.text('Integration pending'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('queue loading, API error, retry and empty state', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var requests = 0;
    await _pump(
      tester,
      queue: true,
      settle: false,
      handler: (request) async {
        expect(request.headers['Authorization'], 'Bearer landlord-test-token');
        expect(request.url.path, endsWith('/property/$_property'));
        requests++;
        return requests == 1 ? pending.future : _json([]);
      },
    );
    expect(find.text('Loading applications'), findsOneWidget);
    pending.complete(_json({}, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('No rental applications'), findsOneWidget);
    expect(find.byTooltip('Refresh applications'), findsOneWidget);
  });

  for (final entry in {
    0: 'Pending',
    1: 'In progress',
    3: 'Completed',
    4: 'Failed',
  }.entries) {
    testWidgets(
      'validation displays ${entry.value} without inventing findings',
      (tester) async {
        await _pump(
          tester,
          handler: (request) async =>
              request.url.path.endsWith('/validation-runs')
              ? _json([_run(entry.key, summary: false)])
              : _json([]),
        );
        await _reveal(tester, entry.value);
        expect(
          find.text('Detailed findings are not available yet.'),
          findsOneWidget,
        );
        expect(find.text('Passed'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('validation refresh recovers from error and uses newest review', (
    tester,
  ) async {
    var requests = 0;
    await _pump(
      tester,
      handler: (request) async {
        if (!request.url.path.endsWith('/validation-runs')) return _json([]);
        requests++;
        if (requests == 1) return _json({'detail': 'private-tool failed'}, 400);
        if (requests == 2) return _json([]);
        return _json([
          {..._run(4), 'createdAt': '2026-09-14T11:00:00Z'},
          _run(2),
        ]);
      },
    );
    await _reveal(tester, 'Try again');
    expect(find.textContaining('private-tool'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No validation review available'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh AI findings'));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting Human Review'), findsOneWidget);
    expect(find.text('Failed'), findsNothing);
  });

  for (final status in [0, 3, 4, 5, 6]) {
    testWidgets('application status $status has no decision actions', (
      tester,
    ) async {
      await _pump(tester, applicationStatus: status);
      await _reveal(tester, 'Human Decision');
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Request Changes'), findsNothing);
      if (status == 3) {
        expect(find.text('Please update your income proof.'), findsOneWidget);
      }
    });
  }

  for (final requestingChanges in [true, false]) {
    testWidgets(
      '${requestingChanges ? 'changes' : 'rejection'} requires response and waits for API',
      (tester) async {
        final decision = Completer<http.Response>();
        final requests = <http.Request>[];
        await _pump(
          tester,
          handler: (request) async {
            if (request.method == 'PATCH') {
              requests.add(request);
              return decision.future;
            }
            return _json([]);
          },
        );
        final action = requestingChanges ? 'Request Changes' : 'Reject';
        final dialogAction = requestingChanges ? 'Request changes' : 'Reject';
        await _reveal(tester, action);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        final confirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, dialogAction),
        );
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(find.text('Enter a response for the tenant.'), findsOneWidget);
        expect(requests, isEmpty);
        await tester.enterText(
          find.byType(TextFormField),
          '  Please update the income evidence.  ',
        );
        await tester.tap(confirm);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(requests, hasLength(1));
        expect(
          requests.single.url.path,
          endsWith(requestingChanges ? '/request-changes' : '/reject'),
        );
        expect(
          jsonDecode(requests.single.body)['landlordResponse'],
          'Please update the income evidence.',
        );
        expect(find.text('Changes requested from the tenant.'), findsNothing);
        expect(find.text('Application rejected.'), findsNothing);
        decision.complete(
          _json({
            ..._application(requestingChanges ? 3 : 5),
            'id': _application(1)['id'],
            'landlordResponse': 'Please update the income evidence.',
          }),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            requestingChanges
                ? 'Changes requested from the tenant.'
                : 'Application rejected.',
          ),
          findsOneWidget,
        );
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Please update the income evidence.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'approval failure never shows success and leaves actions available',
    (tester) async {
      var decisions = 0;
      await _pump(
        tester,
        applicationStatus: 2,
        handler: (request) async {
          if (request.method == 'PATCH') {
            decisions++;
            return _json({}, 500);
          }
          return _json([]);
        },
      );
      await _reveal(tester, 'Approve');
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(decisions, 0);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Approve'),
        ),
      );
      await tester.pumpAndSettle();
      expect(decisions, 1);
      expect(find.text('Application approved.'), findsNothing);
      expect(find.text('Approve'), findsOneWidget);
      expect(
        find.text('The rental application request failed. Please try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('document summary retries independently of AI findings', (
    tester,
  ) async {
    var documentRequests = 0;
    var validationRequests = 0;
    await _pump(
      tester,
      handler: (request) async {
        if (request.url.path.endsWith('/documents')) {
          documentRequests++;
          return documentRequests == 1 ? _json({}, 500) : _json([]);
        }
        validationRequests++;
        return _json([_run(2)]);
      },
    );
    await _reveal(tester, 'Try again');
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await _reveal(tester, 'No documents uploaded');
    expect(find.text('No documents uploaded'), findsOneWidget);
    expect(documentRequests, 2);
    expect(validationRequests, 1);
    expect(tester.takeException(), isNull);
  });

  for (final validResponse in [true, false]) {
    testWidgets(
      'approval ${validResponse ? 'succeeds after response' : 'rejects empty success body'}',
      (tester) async {
        final decision = Completer<http.Response>();
        await _pump(
          tester,
          handler: (request) async {
            if (request.method == 'PATCH') {
              expect(request.url.path, endsWith('/approve'));
              expect(jsonDecode(request.body), {
                'status': 4,
                'landlordResponse': null,
              });
              return decision.future;
            }
            return _json([]);
          },
        );
        await _reveal(tester, 'Approve');
        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Approve'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Application approved.'), findsNothing);
        decision.complete(
          validResponse
              ? _json({..._application(4), 'id': _application(1)['id']})
              : http.Response('', 200),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Application approved.'),
          validResponse ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Approve'),
          validResponse ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
