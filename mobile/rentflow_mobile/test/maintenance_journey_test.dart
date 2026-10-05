import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/core/validation/phone_number.dart';
import 'package:rentflow_mobile/features/maintenance/models/maintenance_request.dart';
import 'package:rentflow_mobile/features/maintenance/models/maintenance_status_history.dart';
import 'package:rentflow_mobile/features/maintenance/widgets/maintenance_timeline.dart';

import 'maintenance_card_polish_test.dart' as fixture;

const channel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'event labels use the actual transition, including estimate revisions',
    () {
      final transitions = <(int?, int, String)>[
        (null, 0, 'Request submitted'),
        (0, 1, 'Request reviewed'),
        (1, 2, 'Technician assigned'),
        (2, 3, 'Estimate requested'),
        (3, 4, 'Estimate submitted'),
        (4, 5, 'Awaiting landlord approval'),
        (5, 6, 'Estimate approved'),
        (5, 7, 'Estimate rejected'),
        (5, 3, 'Estimate revision requested'),
        (6, 8, 'Work started'),
        (8, 9, 'Request completed'),
      ];
      for (final transition in transitions) {
        final event = MaintenanceStatusHistory(
          id: 'event',
          fromStatus: transition.$1 == null
              ? null
              : MaintenanceRequestStatus.fromJson(transition.$1),
          toStatus: MaintenanceRequestStatus.fromJson(transition.$2),
          changedAt: DateTime.utc(2026, 10, 3),
          notes: 'Internal note',
        );
        expect(maintenanceEventLabel(event), transition.$3);
      }
      expect(
        phoneDialerUri('+44 (20) 7123-4567').toString(),
        'tel:+442071234567',
      );
      for (final phone in [
        '',
        '12-----',
        '+94771234567;ext=1',
        '+94771234567?call=true',
      ]) {
        expect(phoneDialerUri(phone), isNull);
      }
      for (final manifest
          in Directory('android')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('AndroidManifest.xml'))) {
        expect(
          manifest.readAsStringSync(),
          isNot(contains('android.permission.CALL_PHONE')),
        );
      }
    },
  );

  testWidgets(
    'safe work contact launches the native dialer with accessible Call semantics',
    (tester) async {
      MethodCall? launched;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            launched = call;
            return true;
          });
      final semantics = tester.ensureSemantics();
      final request = fixture.detail()
        ..['assignedTechnicianContactPhone'] = '+94 77 123 4567';
      await fixture.mountTenant(tester, request);
      await tester.tap(
        find.byKey(const ValueKey('request-toggle-${fixture.requestId}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mike Reyes'), findsOneWidget);
      expect(find.text('MR'), findsOneWidget);
      expect(find.bySemanticsLabel('Call assigned technician'), findsOneWidget);
      semantics.dispose();
      final call = find.byKey(const ValueKey('call-assigned-technician'));
      await tester.ensureVisible(call);
      await tester.tap(call);
      await tester.pumpAndSettle();
      expect(launched?.method, 'launch');
      expect((launched?.arguments as Map)['url'], 'tel:+94771234567');
      expect((launched?.arguments as Map)['useWebView'], false);
      fixture.expectNoDatabaseIds();
    },
  );

  for (final phone in [null, '', 'invalid', '12-----']) {
    testWidgets(
      'no Call when the detail contract lacks a valid work number ($phone)',
      (tester) async {
        final request = fixture.detail()
          ..['assignedTechnicianContactPhone'] = phone;
        request['phoneNumber'] = '+94112223344';
        request['technicianEmail'] = 'private-tech@example.test';
        await fixture.mountTenant(tester, request);
        await tester.tap(
          find.byKey(const ValueKey('request-toggle-${fixture.requestId}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mike Reyes'), findsOneWidget);
        expect(find.text('Call'), findsNothing);
        expect(find.text('+94112223344'), findsNothing);
        expect(find.text('private-tech@example.test'), findsNothing);
        fixture.expectNoDatabaseIds();
      },
    );
  }

  testWidgets(
    'connected chronological journey distinguishes revisions and omits staff notes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1560));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await fixture.mountTenant(
        tester,
        fixture.detail(),
        history: [
          {
            'id': 'work',
            'fromStatus': 6,
            'toStatus': 8,
            'changedAt': '2026-10-04T12:00:00Z',
            'notes': 'Staff-only supplier information',
          },
          {
            'id': 'initial',
            'fromStatus': null,
            'toStatus': 0,
            'changedAt': '2026-10-03T09:00:00Z',
            'notes': 'Internal private contact',
          },
          {
            'id': 'revision',
            'fromStatus': 5,
            'toStatus': 3,
            'changedAt': '2026-10-04T10:00:00Z',
            'notes': null,
          },
        ],
      );
      await tester.tap(
        find.byKey(const ValueKey('request-toggle-${fixture.requestId}')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MaintenanceTimeline), findsOneWidget);
      expect(
        find.byKey(const ValueKey('timeline-connector-initial')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timeline-connector-revision')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timeline-connector-work')),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.text('Request submitted')).dy,
        lessThan(
          tester.getTopLeft(find.text('Estimate revision requested')).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('Estimate revision requested')).dy,
        lessThan(tester.getTopLeft(find.text('Work started')).dy),
      );
      expect(find.textContaining('Staff-only'), findsNothing);
      expect(find.textContaining('Internal private'), findsNothing);
      expect(find.textContaining('→'), findsNothing);
      expect(find.text('Parts ordered'), findsNothing);
      expect(find.text('On-site visit scheduled'), findsNothing);
      expect(find.text('DESCRIPTION'), findsNothing);
      expect(find.text('Preferred access'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final viewport in [
    (const Size(320, 800), 1.0),
    (const Size(720, 1560), 2.0),
    (const Size(1080, 2340), 3.0),
  ]) {
    testWidgets('expanded long journey fits $viewport with 200% text', (
      tester,
    ) async {
      tester.view.physicalSize = viewport.$1;
      tester.view.devicePixelRatio = viewport.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final request =
          fixture.detail(name: 'Alexandria María de Silva Wijesinghe')
            ..['assignedTechnicianContactPhone'] = '+94771234567'
            ..['referenceCode'] = 'MR-1234567890ABCDEF1234567890ABCDEF'
            ..['description'] =
                'The outlet near the bedroom doorway no longer supplies power. ' *
                8;
      await fixture.mountTenant(
        tester,
        request,
        scale: 2,
        history: [
          {
            'id': 'revision',
            'fromStatus': 5,
            'toStatus': 3,
            'changedAt': '2026-10-04T10:00:00Z',
            'notes': null,
          },
        ],
      );
      final toggle = find.byKey(
        const ValueKey('request-toggle-${fixture.requestId}'),
      );
      await tester.ensureVisible(toggle);
      await tester.tapAt(tester.getTopLeft(toggle) + const Offset(10, 10));
      await tester.pumpAndSettle();
      final name = find.text('Alexandria María de Silva Wijesinghe');
      await tester.ensureVisible(name);
      final call = find.byKey(const ValueKey('call-assigned-technician'));
      await tester.ensureVisible(call);
      expect(
        tester.getBottomLeft(name).dy,
        lessThanOrEqualTo(tester.getTopLeft(call).dy),
      );
      await tester.ensureVisible(find.text('Estimate revision requested'));
      expect(find.text('Estimate revision requested'), findsOneWidget);
      fixture.expectNoDatabaseIds();
      expect(tester.takeException(), isNull);
    });
  }
}
