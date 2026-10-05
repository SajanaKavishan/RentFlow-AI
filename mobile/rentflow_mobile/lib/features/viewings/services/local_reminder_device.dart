import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/viewing.dart';
import 'viewing_reminders.dart';

final viewingReminders = ViewingReminders(LocalReminderDevice());

class LocalReminderDevice implements ReminderDevice {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _storage = const FlutterSecureStorage();
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> initialize() async {
    if (!_supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_viewing_reminder'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          viewingReminders.tappedPayload.value = response.payload,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      viewingReminders.tappedPayload.value =
          launch?.notificationResponse?.payload;
    }
  }

  @override
  Future<void> requestPermissionOnce() async {
    if (!_supported ||
        await _storage.read(key: 'viewing-reminder-permission-v1') == 'asked') {
      return;
    }
    // Record the attempt before opening the OS prompt, including denial/dismissal.
    await _storage.write(key: 'viewing-reminder-permission-v1', value: 'asked');
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<Map<int, String?>> pending() async => !_supported
      ? {}
      : {
          for (final n in await _plugin.pendingNotificationRequests())
            n.id: n.payload,
        };

  @override
  Future<void> schedule(int id, Viewing viewing, String payload) async {
    if (!_supported) return;
    final title = viewing.propertyTitle?.trim();
    final body = title != null && title.isNotEmpty && title.length <= 80
        ? "Confirm the tenant's attendance for your viewing at $title."
        : "Confirm the tenant's attendance for your viewing.";
    await _plugin.zonedSchedule(
      id: id,
      title: 'How did the viewing go?',
      body: body,
      scheduledDate: tz.TZDateTime.from(viewing.completionEligibleAt!, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'viewing_completion',
          'Viewing reminders',
          channelDescription: 'Reminders to confirm viewing attendance',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      // Avoid requiring special exact-alarm access for an informational reminder.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (_supported) await _plugin.cancel(id: id);
  }

  @override
  Future<String?> readState() async =>
      _supported ? _storage.read(key: 'viewing-reminders-v1') : null;
  @override
  Future<void> writeState(String state) async {
    if (_supported) {
      await _storage.write(key: 'viewing-reminders-v1', value: state);
    }
  }
}
