import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/viewings/models/viewing.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_reminders.dart';
import 'helpers/landlord_workspace_fixture.dart';

void main() {
  late MemoryReminderDevice device;
  late ViewingReminders reminders;
  setUp(() async {
    device = MemoryReminderDevice();
    reminders = ViewingReminders(device, now: () => reminderNow);
    await reminders.setOwner(ownerId);
  });
  Viewing future({int status = 1, DateTime? at, String id = 'viewing'}) =>
      Viewing.fromJson(
        viewingJson(
          status: status,
          id: id,
          eligible: false,
          at: at ?? reminderNow.add(const Duration(minutes: 30)),
        ),
      );

  test(
    'uses exact server end, deduplicates and keeps allocation on restart',
    () async {
      final viewing = future();
      await reminders.reconcile(ownerId, [viewing]);
      final id = device.scheduled.keys.single;
      expect(
        device.scheduledViewings.single.completionEligibleAt,
        viewing.completionEligibleAt,
      );
      expect(
        jsonDecode(device.scheduled[id]!)['at'],
        viewing.completionEligibleAt!.toUtc().toIso8601String(),
      );
      await reminders.reconcile(ownerId, [viewing]);
      final restarted = ViewingReminders(device, now: () => reminderNow);
      await restarted.setOwner(ownerId);
      await restarted.reconcile(ownerId, [viewing]);
      expect(device.scheduled.keys, [id]);
      expect(device.scheduledViewings, hasLength(1));
      expect(device.permissionRequests, 1);
    },
  );
  for (final status in [0, 2, 3, 4]) {
    test('status $status cancels existing reminder', () async {
      await reminders.reconcile(ownerId, [future()]);
      final id = device.scheduled.keys.single;
      await reminders.reconcile(ownerId, [future(status: status)]);
      expect(device.scheduled, isEmpty);
      expect(device.cancelled, contains(id));
    });
  }
  test(
    'changed eligibility replaces the same notification, no extra hour',
    () async {
      await reminders.reconcile(ownerId, [future()]);
      final id = device.scheduled.keys.single;
      final changed = future(at: reminderNow.add(const Duration(minutes: 45)));
      await reminders.reconcile(ownerId, [changed]);
      expect(device.scheduled.keys, [id]);
      expect(
        device.scheduledViewings.last.completionEligibleAt,
        changed.completionEligibleAt,
      );
      expect(device.scheduledViewings, hasLength(2));
    },
  );
  test('different viewings use collision-free persistent IDs', () async {
    await reminders.reconcile(ownerId, [future(id: 'Aa'), future(id: 'BB')]);
    expect(device.scheduled, hasLength(2));
    expect(device.scheduled.keys.toSet(), hasLength(2));
  });
  test(
    'permission failure is contained; later reconcile and logout still work',
    () async {
      device.denyPermission = true;
      await reminders.reconcile(ownerId, [future()]);
      await reminders.reconcile(ownerId, [future()]);
      expect(device.permissionRequests, 1);
      await reminders.setOwner(null);
      expect(device.scheduled, isEmpty);
    },
  );
  test(
    'missing timestamp and already due viewing do not schedule device reminder',
    () async {
      final raw = viewingJson()..['completionEligibleAt'] = null;
      await reminders.reconcile(ownerId, [
        Viewing.fromJson(raw),
        future(id: 'due', at: reminderNow),
      ]);
      expect(device.scheduled, isEmpty);
    },
  );
  test(
    'ownership change cancels old reminders and rejects stale reconcile/tap',
    () async {
      await reminders.reconcile(ownerId, [future()]);
      reminders.tappedPayload.value = device.scheduled.values.single;
      await reminders.setOwner('other-owner');
      await reminders.reconcile(ownerId, [future()]);
      expect(device.scheduled, isEmpty);
      expect(reminders.consumeTap('other-owner'), isNull);
    },
  );
  test('authoritative removal cancels reminder', () async {
    await reminders.reconcile(ownerId, [future()]);
    await reminders.reconcile(ownerId, []);
    expect(device.scheduled, isEmpty);
  });
}
