import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/shared/profile/shared_profile_content.dart';

import 'helpers/profile_backend.dart';
import 'match_preferences_test.dart' show tapVisible;

void main() {
  late ProfileBackend backend;
  setUp(() => backend = ProfileBackend(role: UserRole.maintenanceTechnician));
  tearDown(() => backend.dispose());

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    await backend.pump(
      tester,
      (user) => Scaffold(body: SharedProfileContent(user: user)),
      scale: scale,
    );
    await tapVisible(tester, find.text('Work contact'));
  }

  for (final role in UserRole.values) {
    testWidgets('Work contact profile row is Technician-only (${role.value})', (
      tester,
    ) async {
      backend.profile['role'] = role.value;
      await backend.pump(
        tester,
        (user) => Scaffold(body: SharedProfileContent(user: user)),
      );
      expect(
        find.text('Work contact'),
        role == UserRole.maintenanceTechnician ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('profile phone is copied only by explicit enabled Save', (
    tester,
  ) async {
    await open(tester);
    expect(backend.writes, isEmpty);
    await tapVisible(tester, find.byType(SwitchListTile));
    expect(backend.writes, isEmpty);
    await tapVisible(tester, find.text('Save'));
    final body = jsonDecode(backend.writes.single.body) as Map<String, dynamic>;
    expect(body['maintenanceContactPhone'], backend.profile['phoneNumber']);
    expect(body['maintenanceContactEnabled'], true);
    expect(body.containsKey('publicContactPhone'), isFalse);
    expect(
      backend.auth.currentUser!.maintenanceContactPhone,
      backend.profile['phoneNumber'],
    );
  });

  testWidgets(
    'custom work number can be saved and disabled without losing its snapshot',
    (tester) async {
      await open(tester);
      await tapVisible(tester, find.text('Use a different number'));
      await tester.enterText(find.byType(TextField), '+44 (20) 7123-4567');
      await tapVisible(tester, find.byType(SwitchListTile));
      await tapVisible(tester, find.text('Save'));
      expect(
        backend.auth.currentUser!.maintenanceContactPhone,
        '+44 (20) 7123-4567',
      );
      await tapVisible(tester, find.text('Work contact'));
      await tapVisible(tester, find.byType(SwitchListTile));
      await tapVisible(tester, find.text('Save'));
      final body = jsonDecode(backend.writes.last.body) as Map<String, dynamic>;
      expect(body['maintenanceContactPhone'], '+44 (20) 7123-4567');
      expect(body['maintenanceContactEnabled'], false);
      expect(backend.auth.currentUser!.maintenanceContactEnabled, isFalse);
    },
  );

  testWidgets(
    'later private phone change does not mutate the saved work contact',
    (tester) async {
      backend.profile['maintenanceContactPhone'] = '+94 77 123 4567';
      backend.profile['maintenanceContactEnabled'] = true;
      backend.profile['phoneNumber'] = '+94112223344';
      await open(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '+94 77 123 4567',
      );
      await tapVisible(tester, find.text('Save'));
      final body =
          jsonDecode(backend.writes.single.body) as Map<String, dynamic>;
      expect(body['maintenanceContactPhone'], '+94 77 123 4567');
      expect(body['phoneNumber'], '+94112223344');
    },
  );

  testWidgets('invalid enabled work number stays local and preserves draft', (
    tester,
  ) async {
    await open(tester);
    await tapVisible(tester, find.text('Use a different number'));
    await tester.enterText(find.byType(TextField), '12-----');
    await tapVisible(tester, find.byType(SwitchListTile));
    await tapVisible(tester, find.text('Save'));
    expect(backend.writes, isEmpty);
    expect(
      find.textContaining('Enter a valid work contact number'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '12-----',
    );
  });

  testWidgets('disabled empty save never copies private phone', (tester) async {
    await open(tester);
    await tapVisible(tester, find.text('Save'));
    final body = jsonDecode(backend.writes.single.body) as Map<String, dynamic>;
    expect(body['maintenanceContactPhone'], '');
    expect(body['maintenanceContactEnabled'], false);
  });

  testWidgets('Work contact editor fits 320px with 200% text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester, scale: 2);
    await tapVisible(tester, find.text('Use a different number'));
    await tester.enterText(find.byType(TextField), '+94771234567');
    await tapVisible(tester, find.byType(SwitchListTile));
    await tapVisible(tester, find.text('Save'));
    expect(backend.auth.currentUser!.maintenanceContactEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
