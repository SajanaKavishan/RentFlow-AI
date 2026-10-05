import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:rentflow_mobile/debug/maintenance_preview.dart';
import 'package:rentflow_mobile/debug/maintenance_preview_dependencies.dart';
import 'package:rentflow_mobile/features/maintenance/services/maintenance_photo_picker.dart';

import 'tenant_maintenance_redesign_test.dart' as fixtures;

const requestId = '11efbe01-9196-44b6-b1b2-73767fae5cf1';
const reference = 'MR-C8070B6D94F6A810';

Future<MaintenancePhoto> photo([String name = 'sink.png']) async =>
    MaintenancePhoto(
      fileName: name,
      bytes: (await rootBundle.load(
        'assets/auth/residence.png',
      )).buffer.asUint8List(),
      contentType: 'image/png',
    );

class FakePicker extends MaintenancePhotoPicker {
  List<MaintenancePhoto> next = [];
  MaintenancePhotoPickerException? error;
  final List<MaintenancePhotoSource> calls = [];
  bool supportsSettings = false;
  int settingsOpened = 0;
  @override
  bool get canOpenSettings => supportsSettings;
  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<List<MaintenancePhoto>> pick(MaintenancePhotoSource source) async {
    calls.add(source);
    if (error case final failure?) throw failure;
    return next;
  }
}

class FakeNativePicker extends ImagePicker {
  XFile? selected;
  PlatformException? failure;
  ImageSource? source;
  bool? fullMetadata;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    fullMetadata = requestFullMetadata;
    if (failure case final error?) throw error;
    return selected;
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    bool requestFullMetadata = true,
    int? limit,
  }) async {
    source = ImageSource.gallery;
    fullMetadata = requestFullMetadata;
    if (failure case final error?) throw error;
    return selected == null ? [] : [selected!];
  }
}

class WorkflowApi {
  final events = <String>[];
  final attachments = <Map<String, dynamic>>[];
  Map<String, dynamic>? body;
  int createStatus = 201;
  int failUpload = 0;
  int uploads = 0;
  final uploadHeaders = <Map<String, String>>[];
  final uploadPaths = <String>[];
  Completer<http.Response>? pendingCreate;
  Map<String, dynamic> get response => {
    ...fixtures.requestJson(0, title: 'Server-derived title'),
    'id': requestId,
    'referenceCode': reference,
    'category': 7,
    'priority': 2,
    'preferredAccessWindow': 'Evening',
  };
  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'POST' &&
        request.url.path.endsWith('/maintenance-requests')) {
      events.add('create');
      body = jsonDecode(request.body) as Map<String, dynamic>;
      if (pendingCreate case final pending?) return pending.future;
      return http.Response(
        jsonEncode(
          createStatus == 201
              ? response
              : {
                  'detail':
                      'An active lease for this property is required to submit a maintenance request.',
                },
        ),
        createStatus,
      );
    }
    if (request.method == 'POST' && request.url.path.endsWith('/attachments')) {
      events.add('upload');
      uploads++;
      uploadPaths.add(request.url.path);
      uploadHeaders.add(Map.of(request.headers));
      if (uploads == failUpload) {
        return http.Response('{"detail":"Photo upload failed."}', 503);
      }
      final attachment = {
        'id': 'attachment-$uploads',
        'maintenanceRequestId': requestId,
        'fileName': 'photo-$uploads.png',
        'contentType': 'image/png',
        'fileSize': request.bodyBytes.length,
        'attachmentType': null,
        'uploadedByUserId': fixtures.requestJson(0)['tenantId'],
        'createdAt': '2026-10-05T09:00:00Z',
      };
      attachments.add(attachment);
      return http.Response(jsonEncode(attachment), 201);
    }
    if (request.url.path.endsWith('/attachments')) {
      events.add('attachments');
      return http.Response(jsonEncode(attachments), 200);
    }
    events.add('detail');
    return http.Response(jsonEncode(response), 200);
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> choosePhotos(WidgetTester tester, String source) async {
  await tap(tester, find.byKey(const ValueKey('maintenance-add-photo')));
  await tap(tester, find.text(source));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native camera/gallery read valid bytes with minimal metadata; cancellation and denial are safe',
    () async {
      final valid = await photo();
      final native = FakeNativePicker()
        ..selected = XFile.fromData(
          valid.bytes,
          name: valid.fileName,
          path: valid.fileName,
          mimeType: valid.contentType,
        );
      final picker = PlatformMaintenancePhotoPicker(picker: native);
      expect(
        (await picker.pick(MaintenancePhotoSource.camera)).single.validate(),
        isNull,
      );
      expect(native.source, ImageSource.camera);
      expect(native.fullMetadata, isFalse);
      expect(
        (await picker.pick(MaintenancePhotoSource.gallery)).single.bytes,
        valid.bytes,
      );
      expect(native.source, ImageSource.gallery);
      expect(native.fullMetadata, isFalse);
      native.selected = null;
      expect(await picker.pick(MaintenancePhotoSource.camera), isEmpty);
      native.failure = PlatformException(
        code: 'camera_access_denied',
        message: '/private/internal/path',
      );
      await expectLater(
        picker.pick(MaintenancePhotoSource.camera),
        throwsA(
          isA<MaintenancePhotoPickerException>().having(
            (e) => e.message,
            'message',
            'Camera access is denied. You can allow it in your device settings.',
          ),
        ),
      );
      native.failure = PlatformException(code: 'photo_access_restricted');
      await expectLater(
        picker.pick(MaintenancePhotoSource.gallery),
        throwsA(
          isA<MaintenancePhotoPickerException>().having(
            (e) => e.message,
            'message',
            contains('device settings'),
          ),
        ),
      );
    },
  );

  test(
    'photo policy rejects empty, oversized and mismatched image files',
    () async {
      final valid = await photo();
      expect(valid.validate(), isNull);
      expect(
        MaintenancePhoto(
          fileName: 'empty.png',
          bytes: Uint8List(0),
          contentType: 'image/png',
        ).validate(),
        contains('empty'),
      );
      expect(
        MaintenancePhoto(
          fileName: 'big.png',
          bytes: Uint8List(MaintenancePhoto.maximumBytes + 1),
          contentType: 'image/png',
        ).validate(),
        contains('10 MB'),
      );
      expect(
        MaintenancePhoto(
          fileName: 'document.pdf',
          bytes: valid.bytes,
          contentType: 'application/pdf',
        ).validate(),
        contains('JPEG'),
      );
      expect(
        MaintenancePhoto(
          fileName: 'renamed.jpg',
          bytes: valid.bytes,
          contentType: 'image/jpeg',
        ).validate(),
        contains('JPEG'),
      );
      expect(
        MaintenancePhoto(
          fileName: 'broken.png',
          bytes: Uint8List.fromList([1, 2, 3]),
          contentType: 'image/png',
        ).validate(),
        contains('JPEG'),
      );
    },
  );

  testWidgets(
    'source sheet defers selection; thumbnails, remove, five-photo limit and permission error preserve draft',
    (tester) async {
      final picker = FakePicker()..next = [await photo()];
      final api = WorkflowApi();
      await fixtures.mount(
        tester,
        api.handle,
        create: true,
        photoPicker: picker,
      );
      await tester.pumpAndSettle();
      await fixtures.fillDraft(tester);
      await tap(tester, find.byKey(const ValueKey('maintenance-add-photo')));
      expect(picker.calls, isEmpty);
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
      await tap(tester, find.text('Cancel'));
      expect(picker.calls, isEmpty);
      await choosePhotos(tester, 'Take a photo');
      expect(picker.calls.single, MaintenancePhotoSource.camera);
      expect(find.text('1/5 photos added'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      picker.next = List.filled(4, await photo());
      await choosePhotos(tester, 'Choose from gallery');
      expect(picker.calls.last, MaintenancePhotoSource.gallery);
      expect(find.text('5/5 photos added'), findsOneWidget);
      expect(find.byKey(const ValueKey('maintenance-add-photo')), findsNothing);
      await tap(tester, find.byTooltip('Remove photo 1'));
      expect(find.text('4/5 photos added'), findsOneWidget);
      picker.next = List.filled(2, await photo());
      await choosePhotos(tester, 'Choose from gallery');
      expect(find.textContaining('Choose fewer photos'), findsOneWidget);
      expect(find.text('4/5 photos added'), findsOneWidget);
      picker.error = const MaintenancePhotoPickerException(
        'Camera access is denied. You can allow it in your device settings.',
      );
      await choosePhotos(tester, 'Take a photo');
      expect(find.textContaining('device settings'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
      picker.supportsSettings = true;
      await choosePhotos(tester, 'Take a photo');
      await tap(tester, find.text('Open settings'));
      expect(picker.settingsOpened, 1);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('maintenance-description')),
            )
            .controller!
            .text,
        'Water below the sink.',
      );
      expect(api.events, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final failedPhoto in [0, 2]) {
    testWidgets(
      'create precedes uploads once; authoritative success and partial failure $failedPhoto',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final picker = FakePicker()
          ..next = [await photo(), await photo('tap.png')];
        final api = WorkflowApi()
          ..failUpload = failedPhoto
          ..pendingCreate = Completer<http.Response>();
        await fixtures.mount(
          tester,
          api.handle,
          create: true,
          photoPicker: picker,
        );
        await tester.pumpAndSettle();
        await fixtures.fillDraft(tester);
        await choosePhotos(tester, 'Choose from gallery');
        final submit = find.byKey(const ValueKey('maintenance-submit'));
        await tester.ensureVisible(submit);
        final callback = tester.widget<FilledButton>(submit).onPressed!;
        callback();
        callback();
        await tester.pump();
        expect(api.events, ['create']);
        expect(api.body, isNot(contains('title')));
        expect(api.body, isNot(contains('tenantAccessNotes')));
        expect(api.body, isNot(contains('referenceCode')));
        api.pendingCreate!.complete(
          http.Response(jsonEncode(api.response), 201),
        );
        await tester.pumpAndSettle();
        expect(api.events, [
          'create',
          'upload',
          'upload',
          'detail',
          'attachments',
        ]);
        expect(api.uploadPaths, everyElement(contains(requestId)));
        expect(
          api.uploadHeaders,
          everyElement(
            predicate<Map<String, String>>(
              (headers) => headers.values.any(
                (value) => value.startsWith('multipart/form-data'),
              ),
            ),
          ),
        );
        expect(find.text('Request Submitted'), findsOneWidget);
        expect(find.text('REQUEST #$reference'), findsOneWidget);
        expect(find.text(requestId), findsNothing);
        expect(find.text('Server-derived title'), findsNothing);
        expect(find.text('HVAC / A/C'), findsOneWidget);
        expect(find.text('High Priority'), findsOneWidget);
        expect(find.text('Evening 5-8'), findsOneWidget);
        expect(
          find.text('${failedPhoto == 0 ? 2 : 1} attached'),
          findsOneWidget,
        );
        expect(
          find.textContaining('could not be uploaded'),
          failedPhoto == 0 ? findsNothing : findsOneWidget,
        );
        expect(find.textContaining('24 hours'), findsNothing);
        await tap(tester, find.text('New Request'));
        expect(find.text('0/5 photos added'), findsOneWidget);
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
        expect(api.events.where((e) => e == 'create'), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final status in [403, 409]) {
    testWidgets(
      'eligibility rejection $status preserves draft and never uploads photos',
      (tester) async {
        final picker = FakePicker()..next = [await photo()];
        final api = WorkflowApi()..createStatus = status;
        await fixtures.mount(
          tester,
          api.handle,
          create: true,
          photoPicker: picker,
        );
        await tester.pumpAndSettle();
        await fixtures.fillDraft(tester);
        await choosePhotos(tester, 'Take a photo');
        await tap(tester, find.byKey(const ValueKey('maintenance-submit')));
        expect(api.events, ['create']);
        expect(find.text('Request Submitted'), findsNothing);
        expect(
          find.textContaining(
            status == 403 ? 'active lease' : 'currently unavailable',
          ),
          findsOneWidget,
        );
        expect(find.text('1/5 photos added'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('maintenance-description')),
              )
              .controller!
              .text,
          'Water below the sink.',
        );
      },
    );
  }

  testWidgets(
    '500-character counter and required access prevent blank/oversized submission',
    (tester) async {
      final api = WorkflowApi();
      await fixtures.mount(
        tester,
        api.handle,
        create: true,
        photoPicker: FakePicker(),
      );
      await tester.pumpAndSettle();
      final description = find.byKey(const ValueKey('maintenance-description'));
      final submit = find.byKey(const ValueKey('maintenance-submit'));
      await tester.ensureVisible(description);
      await tester.enterText(description, ' ' * 20);
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(description, 'a' * 501);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(description).controller!.text.length,
        500,
      );
      expect(find.text('500/500'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tap(tester, find.byKey(const ValueKey('access-evening')));
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      expect(api.events, isEmpty);
    },
  );

  for (final viewport in [
    (const Size(320, 800), 1.0),
    (const Size(720, 1560), 2.0),
    (const Size(1080, 2340), 3.0),
  ]) {
    testWidgets(
      'photo sheet and confirmation fit ${viewport.$1} with 200% text',
      (tester) async {
        tester.view.physicalSize = viewport.$1;
        tester.view.devicePixelRatio = viewport.$2;
        addTearDown(tester.view.reset);
        final api = WorkflowApi();
        await fixtures.mount(
          tester,
          api.handle,
          create: true,
          scale: 2,
          photoPicker: FakePicker(),
        );
        await tester.pumpAndSettle();
        await fixtures.fillDraft(tester);
        await tap(tester, find.byKey(const ValueKey('maintenance-add-photo')));
        expect(find.text('Take a photo'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Cancel'));
        await tap(tester, find.byKey(const ValueKey('maintenance-submit')));
        await tester.ensureVisible(find.text('Track Request'));
        expect(find.text('REQUEST #$reference'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'offline preview selects fixture photos and confirms the real attachment count',
    (tester) async {
      await tester.pumpWidget(const MaintenancePreviewApp());
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('new-maintenance-request')));
      await fixtures.fillDraft(tester);
      await choosePhotos(tester, 'Take a photo');
      await choosePhotos(tester, 'Choose from gallery');
      expect(find.text('4/5 photos added'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('maintenance-submit')));
      expect(find.text('4 attached'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        PreviewMaintenancePhotoPicker(
          permissionDenied: true,
        ).pick(MaintenancePhotoSource.camera),
        throwsA(isA<MaintenancePhotoPickerException>()),
      );
    },
  );
}
