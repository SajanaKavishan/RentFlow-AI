import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentflow_mobile/core/network/api_client.dart';
import 'package:rentflow_mobile/features/auth/controllers/auth_controller.dart';
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/maintenance/screens/assigned_work_screen.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_api_service.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_photo_picker.dart';
import 'package:rentflow_mobile/shared/theme/app_theme.dart';

import 'widget_test.dart' as fixtures;

void main() {
  testWidgets(
    'Mark Complete is available only while assigned work is in progress',
    (tester) async {
      final approved = await _pump(tester, status: 6);
      expect(
        find.byKey(const ValueKey('complete-maintenance-work')),
        findsNothing,
      );
      approved.dispose();
      await tester.pumpWidget(const SizedBox());

      final inProgress = await _pump(tester, status: 8);
      expect(
        find.byKey(const ValueKey('complete-maintenance-work')),
        findsOneWidget,
      );
      inProgress.dispose();
    },
  );

  testWidgets('camera cancel is silent and gallery photo can be removed', (
    tester,
  ) async {
    final picker = _FakePicker()
      ..cameraResults.add(const <MaintenancePhoto>[])
      ..galleryResults.add([_photo('gallery.png')]);
    final harness = await _pump(tester, status: 8, picker: picker);
    addTearDown(harness.dispose);
    await _openSheet(tester);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('take-completion-photo')),
    );
    await _pumpUi(tester);
    expect(find.textContaining('Unable to select'), findsNothing);
    expect(
      find.byKey(const ValueKey('remove-completion-photo-0')),
      findsNothing,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('choose-completion-photos')),
    );
    await _pumpUi(tester);
    expect(picker.sources, [
      MaintenancePhotoSource.camera,
      MaintenancePhotoSource.gallery,
    ]);
    expect(
      find.byKey(const ValueKey('remove-completion-photo-0')),
      findsOneWidget,
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('remove-completion-photo-0')),
    );
    await _pumpUi(tester);
    expect(
      find.byKey(const ValueKey('remove-completion-photo-0')),
      findsNothing,
    );
  });

  testWidgets(
    'upload failure keeps sheet open and Retry completes after upload',
    (tester) async {
      final picker = _FakePicker()..galleryResults.add([_photo('done.png')]);
      final harness = await _pump(
        tester,
        status: 8,
        picker: picker,
        uploadFailures: 1,
      );
      addTearDown(harness.dispose);
      await _openSheet(tester);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('submit-maintenance-completion')),
      );
      await _pumpUi(tester);
      expect(find.text('Add at least one completion photo.'), findsOneWidget);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('choose-completion-photos')),
      );
      await _pumpUi(tester);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('submit-maintenance-completion')),
      );
      await _pumpUi(tester);

      expect(find.text('Complete this job'), findsOneWidget);
      expect(find.text('Photo upload failed.'), findsOneWidget);
      expect(harness.uploadAttempts, 1);
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Retry'));
      await _pumpUi(tester);

      expect(harness.uploadAttempts, 2);
      expect(harness.completeAttempts, 1);
      expect(find.text('No assigned work found'), findsOneWidget);
    },
  );

  testWidgets('completion retry keeps an already uploaded photo', (
    tester,
  ) async {
    final picker = _FakePicker()..cameraResults.add([_photo('camera.png')]);
    final harness = await _pump(
      tester,
      status: 8,
      picker: picker,
      completeFailures: 1,
    );
    addTearDown(harness.dispose);
    await _openSheet(tester);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('take-completion-photo')),
    );
    await _pumpUi(tester);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('submit-maintenance-completion')),
    );
    await _pumpUi(tester);

    expect(find.text('Completion failed after upload.'), findsOneWidget);
    expect(find.text('Complete this job'), findsOneWidget);
    expect(harness.uploadAttempts, 1);
    expect(harness.completeAttempts, 1);
    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Retry'));
    await _pumpUi(tester);

    expect(harness.uploadAttempts, 1);
    expect(harness.completeAttempts, 2);
    expect(find.text('No assigned work found'), findsOneWidget);
  });

  testWidgets(
    'Assigned Work refreshes with native pull gesture and has no refresh icon',
    (tester) async {
      final harness = await _pump(tester, status: 2);
      addTearDown(harness.dispose);
      expect(find.byTooltip('Refresh assigned work'), findsNothing);
      expect(harness.queueLoads, 1);

      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 400),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(harness.queueLoads, 2);
    },
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('complete-maintenance-work'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text('Complete this job'), findsOneWidget);
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  final widget = tester.widget(finder);
  if (widget is ButtonStyleButton) {
    widget.onPressed?.call();
  } else if (widget is IconButton) {
    widget.onPressed?.call();
  } else {
    throw StateError('Expected a tappable button.');
  }
  await tester.pump();
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required int status,
  _FakePicker? picker,
  int uploadFailures = 0,
  int completeFailures = 0,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final storage = fixtures.MemoryTokenStorage('token');
  final controller = fixtures.buildController(
    storage,
    role: UserRole.maintenanceTechnician,
  );
  await controller.restoreSession();
  var currentStatus = status;
  var uploads = 0;
  var completions = 0;
  var queueLoads = 0;
  final client = ApiClient(
    baseUrl: 'http://test',
    tokenStorage: storage,
    httpClient: MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/technician/')) {
        queueLoads++;
        return http.Response(
          jsonEncode(currentStatus == 9 ? [] : [_request(currentStatus)]),
          200,
        );
      }
      if (path.endsWith('/completion-attachments')) {
        uploads++;
        if (uploads <= uploadFailures) {
          return http.Response(
            jsonEncode({'detail': 'Photo upload failed.'}),
            400,
          );
        }
        return http.Response(jsonEncode(_attachment()), 201);
      }
      if (path.endsWith('/complete-work')) {
        completions++;
        if (completions <= completeFailures) {
          return http.Response(
            jsonEncode({'detail': 'Completion failed after upload.'}),
            400,
          );
        }
        currentStatus = 9;
        return http.Response(jsonEncode(_request(9)), 200);
      }
      if (path.endsWith('/history') || path.endsWith('/estimates')) {
        return http.Response('[]', 200);
      }
      if (path.endsWith('/estimates/latest')) return http.Response('', 204);
      if (path.endsWith('/job-1')) {
        return http.Response(jsonEncode(_request(currentStatus)), 200);
      }
      return http.Response('{}', 404);
    }),
  );
  await tester.pumpWidget(
    AuthScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: AssignedWorkScreen(
          maintenanceApiService: MaintenanceApiService(client),
          technicianId: '11111111-1111-1111-1111-111111111112',
          photoPicker: picker ?? _FakePicker(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(
    client,
    controller,
    () => uploads,
    () => completions,
    () => queueLoads,
  );
}

Map<String, dynamic> _request(int status) => {
  'id': 'job-1',
  'referenceCode': 'MR-ABC123',
  'propertyId': 'property-1',
  'propertyTitle': 'Garden House',
  'tenantId': 'tenant-1',
  'technicianId': '11111111-1111-1111-1111-111111111112',
  'title': 'Repair kitchen sink',
  'description': 'The sink is leaking.',
  'category': 0,
  'priority': 2,
  'status': status,
  'tenantAccessNotes': null,
  'triageNotes': null,
  'assignmentNotes': null,
  'cancellationReason': null,
  'completedAt': status == 9 ? '2026-10-06T08:00:00Z' : null,
  'createdAt': '2026-10-01T08:00:00Z',
  'updatedAt': null,
};

Map<String, dynamic> _attachment() => {
  'id': 'photo-1',
  'maintenanceRequestId': 'job-1',
  'fileName': 'done.png',
  'contentType': 'image/png',
  'fileSize': 8,
  'attachmentType': 'technician-completion',
  'uploadedByUserId': '11111111-1111-1111-1111-111111111112',
  'createdAt': '2026-10-06T08:00:00Z',
};

MaintenancePhoto _photo(String name) => MaintenancePhoto(
  fileName: name,
  bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  contentType: 'image/png',
);

class _FakePicker extends MaintenancePhotoPicker {
  final cameraResults = <List<MaintenancePhoto>>[];
  final galleryResults = <List<MaintenancePhoto>>[];
  final sources = <MaintenancePhotoSource>[];

  @override
  Future<List<MaintenancePhoto>> pick(MaintenancePhotoSource source) async {
    sources.add(source);
    final queue = source == MaintenancePhotoSource.camera
        ? cameraResults
        : galleryResults;
    return queue.isEmpty ? const [] : queue.removeAt(0);
  }
}

class _Harness {
  const _Harness(
    this.client,
    this.controller,
    this._uploads,
    this._completions,
    this._queueLoads,
  );
  final ApiClient client;
  final AuthController controller;
  final int Function() _uploads;
  final int Function() _completions;
  final int Function() _queueLoads;

  int get uploadAttempts => _uploads();
  int get completeAttempts => _completions();
  int get queueLoads => _queueLoads();

  void dispose() {
    controller.dispose();
    client.close();
  }
}
