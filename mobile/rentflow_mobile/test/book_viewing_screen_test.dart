import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/properties/models/property.dart';
import 'package:rentflow_mobile/features/properties/services/property_api_service.dart';
import 'package:rentflow_mobile/features/properties/widgets/property_photo.dart';
import 'package:rentflow_mobile/features/viewings/screens/book_viewing_screen.dart';
import 'package:rentflow_mobile/features/viewings/screens/my_viewings_screen.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

class _Tokens implements TokenStorage {
  @override
  Future<void> deleteToken() async {}
  @override
  Future<String?> readToken() async => 'tenant-token';
  @override
  Future<void> saveToken(String value) async {}
}

class _ImageClient extends Fake implements HttpClient {
  Uri? requested;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested = url;
    return _ImageRequest();
  }
}

class _ImageRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _ImageResponse();
}

class _ImageResponse extends Fake implements HttpClientResponse {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==',
  );
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

const _id = '22222222-2222-4222-8222-222222222222';
const _instant = '2030-10-07T03:30:00Z';
final _property = Property.fromJson({
  'id': _id,
  'landlordId': '11111111-1111-4111-8111-111111111111',
  'title': 'Harbour View Residencies',
  'description': 'Home',
  'address': 'Marine Drive',
  'city': 'Colombo',
  'monthlyRent': 125000,
  'bedrooms': 2,
  'bathrooms': 1,
  'isAvailable': true,
  'availableFrom': '2035-01-01',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': null,
  'amenities': <String>[],
});
http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
http.Response _slots(
  http.Request request, {
  bool empty = false,
  String time = '9:00 AM',
}) => _json({
  'date': request.url.queryParameters['date'],
  'timeZoneId': 'Asia/Colombo',
  'slotDurationMinutes': 60,
  'state': empty ? 'empty' : 'available',
  'slots': empty
      ? []
      : [
          {
            'localTime': '09:00',
            'displayTime': time,
            'requestedDateTime': _instant,
          },
        ],
});
http.Response _created(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  return _json({
    'id': 'request-id',
    'tenantId': 'tenant-id',
    ...body,
    'status': 0,
    'landlordResponse': null,
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': null,
  }, 201);
}

Future<void> _pump(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  bool valid = true,
  double scale = 1,
  bool loadImages = false,
}) async {
  final client = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: _Tokens(),
    httpClient: MockClient((request) {
      if (!loadImages && request.url.path.endsWith('/images')) {
        return Future.value(_json([]));
      }
      return handler(request);
    }),
  );
  addTearDown(client.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: BookViewingScreen(
        propertyId: valid ? _id : '',
        property: valid ? _property : null,
        propertyApiService: PropertyApiService(client),
        viewingApiService: ViewingApiService(client),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _date(
  WidgetTester tester, {
  int offset = 1,
  bool settle = true,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final selected = today.add(Duration(days: offset));
  await tester.ensureVisible(
    find.byKey(const ValueKey('viewing-date-selector')),
  );
  await tester.tap(find.byKey(const ValueKey('viewing-date-selector')));
  await tester.pump(const Duration(milliseconds: 400));
  if (selected.month != today.month) {
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('${selected.day}').last);
  await tester.tap(find.text('OK'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _select(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('viewing-slot-09:00')));
  await tester.tap(find.byKey(const ValueKey('viewing-slot-09:00')));
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.pump();
  await tester.ensureVisible(find.byKey(const ValueKey('confirm-viewing')));
  await tester.tap(find.byKey(const ValueKey('confirm-viewing')));
  await tester.pump();
}

void main() {
  testWidgets(
    'selected property photo uses actual image metadata and resolved URL',
    (tester) async {
      final imageClient = _ImageClient();
      debugNetworkImageHttpClientProvider = () => imageClient;
      addTearDown(() {
        debugNetworkImageHttpClientProvider = null;
      });
      final paths = <String>[];
      await _pump(tester, (request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/images')) {
          return _json([
            {'id': 'image-id', 'isPrimary': true, 'sortOrder': 0},
          ]);
        }
        if (request.url.path.endsWith('/url')) {
          return _json({'url': 'https://images.example.test/home.png'});
        }
        throw StateError('Unexpected request');
      }, loadImages: true);
      expect(paths, contains('/api/properties/$_id/images'));
      expect(paths, contains('/api/properties/$_id/images/image-id/url'));
      expect(
        imageClient.requested.toString(),
        'https://images.example.test/home.png',
      );
      expect(
        find.byKey(const ValueKey('property-photo-image-id')),
        findsOneWidget,
      );
      debugNetworkImageHttpClientProvider = null;
    },
  );
  testWidgets('note input enforces 500 characters', (tester) async {
    await _pump(tester, (_) async => throw StateError('No viewing request'));
    await tester.enterText(
      find.byKey(const ValueKey('viewing-message')),
      List.filled(501, 'x').join(),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('viewing-message')))
          .controller!
          .text
          .length,
      500,
    );
  });
  for (final spec in [(320.0, 1.0), (390.0, 1.0), (430.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'compact booking fits ${spec.$1}px with text scale ${spec.$2}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(spec.$1, 800);
        addTearDown(tester.view.reset);
        await _pump(
          tester,
          (_) async => throw StateError('No viewing request expected'),
          scale: spec.$2,
        );
        expect(find.text('Harbour View Residencies'), findsWidgets);
        expect(find.text('Colombo'), findsWidgets);
        expect(find.text('Rs. 125,000 / month'), findsOneWidget);
        expect(find.byType(PropertyPhoto), findsOneWidget);
        expect(find.text(_id), findsNothing);
        expect(
          find.text('Choose a date to see viewing times.'),
          findsOneWidget,
        );
        expect(find.text('Request a viewing'), findsOneWidget);
        expect(
          find.text('Select your preferred date and time'),
          findsOneWidget,
        );
        expect(find.text('REQUEST A VIEWING'), findsNothing);
        expect(find.text('Choose a time'), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('confirm-viewing')),
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('confirm-viewing')),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('missing property cannot choose a date or submit', (
    tester,
  ) async {
    await _pump(
      tester,
      (_) async => throw StateError('No API request'),
      valid: false,
    );
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('viewing-date-selector')))
          .onTap,
      isNull,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('confirm-viewing')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('confirm-viewing')))
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'date picker fetches the selected calendar date and selection enables submission',
    (tester) async {
      http.Request? fetched;
      await _pump(tester, (request) async {
        fetched = request;
        return _slots(request);
      });
      await _date(tester);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(fetched!.url.path, '/api/properties/$_id/viewing-slots');
      expect(
        fetched!.url.queryParameters['date'],
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}',
      );
      expect(fetched!.headers['authorization'], 'Bearer tenant-token');
      expect(fetched!.url.queryParameters['includeUnavailable'], 'true');
      await _select(tester);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('viewing-slot-09:00')),
            )
            .selected,
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('confirm-viewing')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-viewing')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('viewing-message')),
        'Visit the home.',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-viewing')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('loading then empty state is truthful', (tester) async {
    final pending = Completer<http.Response>();
    http.Request? request;
    await _pump(tester, (value) {
      request = value;
      return pending.future;
    });
    await _date(tester, settle: false);
    expect(find.byKey(const ValueKey('viewing-slots-loading')), findsOneWidget);
    pending.complete(_slots(request!, empty: true));
    await tester.pumpAndSettle();
    expect(
      find.text('No viewing times are available on this date.'),
      findsOneWidget,
    );
  });
  testWidgets('error retry keeps the date and loads real slots', (
    tester,
  ) async {
    var calls = 0;
    await _pump(
      tester,
      (request) async => ++calls == 1
          ? _json({'detail': 'Temporary failure'}, 500)
          : _slots(request),
    );
    await _date(tester);
    expect(find.text('Viewing times could not be loaded.'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const ValueKey('viewing-slot-09:00')), findsOneWidget);
  });
  testWidgets(
    'date change clears selected slot and ignores an older response',
    (tester) async {
      final pending = Completer<http.Response>();
      http.Request? old;
      var calls = 0;
      await _pump(tester, (request) {
        calls++;
        if (calls == 1) {
          old = request;
          return pending.future;
        }
        return Future.value(_slots(request, time: '10:00 AM'));
      });
      await _date(tester, settle: false);
      await _date(tester, offset: 2);
      await _select(tester);
      pending.complete(_slots(old!));
      await tester.pumpAndSettle();
      expect(find.text('9:00 AM'), findsNothing);
      expect(find.text('10:00 AM'), findsWidgets);
      await _date(tester, offset: 3);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('viewing-slot-09:00')),
            )
            .selected,
        isFalse,
      );
    },
  );
  testWidgets(
    'exact server UTC instant and trimmed note are submitted once; success opens requests',
    (tester) async {
      final response = Completer<http.Response>();
      http.Request? posted;
      var posts = 0;
      await _pump(tester, (request) {
        if (request.method == 'POST') {
          posts++;
          posted = request;
          return response.future;
        }
        if (request.url.path == '/api/viewings') return Future.value(_json([]));
        return Future.value(_slots(request));
      });
      await _date(tester);
      await _select(tester);
      await tester.enterText(
        find.byKey(const ValueKey('viewing-message')),
        '  Please call first.  ',
      );
      await _submit(tester);
      await _submit(tester);
      expect(posts, 1);
      expect(find.text('Sending request...'), findsOneWidget);
      expect(find.text('Request sent'), findsNothing);
      final body = jsonDecode(posted!.body) as Map<String, dynamic>;
      expect(body['requestedDateTime'], _instant);
      expect(body['tenantMessage'], 'Please call first.');
      response.complete(_created(posted!));
      await tester.pumpAndSettle();
      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Viewing confirmed'), findsNothing);
      await tester.tap(find.text('View my requests'));
      await tester.pumpAndSettle();
      expect(find.byType(MyViewingsScreen), findsOneWidget);
    },
  );
  testWidgets(
    'required note rejects whitespace and allows a meaningful character with counter and summary',
    (tester) async {
      http.Request? posted;
      await _pump(tester, (request) async {
        if (request.method == 'POST') {
          posted = request;
          return _created(request);
        }
        return _slots(request);
      });
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('viewing-message')))
            .maxLength,
        500,
      );
      await _date(tester);
      await _select(tester);
      expect(find.text('0/500'), findsOneWidget);
      await _submit(tester);
      expect(posted, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('viewing-message')),
        '   ',
      );
      await tester.pump();
      expect(find.text('Add a note for the landlord.'), findsOneWidget);
      await _submit(tester);
      expect(posted, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('viewing-message')),
        'x',
      );
      await tester.pump();
      expect(find.text('1/500'), findsOneWidget);
      expect(find.text('Request summary'), findsOneWidget);
      expect(find.text('60 minutes'), findsOneWidget);
      expect(find.text('No message added'), findsNothing);
      expect(find.text('Send viewing request'), findsOneWidget);
      await _submit(tester);
      await tester.pumpAndSettle();
      expect((jsonDecode(posted!.body) as Map)['tenantMessage'], 'x');
    },
  );
  testWidgets(
    '409 refreshes slots while preserving the selected date and landlord note',
    (tester) async {
      var gets = 0;
      await _pump(tester, (request) async {
        if (request.method == 'POST') return _json({'detail': 'Conflict'}, 409);
        gets++;
        return _slots(request);
      });
      await _date(tester);
      await _select(tester);
      await tester.enterText(
        find.byKey(const ValueKey('viewing-message')),
        'Keep this note',
      );
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(gets, 2);
      expect(
        find.text(
          'That time is no longer available. Please choose another slot.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('viewing-message')))
            .controller!
            .text,
        'Keep this note',
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('viewing-slot-09:00')),
            )
            .selected,
        isFalse,
      );
      expect(find.text('Request sent'), findsNothing);
    },
  );
  testWidgets(
    'approved slot is disabled, labelled booked, and cannot be selected',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        (request) async => _json({
          'date': request.url.queryParameters['date'],
          'timeZoneId': 'Asia/Colombo',
          'slotDurationMinutes': 60,
          'state': 'available',
          'slots': [
            {
              'localTime': '09:00',
              'displayTime': '9:00 AM',
              'requestedDateTime': _instant,
              'isAvailable': true,
              'unavailableReason': null,
            },
            {
              'localTime': '10:00',
              'displayTime': '10:00 AM',
              'requestedDateTime': '2030-10-07T04:30:00Z',
              'isAvailable': false,
              'unavailableReason': 'ApprovedViewing',
            },
          ],
        }),
      );
      await _date(tester);
      final blocked = find.byKey(const ValueKey('viewing-slot-10:00'));
      await tester.ensureVisible(blocked);
      expect(tester.widget<ChoiceChip>(blocked).onSelected, isNull);
      expect(
        tester.widget<Text>(find.text('10:00 AM')).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.text('Booked'), findsOneWidget);
      await tester.tap(blocked);
      await tester.pump();
      expect(tester.widget<ChoiceChip>(blocked).selected, isFalse);
      await _select(tester);
      final selected = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('viewing-slot-09:00')),
      );
      expect(selected.selectedColor, AppPalette.darkOlive);
      expect(selected.labelStyle!.color, AppPalette.white);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('unconfigured schedule has one truthful instruction', (
    tester,
  ) async {
    await _pump(
      tester,
      (request) async => _json({
        'date': request.url.queryParameters['date'],
        'timeZoneId': 'Asia/Colombo',
        'slotDurationMinutes': 60,
        'state': 'unconfigured',
        'slots': [],
      }),
    );
    await _date(tester);
    expect(
      find.text(
        'Viewing times have not been configured for this property yet.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('No viewing times are available on this date.'),
      findsNothing,
    );
  });

  testWidgets(
    'emoji note validation and counter match the backend length limit',
    (tester) async {
      await _pump(tester, (request) async => _slots(request));
      await _date(tester);
      await _select(tester);
      final note = find.byKey(const ValueKey('viewing-message'));
      await tester.enterText(note, List.filled(251, '🙂').join());
      await tester.pump();
      expect(find.text('502/500'), findsOneWidget);
      expect(
        find.text('The note must not exceed 500 characters.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-viewing')))
            .onPressed,
        isNull,
      );
      await tester.enterText(note, List.filled(250, '🙂').join());
      await tester.pump();
      expect(find.text('500/500'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-viewing')))
            .onPressed,
        isNotNull,
      );
    },
  );

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('complete booking remains usable at 320px and ${scale}x text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 780);
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        (request) async =>
            request.method == 'POST' ? _created(request) : _slots(request),
        scale: scale,
      );
      await _date(tester);
      await _select(tester);
      await tester.enterText(
        find.byKey(const ValueKey('viewing-message')),
        'I would like to see the parking area.',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Request summary'));
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Request sent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
