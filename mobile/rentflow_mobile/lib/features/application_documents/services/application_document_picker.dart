import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class SelectedDocumentFile {
  const SelectedDocumentFile({
    required this.name,
    required this.extension,
    required this.size,
    required this.bytes,
  });
  final String name;
  final String? extension;
  final int size;
  final Uint8List bytes;
}

class DocumentSelectionException implements Exception {
  const DocumentSelectionException(this.message);
  final String message;
}

/// Shared native Files selection; mirrors ApplicationDocumentService's size/MIME
/// limits and preserves the existing picker extension filter.
abstract final class ApplicationDocumentPicker {
  static const maximumFileSizeBytes = 5 * 1024 * 1024;
  static const extensions = ['pdf', 'jpg', 'jpeg', 'png'];
  static const accessError =
      'Unable to access this file. Choose another file and try again.';

  static String? contentTypeFor(String? extension) =>
      switch (extension?.toLowerCase()) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        _ => null,
      };

  static String validate(SelectedDocumentFile file) {
    if (file.size <= 0 || file.bytes.isEmpty) {
      throw const DocumentSelectionException(
        'The selected document file cannot be empty.',
      );
    }
    if (file.size > maximumFileSizeBytes ||
        file.bytes.length > maximumFileSizeBytes) {
      throw const DocumentSelectionException(
        'Choose a file that is 5 MB or smaller.',
      );
    }
    final mime = contentTypeFor(file.extension);
    if (mime == null) {
      throw const DocumentSelectionException(
        'Only PDF, JPEG, and PNG files are supported.',
      );
    }
    return mime;
  }

  static Future<SelectedDocumentFile?> pick() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: extensions,
      );
      if (file == null) return null;
      final size = await file.length();
      // Reject large provider files before reading them into memory.
      if (size > maximumFileSizeBytes) {
        throw const DocumentSelectionException(
          'Choose a file that is 5 MB or smaller.',
        );
      }
      if (size <= 0) {
        throw const DocumentSelectionException(
          'The selected document file cannot be empty.',
        );
      }
      final separator = file.name.lastIndexOf('.');
      final selected = SelectedDocumentFile(
        name: file.name,
        extension: separator < 0
            ? null
            : file.name.substring(separator + 1).toLowerCase(),
        size: size,
        bytes: await file.readAsBytes(),
      );
      validate(selected);
      return selected;
    } on DocumentSelectionException {
      rethrow;
    } catch (_) {
      throw const DocumentSelectionException(accessError);
    }
  }
}
