import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rentflow_mobile/features/viewings/models/viewing.dart';
import 'package:rentflow_mobile/features/viewings/services/local_reminder_device.dart';
import 'helpers/landlord_workspace_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final calls = <MethodCall>[];
  final values = <String, String>{};
  setUp(() {
    calls.clear();
    values.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'getNotificationAppLaunchDetails') {
            return {'notificationLaunchedApp': false};
          }
          if (call.method == 'pendingNotificationRequests') return <Object>[];
          if (call.method == 'requestNotificationsPermission' ||
              call.method == 'requestPermissions') {
            return false;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
          final data = call.arguments as Map;
          if (call.method == 'read') return values[data['key']];
          if (call.method == 'write') {
            values[data['key'] as String] = data['value'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null);
  });
  test(
    'Android denial is requested once and schedule uses server UTC timestamp',
    () async {
      final device = LocalReminderDevice();
      await device.initialize();
      await device.requestPermissionOnce();
      await LocalReminderDevice().requestPermissionOnce();
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        hasLength(1),
      );
      final at = reminderNow.add(const Duration(minutes: 30));
      await device.schedule(
        10001,
        Viewing.fromJson(viewingJson(at: at)),
        'payload',
      );
      final schedule =
          calls.singleWhere((c) => c.method == 'zonedSchedule').arguments
              as Map;
      expect(schedule['id'], 10001);
      expect(schedule['scheduledDateTime'], '2030-01-02T05:30:00');
      expect(schedule['timeZoneName'], 'Etc/UTC');
      expect(schedule['title'], 'How did the viewing go?');
      expect(schedule['body'], contains('Garden House'));
      expect(schedule['payload'], 'payload');
      expect(
        calls.where((c) => c.method == 'requestExactAlarmsPermission'),
        isEmpty,
      );
    },
  );
  test(
    'iOS initialization defers permission; explicit request is only made once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      final device = LocalReminderDevice();
      await device.initialize();
      final settings =
          calls.singleWhere((c) => c.method == 'initialize').arguments as Map;
      expect(settings['requestAlertPermission'], false);
      expect(settings['requestBadgePermission'], false);
      expect(settings['requestSoundPermission'], false);
      await device.requestPermissionOnce();
      await device.requestPermissionOnce();
      expect(
        calls.where((c) => c.method == 'requestPermissions'),
        hasLength(1),
      );
    },
  );
}
