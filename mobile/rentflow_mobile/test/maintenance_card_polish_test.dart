import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/maintenance/screens/assigned_work_screen.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'tenant_maintenance_redesign_test.dart' as tenant;
import 'widget_test.dart' as fixtures;

const requestId = '11efbe01-9196-44b6-b1b2-73767fae5cf1';
const propertyId = '21efbe01-9196-44b6-b1b2-73767fae5cf1';
const tenantId = '31efbe01-9196-44b6-b1b2-73767fae5cf1';
const technicianId = '41efbe01-9196-44b6-b1b2-73767fae5cf1';
const reference = 'MR-C8070B6D94F6A810';

Map<String, dynamic> detail({String? name = 'Mike Reyes'}) => {
  ...tenant.requestJson(8, title: 'Bedroom outlet not working'),
  'id': requestId,
  'propertyId': propertyId,
  'tenantId': tenantId,
  'technicianId': technicianId,
  'referenceCode': reference,
  'assignedTechnicianName': name,
  'category': 1,
  'description': 'The bedroom outlet has no power.',
  'preferredAccessWindow': 'Morning',
  'createdAt': '2026-10-03T08:15:00Z',
};

Map<String, dynamic> summary(Map<String, dynamic> request) => {...request}
  ..remove('description')
  ..remove('assignedTechnicianName');

Future<void> mountTenant(
  WidgetTester tester,
  Map<String, dynamic> request, {
  List<Map<String, dynamic>> history = const [],
  List<Map<String, dynamic>> attachments = const [],
  double scale = 1,
}) async {
  await tenant.mount(tester, (r) async {
    final Object payload;
    if (r.url.path.contains('/tenant/')) {
      payload = [summary(request)];
    } else if (r.url.path.endsWith('/history')) {
      payload = history;
    } else if (r.url.path.endsWith('/attachments')) {
      payload = attachments;
    } else {
      payload = request;
    }
    return http.Response(jsonEncode(payload), 200);
  }, scale: scale);
  await tester.pumpAndSettle();
}

void expectNoDatabaseIds() {
  for (final id in [requestId, propertyId, tenantId, technicianId]) {
    expect(find.textContaining(id), findsNothing);
  }
}

void main() {
  testWidgets(
    'compact Tenant summary expands real identity, ordered history and attachments',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mountTenant(
        tester,
        detail(),
        history: [
          {
            'id': 'assigned',
            'fromStatus': 1,
            'toStatus': 2,
            'changedAt': '2026-10-04T10:00:00Z',
            'notes': 'Bring an outlet tester.',
          },
          {
            'id': 'submitted',
            'fromStatus': null,
            'toStatus': 0,
            'changedAt': '2026-10-03T08:15:00Z',
            'notes': null,
          },
          {
            'id': 'triaged',
            'fromStatus': 0,
            'toStatus': 1,
            'changedAt': '2026-10-04T09:00:00Z',
            'notes': null,
          },
        ],
        attachments: [
          {
            'id': 'photo',
            'maintenanceRequestId': requestId,
            'fileName': 'outlet.png',
            'contentType': 'image/png',
            'fileSize': 2048,
            'attachmentType': null,
            'uploadedByUserId': tenantId,
            'createdAt': '2026-10-03T08:16:00Z',
          },
        ],
      );

      final toggle = find.byKey(const ValueKey('request-toggle-$requestId'));
      expect(find.text('Electrical · $reference'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Oct 3'), findsOneWidget);
      expect(tester.getSize(toggle).height, lessThan(140));
      expect(find.text('DESCRIPTION'), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expectNoDatabaseIds();

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('DESCRIPTION'), findsNothing);
      expect(find.text('The bedroom outlet has no power.'), findsOneWidget);
      expect(find.text('Preferred access'), findsOneWidget);
      expect(find.text('Morning 8-12'), findsOneWidget);
      expect(find.text('Mike Reyes'), findsOneWidget);
      expect(find.text('MR'), findsOneWidget);
      expect(find.text('Assigned technician'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      final submittedY = tester.getTopLeft(find.text('Request submitted')).dy;
      final triagedY = tester.getTopLeft(find.text('Request reviewed')).dy;
      final assignedY = tester.getTopLeft(find.text('Technician assigned')).dy;
      expect(submittedY, lessThan(triagedY));
      expect(triagedY, lessThan(assignedY));
      expect(find.text('Bring an outlet tester.'), findsNothing);
      expect(find.text('ATTACHMENTS'), findsOneWidget);
      expect(find.text('outlet.png'), findsOneWidget);
      expect(find.text('No attachments yet.'), findsNothing);
      expect(find.text('Parts ordered'), findsNothing);
      expect(find.text('On-site visit scheduled'), findsNothing);
      expect(find.text('Call'), findsNothing);
      expect(find.byIcon(Icons.phone), findsNothing);
      expect(find.byIcon(Icons.email), findsNothing);
      expectNoDatabaseIds();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Mike Reyes'), findsNothing);
      expect(find.text('DESCRIPTION'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final missing in ['unassigned', 'null-name', 'blank-name']) {
    testWidgets(
      'omits unavailable identity, access and empty history ($missing)',
      (tester) async {
        final request = detail(
          name: missing == 'null-name'
              ? null
              : missing == 'blank-name'
              ? '  '
              : 'Mike Reyes',
        );
        if (missing == 'unassigned') request['technicianId'] = null;
        request['preferredAccessWindow'] = null;
        request['tenantAccessNotes'] = null;
        await mountTenant(tester, request);
        await tester.tap(
          find.byKey(const ValueKey('request-toggle-$requestId')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('assigned-technician-identity')),
          findsNothing,
        );
        expect(find.text('Mike Reyes'), findsNothing);
        expect(find.text('PREFERRED ACCESS'), findsNothing);
        expect(find.text('UPDATES'), findsNothing);
        expect(find.text('No attachments yet.'), findsOneWidget);
        expectNoDatabaseIds();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Technician queue and active detail use friendly references without database IDs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = fixtures.MemoryTokenStorage('token');
      final auth = fixtures.buildController(
        storage,
        role: UserRole.maintenanceTechnician,
      );
      await auth.restoreSession();
      addTearDown(auth.dispose);
      final requests = [
        detail()..['technicianId'] = auth.currentUser!.id,
        {
          ...detail(),
          'id': '51efbe01-9196-44b6-b1b2-73767fae5cf1',
          'title': 'Kitchen sink leaking',
          'referenceCode': 'MR-AAAAAAAAAAAAAAAA',
          'technicianId': auth.currentUser!.id,
        },
      ];
      final client = ApiClient(
        baseUrl: 'http://test',
        tokenStorage: storage,
        httpClient: MockClient((r) async {
          if (r.url.path.contains('/technician/')) {
            return http.Response(
              jsonEncode(requests.map(summary).toList()),
              200,
            );
          }
          final request = requests
              .where((item) => r.url.path.endsWith('/${item['id']}'))
              .firstOrNull;
          return http.Response(
            request == null ? '[]' : jsonEncode(request),
            200,
          );
        }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: AssignedWorkScreen(
              technicianId: auth.currentUser!.id,
              maintenanceApiService: MaintenanceApiService(client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Electrical · $reference'), findsNWidgets(2));
      expect(find.text('Electrical · MR-AAAAAAAAAAAAAAAA'), findsOneWidget);
      expectNoDatabaseIds();
      expect(find.textContaining(auth.currentUser!.id), findsNothing);
      await tester.tap(find.text('Kitchen sink leaking · in Progress'));
      await tester.pumpAndSettle();
      expect(find.text('Electrical · MR-AAAAAAAAAAAAAAAA'), findsNWidgets(2));
      expect(find.textContaining(requests[1]['id'] as String), findsNothing);
      expectNoDatabaseIds();
      expect(tester.takeException(), isNull);
    },
  );
}
