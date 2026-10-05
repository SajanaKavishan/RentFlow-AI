import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/maintenance/screens/create_maintenance_request_screen.dart';
import 'package:rentflow_mobile/features/maintenance/screens/my_maintenance_requests_screen.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_photo_picker.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';
import 'package:rentflow_mobile/features/maintenance/widgets/tenant_maintenance_ui.dart';

import 'widget_test.dart' as fixtures;

Map<String, dynamic> requestJson(int status, {String? title}) => {
  'id': 'real-request-$status',
  'referenceCode':
      'MR-${status.toRadixString(16).toUpperCase().padLeft(16, '0')}',
  'propertyId': 'real-property',
  'tenantId': '11111111-1111-1111-1111-111111111112',
  'technicianId': null,
  'title': title ?? 'Request with status $status',
  'description': 'Water is dripping below the sink. ' * 15,
  'category': 0,
  'priority': 1,
  'status': status,
  'tenantAccessNotes': 'Please use the side entrance.',
  'createdAt': '2026-09-17T08:15:00Z',
  'updatedAt': null,
};

Future<void> mount(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  bool create = false,
  double scale = 1,
  double keyboard = 0,
  MaintenancePhotoPicker? photoPicker,
}) async {
  final storage = fixtures.MemoryTokenStorage('token');
  final auth = fixtures.buildController(storage, role: UserRole.tenant);
  await auth.restoreSession();
  addTearDown(auth.dispose);
  final client = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: storage,
    httpClient: MockClient(handler),
  );
  addTearDown(client.close);
  final service = MaintenanceApiService(client);
  await tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: create
            ? CreateMaintenanceRequestScreen(
                propertyId: 'real-property',
                maintenanceApiService: service,
                photoPicker: photoPicker,
              )
            : MyMaintenanceRequestsScreen(maintenanceApiService: service),
      ),
    ),
  );
}

Future<void> fillDraft(WidgetTester tester) async {
  final description = find.byKey(const ValueKey('maintenance-description'));
  await tester.ensureVisible(description);
  await tester.enterText(description, 'Water below the sink.');
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  final access = find.byKey(const ValueKey('access-morning'));
  await tester.ensureVisible(access);
  await tester.tap(access);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'overview uses compact same-row header, summary, filters and empty state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester, (_) async => http.Response('[]', 200));
      await tester.pumpAndSettle();

      final title = find.byKey(const ValueKey('maintenance-title'));
      final action = find.byKey(const ValueKey('new-maintenance-request'));
      final titleRect = tester.getRect(title);
      final actionRect = tester.getRect(action);
      expect(titleRect.left, 20);
      expect((titleRect.center.dy - actionRect.center.dy).abs(), lessThan(8));
      expect(actionRect.height, lessThanOrEqualTo(44));
      expect(actionRect.width, lessThan(160));

      final summaryRects = [
        for (final group in ['open', 'inProgress', 'resolved'])
          tester.getRect(find.byKey(ValueKey('summary-$group'))),
      ];
      expect(summaryRects.every((rect) => rect.height <= 90), isTrue);
      expect(summaryRects.map((rect) => rect.top).toSet(), hasLength(1));
      expect(find.text('Open'), findsNWidgets(2));
      expect(find.text('In progress'), findsNWidgets(2));
      expect(find.text('Resolved'), findsNWidgets(2));

      for (final group in ['all', 'open', 'inProgress', 'resolved']) {
        final chip = find.byKey(ValueKey('filter-$group'));
        expect(tester.getSize(chip).height, lessThanOrEqualTo(36));
      }
      expect(
        find.byKey(const ValueKey('maintenance-section-divider')),
        findsOneWidget,
      );
      expect(find.text('No maintenance requests yet.'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no-property rule keeps a compact dismissible RentFlow dialog', (
    tester,
  ) async {
    await mount(tester, (_) async => http.Response('[]', 200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-maintenance-request')));
    await tester.pumpAndSettle();

    expect(find.text('No associated properties'), findsOneWidget);
    expect(
      find.text(
        'An active lease for this property is required before you can submit a maintenance request.',
      ),
      findsOneWidget,
    );
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor, AppPalette.white);
    expect(dialog.surfaceTintColor, Colors.transparent);
    expect(dialog.shape, isA<RoundedRectangleBorder>());
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CreateMaintenanceRequestScreen), findsNothing);
  });

  testWidgets(
    'overview loads, derives counts, filters all domain statuses and expands real history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1560));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final loaded = Completer<http.Response>();
      var detailsCalls = 0;
      await mount(tester, (r) async {
        if (r.url.path.contains('/tenant/')) return loaded.future;
        if (r.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'history-record',
                'fromStatus': 0,
                'toStatus': 1,
                'changedAt': '2026-09-18T10:00:00Z',
                'notes': 'Real triage notes.',
              },
            ]),
            200,
          );
        }
        if (r.url.path.endsWith('/attachments')) {
          return http.Response('[]', 200);
        }
        detailsCalls++;
        return http.Response(jsonEncode(requestJson(0)), 200);
      });
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      loaded.complete(
        http.Response(
          jsonEncode([for (var i = 0; i <= 10; i++) requestJson(i)]),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('count-open')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('count-open'))).data,
        '7',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('count-inProgress')))
            .data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('count-resolved'))).data,
        '1',
      );
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.textContaining('Water is dripping'), findsNothing);
      expect(detailsCalls, 0);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('request-toggle-real-request-0')),
            )
            .height,
        lessThan(125),
      );
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('request-toggle-real-request-0')),
        ),
        isSemantics(hasExpandedState: true, isExpanded: false, isButton: true),
      );
      for (final group in [('open', 7), ('inProgress', 1), ('resolved', 1)]) {
        await tester.tap(find.byKey(ValueKey('filter-${group.$1}')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Request with status'),
          findsNWidgets(group.$2),
        );
        final chip = tester.widget<ChoiceChip>(
          find.byKey(ValueKey('filter-${group.$1}')),
        );
        expect(chip.selected, isTrue);
        expect(chip.selectedColor, AppPalette.darkOlive);
      }
      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request with status 0'));
      await tester.pumpAndSettle();
      expect(detailsCalls, 1);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('request-toggle-real-request-0')),
        ),
        isSemantics(hasExpandedState: true, isExpanded: true, isButton: true),
      );
      expect(find.textContaining('Water is dripping'), findsOneWidget);
      expect(find.text('DESCRIPTION'), findsNothing);
      expect(find.text('UPDATES'), findsOneWidget);
      expect(find.text('History'), findsNothing);
      expect(find.textContaining('Real triage notes.'), findsNothing);
      expect(find.text('ATTACHMENTS'), findsOneWidget);
      expect(find.text('No attachments yet.'), findsOneWidget);
      expect(find.text('Call'), findsNothing);
      expect(find.text('Parts ordered'), findsNothing);
      await tester.tap(find.text('Request with status 0'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Water is dripping'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'safe error retries into truthful empty and empty filter states',
    (tester) async {
      var loads = 0;
      await mount(tester, (_) async {
        loads++;
        return loads == 1
            ? http.Response('server error', 500)
            : http.Response('[]', 200);
      });
      await tester.pumpAndSettle();
      expect(find.text('Could not load maintenance requests'), findsOneWidget);
      expect(find.text('server error'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.text('No maintenance requests yet.'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('count-open'))).data,
        '0',
      );
    },
  );

  testWidgets('loaded filter with no matching requests is truthful', (
    tester,
  ) async {
    await mount(
      tester,
      (_) async => http.Response(jsonEncode([requestJson(7)]), 200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-resolved')));
    await tester.pumpAndSettle();
    expect(find.text('No requests in this filter.'), findsOneWidget);
    expect(find.text('Request with status 7'), findsNothing);
  });

  testWidgets(
    'form uses approved choices, duplicate protection, preserved failure draft and authoritative success',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1560));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<http.Response>();
      var submissions = 0;
      Map<String, dynamic>? body;
      final response = {
        ...requestJson(0, title: 'Authoritative API title'),
        'category': 1,
        'priority': 2,
        'preferredAccessWindow': 'Morning',
      };
      await mount(tester, (r) async {
        if (r.method != 'POST') {
          return http.Response(
            r.url.path.endsWith('/attachments') ? '[]' : jsonEncode(response),
            200,
          );
        }
        submissions++;
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return submissions == 1
            ? pending.future
            : http.Response(jsonEncode(response), 201);
      }, create: true);
      await tester.pumpAndSettle();
      for (final category in tenantCreateCategories) {
        expect(
          find.byKey(ValueKey('category-${category.name}')),
          findsOneWidget,
        );
      }
      for (final priority in tenantCreatePriorities) {
        expect(
          find.byKey(ValueKey('priority-${priority.name}')),
          findsOneWidget,
        );
      }
      expect(find.byKey(const ValueKey('priority-low')), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Title'), findsNothing);
      expect(find.text('Access notes (optional)'), findsNothing);
      expect(find.text('Add photos (optional)'), findsOneWidget);
      expect(find.text('Preferred access time'), findsOneWidget);
      final submit = find.byKey(const ValueKey('maintenance-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(submissions, 0);
      await fillDraft(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('category-electrical')),
      );
      await tester.tap(find.byKey(const ValueKey('category-electrical')));
      await tester.ensureVisible(find.byKey(const ValueKey('priority-high')));
      await tester.tap(find.byKey(const ValueKey('priority-high')));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Submitting request...'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(submissions, 1);
      expect(body, {
        'propertyId': 'real-property',
        'description': 'Water below the sink.',
        'category': 1,
        'priority': 2,
        'preferredAccessWindow': 'Morning',
      });
      pending.complete(http.Response('failed', 500));
      await tester.pumpAndSettle();
      expect(find.text('Request Submitted'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('maintenance-description')),
            )
            .controller!
            .text,
        'Water below the sink.',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(submissions, 2);
      expect(find.text('Request Submitted'), findsOneWidget);
      expect(find.text('Authoritative API title'), findsNothing);
      expect(find.text('real-request-0'), findsNothing);
      expect(find.text('REQUEST #MR-0000000000000000'), findsOneWidget);
      expect(find.text('Electrical'), findsOneWidget);
      expect(find.text('High Priority'), findsOneWidget);
      expect(find.text('Morning 8-12'), findsOneWidget);
      expect(find.textContaining('24 hours'), findsNothing);
      expect(find.text('real-property'), findsNothing);
      await tester.tap(find.text('New Request'));
      await tester.pumpAndSettle();
      expect(find.text('Request Submitted'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('maintenance-description')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('access-morning')))
            .selected,
        isFalse,
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final viewport in [
    (const Size(320, 800), 1.0),
    (const Size(720, 1560), 2.0),
    (const Size(1080, 2340), 3.0),
  ]) {
    final size = viewport.$1;
    final pixelRatio = viewport.$2;
    for (final scale in [1.0, 2.0]) {
      testWidgets('overview long content fits $size at $scale text scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = pixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final json = requestJson(
          5,
          title:
              'Very long maintenance title describing the kitchen sink and surrounding damage ' *
              3,
        );
        await mount(
          tester,
          (r) async => http.Response(
            r.url.path.contains('/tenant/')
                ? jsonEncode([json])
                : r.url.path.endsWith('/history') ||
                      r.url.path.endsWith('/attachments')
                ? '[]'
                : jsonEncode(json),
            200,
          ),
          scale: scale,
        );
        await tester.pumpAndSettle();
        if (scale == 1) {
          final titleRect = tester.getRect(
            find.byKey(const ValueKey('maintenance-title')),
          );
          final actionRect = tester.getRect(
            find.byKey(const ValueKey('new-maintenance-request')),
          );
          expect(
            (titleRect.center.dy - actionRect.center.dy).abs(),
            lessThan(8),
          );
        }
        final cardTitle = find.text(json['title'] as String);
        await tester.ensureVisible(cardTitle);
        await tester.tapAt(tester.getTopLeft(cardTitle) + const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text(json['description'] as String), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      testWidgets('create form fits $size at $scale text scale with keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = pixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(
          tester,
          (_) async => http.Response('{}', 500),
          create: true,
          scale: scale,
          keyboard: 260,
        );
        await tester.pumpAndSettle();
        await fillDraft(tester);
        await tester.ensureVisible(find.text('Submit Request'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
