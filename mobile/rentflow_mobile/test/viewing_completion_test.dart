import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/viewings/models/viewing.dart';
import 'package:rentflow_mobile/features/viewings/screens/landlord_viewing_request_details_screen.dart';
import 'package:rentflow_mobile/features/viewings/screens/landlord_viewing_requests_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

const _id = '33333333-3333-4333-8333-333333333333';
const _propertyId = '22222222-2222-4222-8222-222222222222';
const _tenantId = '11111111-1111-4111-8111-111111111111';
const _phone = '+94 77 123 4567';
final _now = DateTime.utc(2030, 1, 2, 5);
final _end = DateTime.utc(2030, 1, 2, 5, 30);
final _completeButton = find.byKey(const ValueKey('complete-viewing-request'));

class _Tokens implements TokenStorage {
  @override
  Future<void> deleteToken() async {}
  @override
  Future<String?> readToken() async => 'landlord-token';
  @override
  Future<void> saveToken(String value) async {}
}

Map<String, dynamic> _viewing({
  int status = 1,
  bool eligible = true,
  DateTime? end,
  String? name,
  String propertyId = _propertyId,
}) => {
  'id': _id,
  'propertyId': propertyId,
  'tenantId': _tenantId,
  'tenant': {
    'displayName': name ?? 'Chamodya Sayanjali',
    'phoneNumber': status == 1 ? _phone : null,
  },
  'requestedDateTime': '2030-01-02T04:30:00Z',
  'requestedLocalDate': '2030-01-02',
  'requestedDisplayTime': '10:00 AM',
  'timeZoneId': 'Asia/Colombo',
  'durationMinutes': 60,
  'status': status,
  'canMarkCompleted': eligible,
  'completionEligibleAt': status == 1 ? (end ?? _end).toIso8601String() : null,
  'tenantMessage': 'Please show me the outdoor space.',
  'landlordResponse': 'The scheduled viewing is confirmed.',
  'createdAt': '2029-12-30T00:00:00Z',
  'updatedAt': status == 4 ? '2030-01-02T05:30:00Z' : null,
};

http.Response _json(Object value) => http.Response(jsonEncode(value), 200);

ApiClient _client(Future<http.Response> Function(http.Request) respond) {
  final api = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: _Tokens(),
    httpClient: MockClient(respond),
  );
  addTearDown(api.close);
  return api;
}

Future<void> _pump(
  WidgetTester tester, {
  required Future<http.Response> Function(http.Request) respond,
  Map<String, dynamic>? initial,
  double width = 390,
  double scale = 1,
  double topInset = 0,
  double bottomInset = 0,
  DateTime Function()? nowProvider,
  bool list = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 850);
  addTearDown(tester.view.reset);
  final service = ViewingApiService(_client(respond));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
        ),
        child: child!,
      ),
      home: list
          ? LandlordViewingRequestsScreen(
              propertyId: _propertyId,
              viewingApiService: service,
            )
          : LandlordViewingRequestDetailsScreen(
              viewing: Viewing.fromJson(initial ?? _viewing()),
              viewingApiService: service,
              nowProvider: nowProvider ?? () => _now,
            ),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpAndSettle();
}

Future<void> _openConfirmation(WidgetTester tester) async {
  await tester.ensureVisible(_completeButton);
  await tester.tap(_completeButton);
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await _openConfirmation(tester);
  await tester.tap(find.text('Confirm completed'));
  await tester.pump();
}

void main() {
  for (final eligible in [true, false]) {
    test('model parses completion permission $eligible and UTC end', () {
      final viewing = Viewing.fromJson(_viewing(eligible: eligible));
      expect(viewing.canMarkCompleted, eligible);
      expect(viewing.completionEligibleAt, _end);
      expect(viewing.completionEligibleAt!.isUtc, isTrue);
    });
  }

  test('older or null completion fields fail closed', () {
    final json = _viewing()
      ..remove('canMarkCompleted')
      ..remove('completionEligibleAt');
    expect(Viewing.fromJson(json).canMarkCompleted, isFalse);
    expect(Viewing.fromJson(json).completionEligibleAt, isNull);
    expect(
      Viewing.fromJson({...json, 'canMarkCompleted': null}).canMarkCompleted,
      isFalse,
    );
  });

  test('model parses offset end as the same absolute instant', () {
    expect(
      Viewing.fromJson({
        ..._viewing(),
        'completionEligibleAt': '2030-01-02T11:00:00+05:30',
      }).completionEligibleAt,
      _end,
    );
  });

  test('malformed eligibility values are rejected safely', () {
    expect(
      () => Viewing.fromJson({..._viewing(), 'canMarkCompleted': 'true'}),
      throwsFormatException,
    );
    expect(
      () =>
          Viewing.fromJson({..._viewing(), 'completionEligibleAt': 'invalid'}),
      throwsFormatException,
    );
  });

  test(
    'complete service sends only JWT-owned PATCH and parses authoritative state',
    () async {
      final service = ViewingApiService(
        _client((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/viewings/$_id/complete');
          expect(request.url.queryParameters, isEmpty);
          expect(request.body, isEmpty);
          expect(request.headers['Authorization'], 'Bearer landlord-token');
          return _json(_viewing(status: 4, eligible: false));
        }),
      );
      final result = await service.completeViewing(id: _id);
      expect(result.status, ViewingStatus.completed);
      expect(result.updatedAt, _end);
      expect(result.tenantId, _tenantId);
      expect(result.propertyId, _propertyId);
    },
  );

  for (final body in ['', jsonEncode(_viewing()), '{invalid']) {
    test(
      'complete service refuses unconfirmed or malformed response $body',
      () async {
        final service = ViewingApiService(
          _client((_) async => http.Response(body, 200)),
        );
        await expectLater(
          service.completeViewing(id: _id),
          throwsA(isA<ViewingApiException>()),
        );
      },
    );
  }

  test('complete service preserves conflict status for recovery', () async {
    final service = ViewingApiService(
      _client(
        (_) async => http.Response(
          jsonEncode({
            'detail': 'Only approved viewings may be changed to Completed.',
          }),
          409,
        ),
      ),
    );
    await expectLater(
      service.completeViewing(id: _id),
      throwsA(
        isA<ViewingApiException>().having((e) => e.statusCode, 'status', 409),
      ),
    );
  });

  testWidgets(
    'Approved before end hides action and shows property-local helper',
    (tester) async {
      final json = _viewing(eligible: false);
      await _pump(tester, initial: json, respond: (_) async => _json(json));
      expect(_completeButton, findsNothing);
      expect(find.text('Viewing completion'), findsOneWidget);
      expect(
        find.text(
          'You can mark this viewing as completed after the scheduled viewing ends.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('11:00 AM (Asia/Colombo)'), findsOneWidget);
    },
  );

  testWidgets(
    'server permission controls action even when device clock is before end',
    (tester) async {
      await _pump(tester, respond: (_) async => _json(_viewing()));
      expect(_now.isBefore(_end), isTrue);
      expect(_completeButton, findsOneWidget);
      expect(find.text('Viewing completion'), findsNothing);
    },
  );

  testWidgets('cancelling confirmation never sends PATCH', (tester) async {
    var patches = 0;
    await _pump(
      tester,
      respond: (request) async {
        if (request.method == 'PATCH') patches++;
        return _json(_viewing());
      },
    );
    await _openConfirmation(tester);
    expect(find.text('Mark viewing completed?'), findsOneWidget);
    expect(
      find.text(
        'Confirm that the tenant attended this viewing and the viewing has finished.',
      ),
      findsOneWidget,
    );
    expect(patches, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(patches, 0);
    expect(_completeButton, findsOneWidget);
  });

  testWidgets(
    'confirmation sends one PATCH, blocks duplicate taps and waits for server',
    (tester) async {
      var patches = 0;
      final response = Completer<http.Response>();
      await _pump(
        tester,
        respond: (request) async {
          if (request.method == 'PATCH') {
            patches++;
            return response.future;
          }
          return _json(_viewing());
        },
      );
      await _confirm(tester);
      await tester.pump();
      expect(patches, 1);
      expect(find.text('Completing...'), findsOneWidget);
      expect(tester.widget<FilledButton>(_completeButton).onPressed, isNull);
      expect(find.text('Viewing completed'), findsNothing);
      await tester.tap(_completeButton);
      await tester.pump();
      expect(patches, 1);
      response.complete(_json(_viewing(status: 4, eligible: false)));
      await tester.pumpAndSettle();
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Viewing completed'), findsOneWidget);
      expect(
        find.text('This viewing has been marked as completed.'),
        findsOneWidget,
      );
      expect(_completeButton, findsNothing);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text(_phone), findsNothing);
      expect(find.text('Call tenant'), findsNothing);
      expect(find.text('Chamodya Sayanjali'), findsOneWidget);
      expect(find.text('Please show me the outdoor space.'), findsOneWidget);
      expect(find.text('The scheduled viewing is confirmed.'), findsOneWidget);
      expect(find.byType(LandlordViewingRequestDetailsScreen), findsOneWidget);
    },
  );

  for (final failure in ['network', 'server', 'wrong-resource']) {
    testWidgets(
      '$failure completion failure preserves Approved without fake success',
      (tester) async {
        await _pump(
          tester,
          respond: (request) async {
            if (request.method == 'GET') return _json(_viewing());
            if (failure == 'network') throw http.ClientException('offline');
            if (failure == 'wrong-resource') {
              return _json({..._viewing(status: 4), 'id': 'other-viewing'});
            }
            return http.Response('{}', 500);
          },
        );
        await _confirm(tester);
        await tester.pumpAndSettle();
        expect(find.text('Approved'), findsOneWidget);
        expect(find.text('Viewing completed'), findsNothing);
        expect(
          find.text('Could not update the viewing. Please try again.'),
          findsWidgets,
        );
        expect(_completeButton, findsOneWidget);
      },
    );
  }

  for (final completed in [true, false]) {
    testWidgets(
      '409 refetch resolves to ${completed ? 'Completed' : 'ineligible Approved'}',
      (tester) async {
        var gets = 0;
        await _pump(
          tester,
          respond: (request) async {
            if (request.method == 'PATCH') return http.Response('{}', 409);
            gets++;
            return _json(
              gets == 1
                  ? _viewing()
                  : _viewing(status: completed ? 4 : 1, eligible: false),
            );
          },
        );
        await _confirm(tester);
        await tester.pumpAndSettle();
        expect(gets, 2);
        expect(_completeButton, findsNothing);
        expect(
          find.byKey(const ValueKey('viewing-action-error')),
          findsNothing,
        );
        expect(
          find.text(completed ? 'Viewing completed' : 'Viewing completion'),
          findsOneWidget,
        );
        expect(find.text('Viewing marked as completed.'), findsNothing);
      },
    );
  }

  testWidgets(
    'failed conflict refetch preserves status and hides stale permission',
    (tester) async {
      var gets = 0;
      await _pump(
        tester,
        respond: (request) async {
          if (request.method == 'PATCH') return http.Response('{}', 409);
          return ++gets == 1 ? _json(_viewing()) : http.Response('{}', 500);
        },
      );
      await _confirm(tester);
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);
      expect(_completeButton, findsNothing);
      expect(
        find.text('Could not update the viewing. Please try again.'),
        findsWidgets,
      );
    },
  );

  for (final serverEligible in [true, false]) {
    testWidgets(
      'one-shot end timer refetches and obeys server eligibility $serverEligible',
      (tester) async {
        var gets = 0;
        final end = _now.add(const Duration(seconds: 2));
        await _pump(
          tester,
          initial: _viewing(eligible: false, end: end),
          respond: (request) async {
            expect(request.method, 'GET');
            gets++;
            return _json(
              _viewing(eligible: gets > 1 && serverEligible, end: end),
            );
          },
        );
        expect(gets, 1);
        expect(_completeButton, findsNothing);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(gets, 2);
        expect(_completeButton, serverEligible ? findsOneWidget : findsNothing);
        await tester.pump(const Duration(minutes: 5));
        await tester.pumpAndSettle();
        expect(gets, 2);
      },
    );
  }

  testWidgets('disposing details cancels the eligibility timer', (
    tester,
  ) async {
    var gets = 0;
    final json = _viewing(
      eligible: false,
      end: _now.add(const Duration(seconds: 2)),
    );
    await _pump(
      tester,
      initial: json,
      respond: (_) async {
        gets++;
        return _json(json);
      },
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(gets, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app resume refetches eligibility after background time passes', (
    tester,
  ) async {
    var gets = 0;
    final json = _viewing(eligible: false);
    await _pump(
      tester,
      initial: json,
      respond: (_) async {
        gets++;
        return _json(gets == 1 ? json : _viewing());
      },
    );
    expect(_completeButton, findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gets, 2);
    expect(_completeButton, findsOneWidget);
  });

  for (final status in [0, 2, 3, 4]) {
    testWidgets(
      'status $status never offers completion even with a true flag',
      (tester) async {
        final json = _viewing(status: status);
        await _pump(tester, initial: json, respond: (_) async => _json(json));
        expect(_completeButton, findsNothing);
        expect(find.text('Viewing completion'), findsNothing);
        if (status == 4) {
          expect(find.text('Viewing completed'), findsOneWidget);
          expect(find.text('Approve'), findsNothing);
          expect(find.text('Reject'), findsNothing);
        }
      },
    );
  }

  testWidgets('returning from completed details refreshes landlord list', (
    tester,
  ) async {
    var completed = false;
    var lists = 0;
    await _pump(
      tester,
      list: true,
      respond: (request) async {
        if (request.url.path.endsWith('/property/$_propertyId')) {
          lists++;
          return _json([
            _viewing(status: completed ? 4 : 1, eligible: !completed),
          ]);
        }
        if (request.method == 'PATCH') completed = true;
        return _json(_viewing(status: completed ? 4 : 1, eligible: !completed));
      },
    );
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    await _confirm(tester);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(lists, 2);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
  });

  for (final status in [1, 4]) {
    testWidgets(
      'status $status fits 320px, long identity and 2x text with safe areas',
      (tester) async {
        final json = _viewing(
          status: status,
          name:
              'Chamodya Sayanjali with a very long family name that must wrap',
          propertyId:
              'A very long property reference for Harbour View Residence near the outdoor garden',
        );
        await _pump(
          tester,
          initial: json,
          width: 320,
          scale: 2,
          topInset: 28,
          bottomInset: 34,
          respond: (_) async => _json(json),
        );
        expect(tester.takeException(), isNull);
        if (status == 1) {
          await _openConfirmation(tester);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (status == 1) {
          final rect = tester.getRect(_completeButton);
          expect(rect.bottom, lessThanOrEqualTo(850 - 34));
        }
      },
    );
  }

  testWidgets('Completed list card fits 320px and 2x text', (tester) async {
    await _pump(
      tester,
      list: true,
      width: 320,
      scale: 2,
      respond: (_) async => _json([
        _viewing(
          status: 4,
          name: 'Chamodya Sayanjali with a very long family name',
        ),
      ]),
    );
    await tester.scrollUntilVisible(find.text('Completed'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
