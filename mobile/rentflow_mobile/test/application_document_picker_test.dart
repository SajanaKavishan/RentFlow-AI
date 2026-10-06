import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentflow_mobile/features/application_documents/services/application_document_picker.dart';

final class PickerFile extends PlatformFile {
  PickerFile(this.name, this.size, {Uint8List? bytes})
    : bytes = bytes ?? Uint8List.fromList([1, 2, 3]);
  @override
  final String name;
  final int size;
  final Uint8List bytes;
  int reads = 0;
  @override
  Uri get uri => Uri.parse('content://documents/selected-file');
  @override
  get xFile => throw UnimplementedError();
  @override
  Future<int> length() async => size;
  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return bytes;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class NativePicker extends FilePickerPlatform {
  PlatformFile? file;
  Object? error;
  int calls = 0;
  FileType? selectedType;
  List<String>? extensions;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    selectedType = type;
    extensions = allowedExtensions;
    if (error != null) throw error!;
    return file;
  }
}

void main() {
  late NativePicker picker;
  setUp(() {
    picker = NativePicker();
    FilePickerPlatform.instance = picker;
  });
  test(
    'existing native picker uses the supported custom Files filter',
    () async {
      picker.file = PickerFile('passport.PDF', 3);
      final file = (await ApplicationDocumentPicker.pick())!;
      expect(picker.calls, 1);
      expect(picker.selectedType, FileType.custom);
      expect(picker.extensions, ['pdf', 'jpg', 'jpeg', 'png']);
      expect(file.name, 'passport.PDF');
      expect(file.extension, 'pdf');
      expect(ApplicationDocumentPicker.validate(file), 'application/pdf');
    },
  );
  test('native cancellation returns null without an error or read', () async {
    expect(await ApplicationDocumentPicker.pick(), isNull);
    expect(picker.calls, 1);
  });
  test('oversize provider file is rejected before bytes are read', () async {
    final file = PickerFile('large.pdf', 5 * 1024 * 1024 + 1);
    picker.file = file;
    await expectLater(
      ApplicationDocumentPicker.pick(),
      throwsA(isA<DocumentSelectionException>()),
    );
    expect(file.reads, 0);
  });
  test(
    'permission/access errors become safe messages without repeating the picker',
    () async {
      picker.error = PlatformException(
        code: 'permission_denied',
        message: 'private provider/path details',
      );
      try {
        await ApplicationDocumentPicker.pick();
        fail('Expected safe error');
      } on DocumentSelectionException catch (error) {
        expect(error.message, ApplicationDocumentPicker.accessError);
        expect(error.message, isNot(contains('private')));
      }
      expect(picker.calls, 1);
    },
  );
  for (final extension in ['pdf', 'jpg', 'jpeg', 'png']) {
    test(
      '$extension maps to backend MIME types at the exact size boundary',
      () {
        final file = SelectedDocumentFile(
          name: 'document.$extension',
          extension: extension,
          size: 5 * 1024 * 1024,
          bytes: Uint8List(5 * 1024 * 1024),
        );
        expect(
          ApplicationDocumentPicker.validate(file),
          extension == 'pdf'
              ? 'application/pdf'
              : extension == 'png'
              ? 'image/png'
              : 'image/jpeg',
        );
      },
    );
  }
  test(
    'empty bytes, oversized bytes and unsupported types fail local validation',
    () {
      for (final file in [
        SelectedDocumentFile(
          name: 'empty.pdf',
          extension: 'pdf',
          size: 0,
          bytes: Uint8List(0),
        ),
        SelectedDocumentFile(
          name: 'unreadable.pdf',
          extension: 'pdf',
          size: 3,
          bytes: Uint8List(0),
        ),
        SelectedDocumentFile(
          name: 'oversized.pdf',
          extension: 'pdf',
          size: 3,
          bytes: Uint8List(5 * 1024 * 1024 + 1),
        ),
        SelectedDocumentFile(
          name: 'file.gif',
          extension: 'gif',
          size: 3,
          bytes: Uint8List(3),
        ),
      ]) {
        expect(
          () => ApplicationDocumentPicker.validate(file),
          throwsA(isA<DocumentSelectionException>()),
        );
      }
    },
  );
}
