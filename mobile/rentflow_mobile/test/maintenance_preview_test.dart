import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/debug/maintenance_preview.dart';
import 'package:rentflow_mobile/debug/maintenance_preview_dependencies.dart';
import 'package:rentflow_mobile/features/maintenance/models/maintenance_request.dart';
import 'package:rentflow_mobile/features/maintenance/screens/create_maintenance_request_screen.dart';
import 'package:rentflow_mobile/features/maintenance/screens/my_maintenance_requests_screen.dart';
import 'package:rentflow_mobile/features/maintenance/widgets/tenant_maintenance_ui.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openForm(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('new-maintenance-request')));
  expect(find.byType(CreateMaintenanceRequestScreen), findsOneWidget);
  expect(find.text('Preview apartment'), findsOneWidget);
}

Future<void> _fillForm(WidgetTester tester) async {
  final description = find.byKey(const ValueKey('maintenance-description'));
  await tester.ensureVisible(description);
  await tester.enterText(description, 'The entrance lock is jammed.');
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
  await _tap(tester, find.byKey(const ValueKey('access-morning')));
}

void main() {
  test(
    'preview title derivation keeps a nonblank title for punctuation-only descriptions',
    () async {
      final dependencies = MaintenancePreviewDependencies();
      addTearDown(dependencies.dispose);
      await dependencies.auth.restoreSession();
      final property =
          (await dependencies.maintenance.getTenantProperties()).single;
      final created = await dependencies.maintenance.createMaintenanceRequest(
        tenantId: dependencies.auth.currentUser!.id,
        propertyId: property.id,
        description: '...',
        category: MaintenanceCategory.plumbing,
        priority: MaintenancePriority.normal,
        preferredAccessWindow: PreferredAccessWindow.morning,
      );
      expect(created.title, 'Plumbing issue');
    },
  );
  test('production sources cannot import or export the debug directory', () {
    final root = Directory('lib').absolute;
    final directives = RegExp(
      r'''^\s*(?:import|export|part)\b[^;]*;''',
      multiLine: true,
    );
    final paths = RegExp(r'''['"]([^'"]+\.dart)['"]''');
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      final normalized = file.path.replaceAll('\\', '/');
      if (!normalized.endsWith('.dart') || normalized.contains('/lib/debug/')) {
        continue;
      }
      for (final directive in directives.allMatches(file.readAsStringSync())) {
        for (final path in paths.allMatches(directive.group(0)!)) {
          final target = path.group(1)!;
          final Uri resolved;
          if (target.startsWith('package:rentflow_mobile/')) {
            resolved = root.uri.resolve(
              target.substring('package:rentflow_mobile/'.length),
            );
          } else if (!target.contains(':')) {
            resolved = file.parent.uri.resolve(target);
          } else {
            continue;
          }
          expect(
            resolved.normalizePath().path,
            isNot(contains('/lib/debug/')),
            reason: '${file.path} must not reference $target',
          );
        }
      }
    }
  });

  test(
    'preview restores its own session and rejects all network transport',
    () async {
      final dependencies = MaintenancePreviewDependencies();
      addTearDown(dependencies.dispose);
      await dependencies.auth.restoreSession();
      expect(dependencies.auth.isAuthenticated, isTrue);
      final service = dependencies.maintenance;
      await expectLater(
        service.apiClient.get(service.apiClient.buildUri('/unimplemented')),
        throwsStateError,
      );
      final tenantId = dependencies.auth.currentUser!.id;
      final property = (await service.getTenantProperties()).single;
      final requests = await service.getMyMaintenanceRequests(
        tenantId: tenantId,
      );
      expect(
        requests.map((r) => r.status),
        containsAll([
          MaintenanceRequestStatus.submitted,
          MaintenanceRequestStatus.inProgress,
          MaintenanceRequestStatus.completed,
        ]),
      );
      final created = await service.createMaintenanceRequest(
        tenantId: tenantId,
        propertyId: property.id,
        title: 'New lock issue',
        description: 'Lock does not turn.',
        category: MaintenanceCategory.security,
        priority: MaintenancePriority.emergency,
        preferredAccessWindow: PreferredAccessWindow.morning,
        tenantAccessNotes: 'Knock first.',
      );
      expect(
        await service.getMaintenanceRequestById(created.id),
        same(created),
      );
      expect(created.category, MaintenanceCategory.security);
      expect(created.priority, MaintenancePriority.emergency);
      expect(created.tenantAccessNotes, 'Knock first.');
      expect(
        (await service.getMyMaintenanceRequests(tenantId: tenantId)).first,
        same(created),
      );
      expect(
        (await service.getMaintenanceRequestHistory(
          maintenanceRequestId: created.id,
        )).single.toStatus,
        created.status,
      );
      final attachment = await service.uploadMaintenanceAttachment(
        maintenanceRequestId: created.id,
        tenantId: tenantId,
        fileName: 'lock.png',
        contentType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(
        (await service.getMaintenanceRequestAttachments(
          maintenanceRequestId: created.id,
          tenantId: tenantId,
        )).single.fileSize,
        3,
      );
      await service.deleteMaintenanceAttachment(
        maintenanceRequestId: created.id,
        attachmentId: attachment.id,
        tenantId: tenantId,
      );
      expect(
        await service.getMaintenanceRequestAttachments(
          maintenanceRequestId: created.id,
          tenantId: tenantId,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'preview uses production overview, filters, details and attachments',
    (tester) async {
      await tester.pumpWidget(const MaintenancePreviewApp());
      await tester.pumpAndSettle();
      expect(find.byType(MyMaintenanceRequestsScreen), findsOneWidget);
      expect(find.text('Kitchen faucet dripping'), findsOneWidget);
      expect(find.text('Bedroom outlet not working'), findsOneWidget);
      expect(find.text('Refrigerator making unusual noise'), findsOneWidget);
      for (final filter in [
        ('open', 'Kitchen faucet dripping'),
        ('inProgress', 'Bedroom outlet not working'),
        ('resolved', 'Refrigerator making unusual noise'),
      ]) {
        await _tap(tester, find.byKey(ValueKey('filter-${filter.$1}')));
        expect(find.text(filter.$2), findsOneWidget);
      }
      await _tap(tester, find.byKey(const ValueKey('filter-open')));
      await _tap(tester, find.text('Kitchen faucet dripping'));
      expect(
        find.text(
          'Water drips from the kitchen faucet and pools below the sink.',
        ),
        findsOneWidget,
      );
      expect(find.text('UPDATES'), findsOneWidget);
      await tester.ensureVisible(find.text('kitchen-faucet.jpg'));
      expect(find.text('ATTACHMENTS'), findsOneWidget);
      expect(find.text('kitchen-faucet.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview validates the real form, submits supported fields and tracks',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaintenancePreviewApp());
      await tester.pumpAndSettle();
      await _openForm(tester);
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
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('maintenance-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('priority-low')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('category-locksDoors')));
      await _tap(tester, find.byKey(const ValueKey('priority-emergency')));
      await _fillForm(tester);
      await _tap(tester, find.text('Submit Request'));
      expect(find.text('Request Submitted'), findsOneWidget);
      expect(find.text('The entrance lock is jammed'), findsNothing);
      expect(find.text('Locks / Doors'), findsOneWidget);
      expect(find.text('Emergency'), findsOneWidget);
      expect(find.text('00000000-0000-4000-8000-000000002000'), findsNothing);
      expect(find.textContaining('REQUEST #MR-'), findsOneWidget);
      expect(find.text('Morning 8-12'), findsOneWidget);
      await _tap(tester, find.text('Track Request'));
      expect(find.byType(MyMaintenanceRequestsScreen), findsOneWidget);
      expect(find.byType(CreateMaintenanceRequestScreen), findsNothing);
      expect(find.text('The entrance lock is jammed'), findsOneWidget);
      expect(find.text('The entrance lock is jammed.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview success New Request resets the real form', (
    tester,
  ) async {
    await tester.pumpWidget(const MaintenancePreviewApp());
    await tester.pumpAndSettle();
    await _openForm(tester);
    await _fillForm(tester);
    await _tap(tester, find.text('Submit Request'));
    await _tap(tester, find.widgetWithText(OutlinedButton, 'New Request'));
    expect(find.byType(CreateMaintenanceRequestScreen), findsOneWidget);
    expect(find.text('Request Submitted'), findsNothing);
    expect(find.text('Preview security repair'), findsNothing);
    final description = tester.widget<TextFormField>(
      find.byKey(const ValueKey('maintenance-description')),
    );
    expect(description.controller!.text, isEmpty);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('access-morning')))
          .selected,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
