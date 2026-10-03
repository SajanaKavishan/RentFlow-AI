import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/properties/screens/property_details_screen.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_photo.dart';
import 'package:rentflow_mobile/features/viewings/models/viewing.dart';
import 'package:rentflow_mobile/features/viewings/screens/my_viewings_screen.dart';
import 'package:rentflow_mobile/features/viewings/screens/tenant_viewing_details_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/features/viewings/widgets/viewing_page_header.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

const _id = '33333333-3333-4333-8333-333333333333';
const _propertyId = '22222222-2222-4222-8222-222222222222';
const _tenantId = '11111111-1111-4111-8111-111111111111';
final _now = DateTime.utc(2026, 10, 3, 4, 12);

class _Tokens implements TokenStorage {
  @override
  Future<void> deleteToken() async {}
  @override
  Future<String?> readToken() async => 'tenant-token';
  @override
  Future<void> saveToken(String value) async {}
}

Map<String, dynamic> _viewing(
  int status, {
  String? note = 'Please show me the outdoor space.',
  String? response,
  String requested = '2030-01-02T05:00:00Z',
  bool? canCancel,
}) => {
  'id': _id,
  'propertyId': _propertyId,
  'tenantId': _tenantId,
  'tenant': {'displayName': 'Private tenant', 'phoneNumber': '+94 77 123 4567'},
  'requestedDateTime': requested,
  'requestedLocalDate': '2030-01-02',
  'requestedDisplayTime': '10:30 AM',
  'timeZoneId': 'Asia/Colombo',
  'status': status,
  'canCancel':
      canCancel ??
      (status == 0
          ? DateTime.parse(requested).isAfter(_now)
          : status == 1 &&
                !DateTime.parse(
                  requested,
                ).subtract(const Duration(hours: 5)).isBefore(_now)),
  'cancellationDeadline': status == 1
      ? DateTime.parse(
          requested,
        ).subtract(const Duration(hours: 5)).toIso8601String()
      : null,
  'tenantMessage': note,
  'landlordResponse': response,
  'createdAt': '2026-09-01T00:00:00Z',
  'updatedAt': '2026-10-03T04:12:00Z',
};

Map<String, dynamic> _property({String? title}) => {
  'id': _propertyId,
  'landlordId': '44444444-4444-4444-8444-444444444444',
  'title': title ?? 'Harbour View Residence',
  'description': 'A home returned by the property API.',
  'address': 'Kureepoththa, Pothuhera',
  'city': 'Kurunegala',
  'monthlyRent': 100000,
  'bedrooms': 2,
  'bathrooms': 1,
  'isAvailable': true,
  'createdAt': '2026-09-01T00:00:00Z',
  'updatedAt': null,
  'amenities': <String>[],
};

http.Response _json(Object value) => http.Response(jsonEncode(value), 200);

http.Response _jsonError(String detail) => http.Response(
  jsonEncode({
    'status': 409,
    'title': 'Viewing request conflict.',
    'detail': detail,
  }),
  409,
);

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> viewing,
  bool list = false,
  double width = 390,
  double scale = 1,
  String? title,
  bool missingProperty = false,
  double bottomInset = 0,
  double topInset = 0,
  DateTime Function()? nowProvider,
  http.Response? Function(http.Request)? respond,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  final api = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: _Tokens(),
    httpClient: MockClient((request) async {
      final overridden = respond?.call(request);
      if (overridden != null) return overridden;
      final path = request.url.path;
      if (path == '/api/viewings') return _json([viewing]);
      if (path == '/api/viewings/$_id') return _json(viewing);
      if (path == '/api/properties/$_propertyId') {
        return missingProperty
            ? http.Response('{}', 404)
            : _json(_property(title: title));
      }
      if (path.endsWith('/images') || path.endsWith('/favorites')) {
        return _json([]);
      }
      return http.Response('{}', 404);
    }),
  );
  addTearDown(api.close);
  final service = ViewingApiService(api);
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
          ? MyViewingsScreen(viewingApiService: service)
          : TenantViewingDetailsScreen(
              viewingId: _id,
              viewingApiService: service,
              nowProvider: nowProvider ?? () => _now,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  const dialer = MethodChannel('plugins.flutter.io/url_launcher');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dialer, null);
  });

  test('eligibility and deadline parse; absent eligibility fails closed', () {
    final json = _viewing(1);
    final viewing = Viewing.fromJson(json);
    expect(viewing.canCancel, isTrue);
    expect(viewing.cancellationDeadline, DateTime.utc(2030, 1, 2));
    json.remove('canCancel');
    expect(Viewing.fromJson(json).canCancel, isFalse);
    expect(
      () => Viewing.fromJson({...json, 'canCancel': 'true'}),
      throwsFormatException,
    );
  });

  testWidgets(
    'Approved allowed cancellation has restrained action and helper',
    (tester) async {
      await _pump(tester, viewing: _viewing(1));
      await _reveal(tester, find.text('Cancel request'));
      expect(find.widgetWithText(TextButton, 'Cancel request'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Back to my viewings'),
        findsOneWidget,
      );
      expect(
        find.text('You can cancel up to 5 hours before the viewing.'),
        findsOneWidget,
      );
      expect(find.text('Need help with this viewing?'), findsNothing);
    },
  );

  testWidgets('server eligibility wins over the device clock', (tester) async {
    await _pump(tester, viewing: _viewing(1, canCancel: false));
    expect(find.text('Cancel request'), findsNothing);
    expect(find.text('Need help with this viewing?'), findsOneWidget);
  });

  testWidgets(
    'device clock ahead cannot close server eligibility or cause a refresh loop',
    (tester) async {
      var reads = 0;
      await _pump(
        tester,
        viewing: _viewing(
          1,
          requested: _now
              .add(const Duration(hours: 5))
              .subtract(const Duration(milliseconds: 1))
              .toIso8601String(),
          canCancel: true,
        ),
        respond: (request) {
          if (request.url.path == '/api/viewings/$_id') reads++;
          return null;
        },
      );
      expect(reads, 1);
      expect(find.text('Cancel request'), findsOneWidget);
      expect(find.text('Need help with this viewing?'), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Cancel request'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final contactResult in ['none', 'invalid', 'forbidden', 'unavailable']) {
    testWidgets(
      'Approved closed window with $contactResult contact shows truthful fallback',
      (tester) async {
        await _pump(
          tester,
          viewing: _viewing(1, canCancel: false),
          respond: (request) {
            if (request.url.path.endsWith('/landlord-contact')) {
              return switch (contactResult) {
                'none' => http.Response('', 204),
                'invalid' => _json({
                  'displayName': 'Landlord',
                  'phoneNumber': 'private-invalid',
                }),
                'forbidden' => http.Response('{}', 403),
                _ => http.Response('{}', 500),
              };
            }
            return null;
          },
        );
        await _reveal(tester, find.text('Need help with this viewing?'));
        expect(find.text('Cancel request'), findsNothing);
        expect(find.text('Call landlord'), findsNothing);
        expect(
          find.text(
            'Your cancellation window has closed. Please follow the viewing arrangements provided by the landlord.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('You can cancel up to 5 hours before the viewing.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dialerResult in ['success', 'false', 'exception']) {
    testWidgets(
      'closed window uses public contact and handles dialer $dialerResult',
      (tester) async {
        MethodCall? launched;
        var contactReads = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(dialer, (call) async {
              launched = call;
              if (dialerResult == 'exception') {
                throw PlatformException(code: 'no_dialer');
              }
              return dialerResult == 'success';
            });
        await _pump(
          tester,
          viewing: _viewing(1, canCancel: false),
          respond: (request) {
            if (request.url.path.endsWith('/landlord-contact')) {
              expect(request.headers['Authorization'], 'Bearer tenant-token');
              contactReads++;
              return _json({
                'displayName': 'Published landlord',
                'phoneNumber': '+94 77 765 4321',
              });
            }
            return null;
          },
        );
        expect(find.text('Cancel request'), findsNothing);
        expect(
          find.text(
            'Your cancellation window has closed. If your plans change, contact the landlord directly.',
          ),
          findsOneWidget,
        );
        await _reveal(tester, find.text('Call landlord'));
        await tester.tap(find.text('Call landlord'));
        await tester.pumpAndSettle();
        expect(contactReads, 2);
        expect(launched?.method, 'launch');
        expect((launched?.arguments as Map)['url'], 'tel:+94777654321');
        expect((launched?.arguments as Map)['useWebView'], isFalse);
        if (dialerResult != 'success') {
          expect(
            find.text('Calling is not available right now.'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'publication is rechecked before calling; withdrawn contact is never launched',
    (tester) async {
      var reads = 0;
      var launches = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(dialer, (call) async {
            launches++;
            return true;
          });
      await _pump(
        tester,
        viewing: _viewing(1, canCancel: false),
        respond: (request) {
          if (request.url.path.endsWith('/landlord-contact')) {
            reads++;
            return reads == 1
                ? _json({
                    'displayName': 'Landlord',
                    'phoneNumber': '+94 77 765 4321',
                  })
                : http.Response('', 204);
          }
          return null;
        },
      );
      await _reveal(tester, find.text('Call landlord'));
      await tester.tap(find.text('Call landlord'));
      await tester.pumpAndSettle();
      expect(launches, 0);
      expect(find.text('Call landlord'), findsNothing);
      expect(
        find.textContaining('Please follow the viewing arrangements'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Approved stale cancellation rejection refreshes help and contact',
    (tester) async {
      var closed = false;
      var reads = 0;
      await _pump(
        tester,
        viewing: _viewing(1),
        respond: (request) {
          if (request.url.path.endsWith('/cancel')) {
            closed = true;
            return _jsonError('Your cancellation window has closed.');
          }
          if (request.url.path == '/api/viewings/$_id') {
            reads++;
            return _json(_viewing(1, canCancel: !closed));
          }
          if (request.url.path.endsWith('/landlord-contact')) {
            return _json({
              'displayName': 'Landlord',
              'phoneNumber': '+94 77 765 4321',
            });
          }
          return null;
        },
      );
      await _reveal(tester, find.text('Cancel request'));
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel viewing'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.text('CANCELLED'), findsNothing);
      expect(find.text('Cancel request'), findsNothing);
      expect(find.text('Need help with this viewing?'), findsOneWidget);
      expect(find.text('Call landlord'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deadline timer refetches server eligibility just after inclusive boundary',
    (tester) async {
      final testStart = tester.binding.clock.now();
      DateTime now() =>
          _now.add(tester.binding.clock.now().difference(testStart));
      var closed = false;
      var reads = 0;
      await _pump(
        tester,
        viewing: _viewing(1),
        nowProvider: now,
        respond: (request) {
          if (request.url.path == '/api/viewings/$_id') {
            reads++;
            return _json(
              _viewing(
                1,
                requested: _now
                    .add(const Duration(hours: 5, seconds: 10))
                    .toIso8601String(),
                canCancel: !closed,
              ),
            );
          }
          return null;
        },
      );
      final remaining = _now.add(const Duration(seconds: 10)).difference(now());
      await tester.pump(remaining);
      expect(reads, 1);
      expect(find.text('Cancel request'), findsOneWidget);
      closed = true;
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Cancel request'), findsNothing);
      expect(find.text('Need help with this viewing?'), findsOneWidget);
    },
  );

  testWidgets(
    'closed help and public contact fit narrow large text with bottom safe area',
    (tester) async {
      await _pump(
        tester,
        viewing: _viewing(
          1,
          canCancel: false,
          response: List.filled(20, 'Please meet at the main gate.').join(' '),
        ),
        width: 320,
        scale: 2,
        bottomInset: 34,
        respond: (request) => request.url.path.endsWith('/landlord-contact')
            ? _json({
                'displayName': 'Landlord',
                'phoneNumber': '+94 77 765 4321',
              })
            : null,
      );
      expect(tester.takeException(), isNull);
      await _reveal(tester, find.text('Call landlord'));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.widgetWithText(OutlinedButton, 'Call landlord'))
            .bottom,
        lessThanOrEqualTo(800 - 34),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in ViewingStatus.values) {
    testWidgets('${status.name} card opens details by ID and returns to list', (
      tester,
    ) async {
      var detailReads = 0;
      var listReads = 0;
      await _pump(
        tester,
        viewing: _viewing(status.value),
        list: true,
        respond: (request) {
          if (request.url.path == '/api/viewings/$_id') detailReads++;
          if (request.url.path == '/api/viewings') listReads++;
          return null;
        },
      );
      await tester.tap(find.text('Harbour View Residence'));
      await tester.pumpAndSettle();
      expect(find.byType(TenantViewingDetailsScreen), findsOneWidget);
      expect(find.byType(PropertyDetailsScreen), findsNothing);
      expect(detailReads, 1);
      expect(find.text(status.name.toUpperCase()), findsOneWidget);
      await _reveal(tester, find.text('Back to my viewings'));
      await tester.tap(find.text('Back to my viewings'));
      await tester.pumpAndSettle();
      expect(find.byType(MyViewingsScreen), findsOneWidget);
      expect(find.byType(TenantViewingDetailsScreen), findsNothing);
      expect(listReads, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('property summary opens property and back refreshes viewing', (
    tester,
  ) async {
    var reads = 0;
    await _pump(
      tester,
      viewing: _viewing(0),
      list: true,
      respond: (request) {
        if (request.url.path == '/api/viewings/$_id') {
          reads++;
          return _json(_viewing(reads == 1 ? 0 : 1));
        }
        return null;
      },
    );
    await tester.tap(find.byTooltip('View viewing details'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('viewing-property-summary')));
    await tester.pumpAndSettle();
    expect(find.byType(PropertyDetailsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.byType(TenantViewingDetailsScreen), findsOneWidget);
    expect(find.text('Your viewing is confirmed'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MyViewingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Pending uses real note, date, response empty state and typography',
    (tester) async {
      await _pump(tester, viewing: _viewing(0));
      expect(find.text('MY VIEWINGS'), findsOneWidget);
      expect(find.text('Waiting for the landlord'), findsOneWidget);
      expect(find.text('Requested viewing'), findsOneWidget);
      expect(find.text('Wednesday, January 2, 2030'), findsOneWidget);
      expect(find.text('10:30 AM · Local property time'), findsOneWidget);
      expect(find.text('“Please show me the outdoor space.”'), findsOneWidget);
      expect(find.text('No response yet'), findsOneWidget);
      expect(find.text('Confirmed viewing'), findsNothing);
      expect(find.text('Kureepoththa, Pothuhera, Kurunegala'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Viewing details')).style?.fontSize,
        24,
      );
      expect(
        tester
            .widget<Text>(find.text('Waiting for the landlord'))
            .style
            ?.fontSize,
        18,
      );
      await _reveal(tester, find.text('Back to my viewings'));
      expect(find.text('Today at 9:42 AM'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
      for (final private in [
        _id,
        _propertyId,
        _tenantId,
        'Private tenant',
        '+94 77 123 4567',
      ]) {
        expect(find.text(private), findsNothing);
      }
      expect(find.byType(PropertyPhotoFallback), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Approved shows actual response and no pending copy', (
    tester,
  ) async {
    await _pump(
      tester,
      viewing: _viewing(1, response: 'Please meet me at the gate.'),
    );
    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('Your viewing is confirmed'), findsOneWidget);
    expect(find.text('Confirmed viewing'), findsOneWidget);
    expect(find.text('A message from your landlord'), findsNothing);
    expect(find.text('Please meet me at the gate.'), findsOneWidget);
    expect(find.text('No response yet'), findsNothing);
    expect(
      find.text('Keep this time in mind while you await a response.'),
      findsNothing,
    );
  });

  testWidgets('missing messages are truthful and old updates are not Today', (
    tester,
  ) async {
    await _pump(
      tester,
      viewing: {
        ..._viewing(1, note: '  '),
        'updatedAt': '2026-09-16T12:30:00Z',
      },
    );
    expect(find.text('Your note'), findsNothing);
    expect(find.text('SENT WITH YOUR REQUEST'), findsNothing);
    expect(
      find.text('The landlord has approved your request.'),
      findsOneWidget,
    );
    expect(find.text('No message provided'), findsOneWidget);
    expect(find.textContaining('See their message'), findsNothing);
    expect(find.text('Sep 16, 2026 at 6:00 PM'), findsOneWidget);
    expect(find.textContaining('Today at'), findsNothing);
  });

  for (final (status, title, heading) in [
    (2, 'Viewing request declined', 'Requested viewing'),
    (3, 'Viewing request cancelled', 'Requested viewing'),
    (4, 'Viewing completed', 'Viewing date'),
  ]) {
    testWidgets('$title renders its actual status without cancellation', (
      tester,
    ) async {
      await _pump(
        tester,
        viewing: _viewing(
          status,
          response: status == 2 ? 'I am unavailable that day.' : null,
        ),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.text(heading), findsOneWidget);
      expect(find.text('Cancel request'), findsNothing);
      if (status == 2) {
        expect(find.text('I am unavailable that day.'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'authoritative detail replaces stale list and refreshes on resume',
    (tester) async {
      var status = 1;
      var reads = 0;
      await _pump(
        tester,
        viewing: _viewing(0),
        list: true,
        respond: (request) {
          if (request.url.path == '/api/viewings/$_id') {
            reads++;
            return _json(_viewing(status));
          }
          return null;
        },
      );
      await tester.tap(find.text('Harbour View Residence'));
      await tester.pumpAndSettle();
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.text('PENDING'), findsNothing);
      status = 2;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('Cancel request'), findsNothing);
    },
  );

  testWidgets('legacy viewing time uses Colombo instead of device time', (
    tester,
  ) async {
    await _pump(
      tester,
      viewing: {
        ..._viewing(0),
        'requestedLocalDate': null,
        'requestedDisplayTime': null,
        'timeZoneId': null,
      },
    );
    expect(find.text('10:30 AM · Local property time'), findsOneWidget);
  });

  for (final status in [0, 1]) {
    for (final offset in status == 0 ? [-1, 0, 1] : [17999, 18000, 18001]) {
      testWidgets(
        'status $status cancellation at now + $offset seconds matches server',
        (tester) async {
          await _pump(
            tester,
            viewing: _viewing(
              status,
              requested: _now.add(Duration(seconds: offset)).toIso8601String(),
            ),
          );
          expect(
            find.text('Cancel request'),
            (status == 0 ? offset > 0 : offset >= 18000)
                ? findsOneWidget
                : findsNothing,
          );
        },
      );
    }
  }

  for (final cancellableStatus in [0, 1]) {
    testWidgets(
      'status $cancellableStatus cancellation applies authoritative result and removes action',
      (tester) async {
        var cancels = 0;
        await _pump(
          tester,
          viewing: _viewing(cancellableStatus),
          respond: (request) {
            if (request.url.path.endsWith('/cancel')) {
              expect(request.method, 'PATCH');
              cancels++;
              return _json(
                _viewing(3, response: 'An existing landlord message.'),
              );
            }
            return null;
          },
        );
        await _reveal(tester, find.text('Cancel request'));
        await tester.tap(find.text('Cancel request'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel viewing'));
        await tester.pumpAndSettle();
        expect(cancels, 1);
        expect(find.text('CANCELLED'), findsOneWidget);
        expect(find.text('Viewing request cancelled'), findsOneWidget);
        expect(find.text('An existing landlord message.'), findsOneWidget);
        expect(find.text('Cancel request'), findsNothing);
        expect(
          find.text('You can cancel before the viewing takes place.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancellation conflict refetches current status without optimism',
    (tester) async {
      var rejected = false;
      await _pump(
        tester,
        viewing: _viewing(0),
        respond: (request) {
          if (request.url.path.endsWith('/cancel')) {
            rejected = true;
            return http.Response(
              '{"message":"This viewing can no longer be cancelled."}',
              409,
            );
          }
          if (rejected && request.url.path == '/api/viewings/$_id') {
            return _json(_viewing(2));
          }
          return null;
        },
      );
      await _reveal(tester, find.text('Cancel request'));
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel viewing'));
      await tester.pumpAndSettle();
      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('CANCELLED'), findsNothing);
      expect(find.text('Cancel request'), findsNothing);
    },
  );

  testWidgets(
    'detail failure retries and missing property keeps viewing usable',
    (tester) async {
      var fail = true;
      await _pump(
        tester,
        viewing: _viewing(0),
        missingProperty: true,
        respond: (request) {
          if (fail && request.url.path == '/api/viewings/$_id') {
            return http.Response('{}', 500);
          }
          return null;
        },
      );
      expect(find.text('Could not load viewing'), findsOneWidget);
      expect(find.text('PENDING'), findsNothing);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('Property details unavailable'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('viewing-property-summary')));
      await tester.pumpAndSettle();
      expect(find.byType(PropertyDetailsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wrong detail identity is rejected', (tester) async {
    await _pump(tester, viewing: {..._viewing(0), 'id': 'another-viewing'});
    expect(find.text('Could not load viewing'), findsOneWidget);
    expect(find.text('PENDING'), findsNothing);
  });

  testWidgets(
    'summary requests primary image and uses fallback for missing URL',
    (tester) async {
      String? imagePath;
      await _pump(
        tester,
        viewing: _viewing(0),
        respond: (request) {
          if (request.url.path.endsWith('/images')) {
            return _json([
              {'id': 'other', 'isPrimary': false, 'sortOrder': 0},
              {'id': 'primary', 'isPrimary': true, 'sortOrder': 3},
            ]);
          }
          if (request.url.path.endsWith('/url')) {
            imagePath = request.url.path;
            return _json({'url': null});
          }
          return null;
        },
      );
      expect(imagePath, '/api/properties/$_propertyId/images/primary/url');
      expect(find.byType(PropertyPhotoFallback), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final status in ViewingStatus.values) {
        testWidgets(
          '${status.name} fits $width px at ${scale}x with long content',
          (tester) async {
            await _pump(
              tester,
              viewing: _viewing(
                status.value,
                note: List.filled(
                  10,
                  'Please show me the outdoor space and parking.',
                ).join(' '),
                response: List.filled(
                  10,
                  'Please meet at the main gate near the outdoor parking area.',
                ).join(' '),
              ),
              width: width,
              scale: scale,
              topInset: 32,
              title: List.filled(6, 'Harbour View Residence').join(' '),
            );
            expect(find.text('MY VIEWINGS'), findsOneWidget);
            expect(find.text('Viewing details'), findsOneWidget);
            final header = find.byType(ViewingPageHeader);
            final back = find.byTooltip('Back');
            expect(tester.getRect(header).top, greaterThanOrEqualTo(32));
            expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
            final button = tester.widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_back),
            );
            expect(
              button.style?.backgroundColor?.resolve({}),
              Colors.transparent,
            );
            expect(button.style?.side?.resolve({}), BorderSide.none);
            expect(button.style?.elevation?.resolve({}), 0);
            expect(
              tester.getRect(back).right,
              lessThan(tester.getRect(find.text('Viewing details')).left),
            );
            expect(tester.takeException(), isNull);
            await _reveal(tester, find.text('Back to my viewings'));
            expect(tester.takeException(), isNull);
            expect(
              MediaQuery.textScalerOf(
                tester.element(find.text('Back to my viewings')),
              ).scale(14),
              14 * scale,
            );
          },
        );
      }
    }
  }
}
