import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentflow_mobile/features/auth/models/current_user.dart';
import 'package:rentflow_mobile/features/application_documents/screens/tenant_documents_screen.dart';
import 'package:rentflow_mobile/features/application_documents/models/application_document.dart';
import 'package:rentflow_mobile/features/application_documents/screens/application_documents_screen.dart';
import 'rental_application_wizard_test.dart' as wizard;
import 'shared_shell_test.dart' as shell;

SelectedDocumentFile selected({
  String name = 'selected.pdf',
  String? extension = 'pdf',
  int size = 3,
  Uint8List? bytes,
}) => SelectedDocumentFile(
  name: name,
  extension: extension,
  size: size,
  bytes: bytes ?? Uint8List.fromList([1, 2, 3]),
);
Finder row(int type) => find.byKey(ValueKey('wizard-document-$type'));

void main() {
  testWidgets(
    'Profile still opens Tenant Documents and the full document workspace',
    (tester) async {
      final backend = wizard.Backend();
      addTearDown(backend.close);
      await shell.pumpShell(
        tester,
        UserRole.tenant,
        apiClient: backend.discovery.client,
      );
      await tester.tap(shell.navigationDestination('Profile'));
      await tester.pumpAndSettle();
      await wizard.tap(tester, find.text('Application documents'));
      expect(find.byType(TenantDocumentsScreen), findsOneWidget);
      await wizard.tap(tester, find.text('View documents'));
      expect(find.byType(ApplicationDocumentsScreen), findsOneWidget);
      expect(
        tester
            .widget<ApplicationDocumentsScreen>(
              find.byType(ApplicationDocumentsScreen),
            )
            .applicationId,
        wizard.id,
      );
      await tester.scrollUntilVisible(find.text('Choose file'), 250);
      expect(find.text('Choose file'), findsOneWidget);
    },
  );
  testWidgets(
    'confirmed upload metadata remains visible if list refresh fails; Continue waits for recovery',
    (tester) async {
      final backend = wizard.Backend(step: 2);
      final previous = backend.discovery.intercept;
      backend.discovery.intercept = (request) async {
        final response = await previous?.call(request);
        if (request.url.path == '${wizard.detail}/documents' &&
            request.method == 'POST') {
          backend.failDocuments = true;
        }
        return response;
      };
      await wizard.open(
        tester,
        backend,
        documentPicker: () async => selected(),
      );
      await wizard.tap(tester, row(1));
      expect(find.textContaining('Uploaded · selected.pdf'), findsOneWidget);
      expect(find.text('Reload documents'), findsOneWidget);
      await wizard.next(tester);
      expect(find.text('Documents information'), findsOneWidget);
      backend.failDocuments = false;
      await wizard.tap(tester, find.text('Reload documents'));
      await wizard.next(tester);
      expect(find.text('Review information'), findsOneWidget);
    },
  );
  for (final invalid in ['applicationId', 'documentType']) {
    testWidgets('upload response with mismatched $invalid is rejected', (
      tester,
    ) async {
      final backend = wizard.Backend(step: 2);
      final previous = backend.discovery.intercept;
      backend.discovery.intercept = (request) async {
        if (request.method == 'POST' &&
            request.url.path == '${wizard.detail}/documents') {
          return http.Response(
            jsonEncode({
              ...wizard.documentJson(1),
              'originalFileName': 'selected.pdf',
              if (invalid == 'applicationId')
                'applicationId': 'other-application',
              if (invalid == 'documentType') 'documentType': 0,
            }),
            201,
          );
        }
        return previous?.call(request);
      };
      await wizard.open(
        tester,
        backend,
        documentPicker: () async => selected(),
      );
      await wizard.tap(tester, row(1));
      expect(
        find.text('The document service returned an invalid response.'),
        findsOneWidget,
      );
      expect(find.textContaining('Uploaded · selected.pdf'), findsNothing);
      expect(find.text('Documents information'), findsOneWidget);
    });
  }
  testWidgets(
    'ChangesRequested can upload required files to the same application',
    (tester) async {
      final backend = wizard.Backend(status: 3, step: 2);
      await wizard.open(
        tester,
        backend,
        documentPicker: () async => selected(),
      );
      await wizard.tap(tester, row(1));
      expect(find.textContaining('Uploaded · selected.pdf'), findsOneWidget);
      expect(backend.calls('${wizard.detail}/documents', 'POST'), 1);
      expect(backend.calls(wizard.root, 'POST'), 0);
    },
  );
  for (final type in ApplicationDocumentType.values) {
    testWidgets(
      '${type.label} directly selects and uploads correct type to existing application',
      (tester) async {
        final backend = wizard.Backend(step: 2)..documents = [];
        var picks = 0;
        await wizard.open(
          tester,
          backend,
          documentPicker: () async {
            picks++;
            return selected();
          },
        );
        await wizard.tap(tester, row(type.value));
        expect(picks, 1);
        expect(find.byType(ApplicationDocumentsScreen), findsNothing);
        expect(find.text('Documents information'), findsOneWidget);
        expect(backend.calls('${wizard.detail}/documents', 'POST'), 1);
        expect(backend.calls(wizard.root, 'POST'), 0);
        final request = backend.discovery.requests.singleWhere(
          (r) => r.method == 'POST',
        );
        expect(request.url.path, '${wizard.detail}/documents');
        expect(request.headers['Authorization'], 'Bearer tenant-token');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data;'),
        );
        expect(
          request.body,
          contains('name="documentType"\r\n\r\n${type.value}'),
        );
        expect(request.body, contains('content-type: application/pdf'));
        expect(find.textContaining('Uploaded · selected.pdf'), findsOneWidget);
        expect(
          backend.calls('${wizard.detail}/documents'),
          greaterThanOrEqualTo(2),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'picker cancellation, including native resume, sends no API calls and keeps rows',
    (tester) async {
      final backend = wizard.Backend(step: 2);
      final picker = Completer<SelectedDocumentFile?>();
      await wizard.open(tester, backend, documentPicker: () => picker.future);
      final calls = backend.discovery.requests.length;
      await tester.ensureVisible(row(1));
      await tester.tap(row(1));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      picker.complete(null);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backend.discovery.requests.length, calls);
      expect(find.text('Documents information'), findsOneWidget);
      expect(find.text('Upload failed · Tap to retry'), findsNothing);
      expect(find.textContaining('Uploaded · identity.pdf'), findsOneWidget);
      expect(find.text('Missing · Required'), findsOneWidget);
    },
  );
  testWidgets('upload in flight disables repeated row taps and Continue', (
    tester,
  ) async {
    final backend = wizard.Backend(step: 2)..uploadGate = Completer<void>();
    var picks = 0;
    await wizard.open(
      tester,
      backend,
      documentPicker: () async {
        picks++;
        return selected();
      },
    );
    await tester.ensureVisible(row(1));
    await tester.tap(row(1));
    await tester.pump();
    await tester.pump();
    expect(find.text('Uploading...'), findsOneWidget);
    expect(tester.widget<InkWell>(row(1)).onTap, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('application-next-step')))
          .onPressed,
      isNull,
    );
    expect(picks, 1);
    expect(backend.calls('${wizard.detail}/documents', 'POST'), 1);
    backend.uploadGate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Uploaded · selected.pdf'), findsOneWidget);
    expect(find.text('Documents information'), findsOneWidget);
    await wizard.next(tester);
    expect(find.text('Review information'), findsOneWidget);
  });
  testWidgets(
    'failed upload retains same row/file for retry without another picker or fake success',
    (tester) async {
      final backend = wizard.Backend(step: 2)..failUpload = true;
      var picks = 0;
      await wizard.open(
        tester,
        backend,
        documentPicker: () async {
          picks++;
          return selected();
        },
      );
      await wizard.tap(tester, row(1));
      expect(find.text('Upload failed · Tap to retry'), findsOneWidget);
      expect(find.textContaining('Uploaded · selected.pdf'), findsNothing);
      expect(find.text('Documents information'), findsOneWidget);
      backend.failUpload = false;
      await wizard.tap(tester, row(1));
      expect(picks, 1);
      expect(backend.calls('${wizard.detail}/documents', 'POST'), 2);
      expect(find.textContaining('Uploaded · selected.pdf'), findsOneWidget);
    },
  );
  testWidgets('invalid success acknowledgment cannot mark row uploaded', (
    tester,
  ) async {
    final backend = wizard.Backend(step: 2)..invalidUploadResponse = true;
    await wizard.open(tester, backend, documentPicker: () async => selected());
    await wizard.tap(tester, row(1));
    expect(find.text('Upload failed · Tap to retry'), findsOneWidget);
    expect(find.textContaining('Uploaded · selected.pdf'), findsNothing);
    expect(find.text('Documents information'), findsOneWidget);
  });
  for (final invalid in ['empty', 'large', 'unsupported', 'access']) {
    testWidgets('$invalid selection is handled safely before an upload', (
      tester,
    ) async {
      final backend = wizard.Backend(step: 2);
      await wizard.open(
        tester,
        backend,
        documentPicker: () async {
          if (invalid == 'access') {
            throw PlatformException(
              code: 'permission_denied',
              message: 'private details',
            );
          }
          return selected(
            extension: invalid == 'unsupported' ? 'gif' : 'pdf',
            size: invalid == 'large'
                ? 5 * 1024 * 1024 + 1
                : invalid == 'empty'
                ? 0
                : 3,
          );
        },
      );
      final calls = backend.discovery.requests.length;
      await wizard.tap(tester, row(1));
      expect(backend.discovery.requests.length, calls);
      expect(find.text('Upload failed · Tap to retry'), findsOneWidget);
      expect(find.textContaining('private details'), findsNothing);
      expect(find.text('Documents information'), findsOneWidget);
    });
  }
  testWidgets(
    'uploaded row offers View and Add another, preserves duplicate-type records',
    (tester) async {
      final backend = wizard.Backend(step: 2);
      await wizard.open(
        tester,
        backend,
        documentPicker: () async => selected(name: 'another.pdf'),
      );
      await wizard.tap(tester, row(0));
      expect(find.text('View document'), findsOneWidget);
      expect(find.text('Add another file'), findsOneWidget);
      expect(find.text('Replace document'), findsNothing);
      await wizard.tap(tester, find.text('Add another file'));
      expect(
        backend.documents.where((doc) => doc['documentType'] == 0),
        hasLength(2),
      );
      expect(find.textContaining('identity.pdf'), findsWidgets);
      expect(find.textContaining('another.pdf'), findsOneWidget);
      expect(
        backend.calls('/api/application-documents/document-0', 'DELETE'),
        0,
      );
      expect(find.byType(ApplicationDocumentsScreen), findsNothing);
    },
  );
  testWidgets(
    'View requests authenticated signed URL and opens it externally',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      MethodCall? launch;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            launch = call;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final backend = wizard.Backend(step: 2);
      final original = backend.discovery.intercept;
      backend.discovery.intercept = (request) async {
        if (request.url.path ==
            '/api/application-documents/document-0/download') {
          expect(request.headers['Authorization'], 'Bearer tenant-token');
          return http.Response(
            '',
            302,
            headers: {'location': 'https://signed.test/private-document'},
          );
        }
        return original?.call(request);
      };
      await wizard.open(tester, backend);
      await wizard.tap(tester, row(0));
      await wizard.tap(tester, find.text('View document'));
      expect(
        backend.calls('/api/application-documents/document-0/download'),
        1,
      );
      expect(launch?.arguments['url'], 'https://signed.test/private-document');
      expect(find.text('Documents information'), findsOneWidget);
    },
  );
  testWidgets(
    'normal app resume restores authoritative documents for same application',
    (tester) async {
      final backend = wizard.Backend(step: 2);
      await wizard.open(tester, backend);
      backend.documents.add(wizard.documentJson(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Uploaded · income.pdf'), findsOneWidget);
      expect(find.text('Documents information'), findsOneWidget);
      expect(backend.calls(wizard.root, 'POST'), 0);
    },
  );
  for (final status in [0, 3]) {
    testWidgets(
      'status $status allows upload; external lifecycle change blocks upload',
      (tester) async {
        final backend = wizard.Backend(status: status, step: 2);
        await wizard.open(
          tester,
          backend,
          documentPicker: () async {
            backend.application['status'] = 1;
            return selected();
          },
        );
        // ChangesRequested resumes earlier; advance its already valid saved sections.
        if (status == 3) {
          await wizard.next(tester);
          await wizard.next(tester);
        }
        await wizard.tap(tester, row(1));
        expect(backend.calls('${wizard.detail}/documents', 'POST'), 0);
        expect(
          find.text(
            'Documents can only be uploaded for Draft or Changes Requested applications.',
          ),
          findsOneWidget,
        );
      },
    );
  }
  for (final display in [
    (320.0, 720.0, 1.0),
    (720.0, 1560.0, 2.0),
    (1080.0, 2340.0, 3.0),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'document rows fit ${display.$1}x${display.$2} at ${scale * 100}% text with long filenames',
        (tester) async {
          final backend = wizard.Backend(step: 2);
          backend.documents.first['originalFileName'] =
              '${List.filled(12, 'long document name').join(' ')}.pdf';
          await wizard.open(
            tester,
            backend,
            width: display.$1,
            height: display.$2,
            ratio: display.$3,
            scale: scale,
            documentPicker: () async => null,
          );
          for (var type = 0; type < 4; type++) {
            await tester.ensureVisible(row(type));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await wizard.tap(tester, row(3));
          expect(find.text('Documents information'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
