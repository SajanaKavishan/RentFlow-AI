import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/auth/token_storage.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/viewings/models/viewing.dart';
import 'package:rentflow_mobile/features/viewings/services/viewing_reminders.dart';

final reminderNow = DateTime.utc(2030, 1, 2, 5);
const ownerId = 'owner';
Map<String, dynamic> viewingJson({
  String id = 'viewing',
  String property = 'property',
  int status = 1,
  bool eligible = true,
  DateTime? at,
}) => {
  'id': id,
  'tenantId': 'tenant',
  'propertyId': property,
  'propertyTitle': 'Garden House',
  'tenant': {'displayName': 'Nimal Perera'},
  'durationMinutes': 60,
  'requestedDateTime': '2030-01-02T04:00:00Z',
  'requestedLocalDate': '2030-01-02',
  'requestedDisplayTime': '9:30 AM',
  'timeZoneId': 'Asia/Colombo',
  'status': status,
  'canMarkCompleted': eligible,
  'completionEligibleAt': (at ?? reminderNow).toIso8601String(),
  'tenantMessage': 'I would like to see the garden.',
  'landlordResponse': null,
  'createdAt': '2030-01-01T10:00:00Z',
  'updatedAt': null,
};
Map<String, dynamic> propertyJson({String id = 'property'}) => {
  'id': id,
  'landlordId': ownerId,
  'title': 'Garden House',
  'description': 'Home with a garden',
  'address': '12 Garden Road',
  'city': 'Colombo',
  'monthlyRent': 70000,
  'bedrooms': 2,
  'bathrooms': 1,
  'isAvailable': true,
  'amenities': <String>[],
  'createdAt': '2030-01-01T10:00:00Z',
  'updatedAt': null,
};
Map<String, dynamic> applicationJson({
  String id = 'application',
  String property = 'property',
}) => {
  'id': id,
  'tenantId': 'tenant',
  'propertyId': property,
  'propertyTitle': 'Garden House',
  'applicantName': 'Nimal Perera',
  'moveInDate': '2030-02-01',
  'monthlyIncome': 250000,
  'occupation': 'Engineer',
  'numberOfOccupants': 2,
  'tenantNote': 'Moving closer to work.',
  'status': 1,
  'landlordResponse': null,
  'createdAt': '2030-01-01T10:00:00Z',
  'submittedAt': '2030-01-01T11:00:00Z',
  'updatedAt': null,
};
http.Response jsonResponse(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

class WorkspaceTokens implements TokenStorage {
  @override
  Future<String?> readToken() async => 'owner-token';
  @override
  Future<void> saveToken(String value) async {}
  @override
  Future<void> deleteToken() async {}
}

ApiClient workspaceClient(
  Future<http.Response> Function(http.Request) handler,
) => ApiClient(
  baseUrl: 'http://test',
  tokenStorage: WorkspaceTokens(),
  httpClient: MockClient(handler),
);

class MemoryReminderDevice implements ReminderDevice {
  final scheduled = <int, String?>{};
  final scheduledViewings = <Viewing>[];
  final cancelled = <int>[];
  String? state;
  bool denyPermission = false;
  int permissionRequests = 0;
  bool _asked = false;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> requestPermissionOnce() async {
    if (_asked) return;
    _asked = true;
    permissionRequests++;
    if (denyPermission) throw StateError('Permission denied');
  }

  @override
  Future<Map<int, String?>> pending() async => Map.of(scheduled);
  @override
  Future<void> schedule(int id, Viewing viewing, String payload) async {
    scheduled[id] = payload;
    scheduledViewings.add(viewing);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<String?> readState() async => state;
  @override
  Future<void> writeState(String value) async {
    state = value;
  }
}
