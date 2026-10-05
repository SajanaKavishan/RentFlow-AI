import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

enum MaintenancePhotoSource { camera, gallery }

class MaintenancePhoto {
  const MaintenancePhoto({
    required this.fileName,
    required this.bytes,
    required this.contentType,
  });

  // Matches the maintenance attachment service; the server remains authoritative.
  static const maximumCount = 5;
  static const maximumBytes = 10 * 1024 * 1024;

  final String fileName;
  final Uint8List bytes;
  final String contentType;

  String? validate() {
    if (bytes.isEmpty) return 'Choose a photo that is not empty.';
    if (bytes.length > maximumBytes) {
      return 'Each photo must be 10 MB or smaller.';
    }
    final extension = fileName.split('.').last.toLowerCase();
    final expectedType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (expectedType == null ||
        contentType != expectedType ||
        mimeType(bytes) != expectedType) {
      return 'Choose a JPEG, PNG, or WEBP photo.';
    }
    return null;
  }

  static String? mimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    const png = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length >= 8 && listEquals(bytes.take(8).toList(), png)) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }
}

class MaintenancePhotoPickerException implements Exception {
  const MaintenancePhotoPickerException(this.message);
  final String message;
}

abstract class MaintenancePhotoPicker {
  Future<List<MaintenancePhoto>> pick(MaintenancePhotoSource source);
  Future<List<MaintenancePhoto>> recoverLostPhotos() async => [];
  bool get canOpenSettings => false;
  Future<bool> openSettings() async => false;
}

class PlatformMaintenancePhotoPicker extends MaintenancePhotoPicker {
  PlatformMaintenancePhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  bool get canOpenSettings =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> openSettings() async {
    if (!canOpenSettings) return false;
    try {
      return await launchUrl(
        Uri.parse('app-settings:'),
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      return false;
    }
  }

  @override
  Future<List<MaintenancePhoto>> pick(MaintenancePhotoSource source) async {
    try {
      final List<XFile> files;
      if (source == MaintenancePhotoSource.camera) {
        final photo = await _picker.pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
        );
        files = photo == null ? [] : [photo];
      } else {
        files = await _picker.pickMultiImage(requestFullMetadata: false);
      }
      return Future.wait(files.map(_readPhoto));
    } on PlatformException catch (error) {
      throw _safePlatformError(error);
    } on MissingPluginException {
      throw const MaintenancePhotoPickerException(
        'Photo selection is unavailable on this device.',
      );
    }
  }

  @override
  Future<List<MaintenancePhoto>> recoverLostPhotos() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return [];
    try {
      final response = await _picker.retrieveLostData();
      if (response.exception case final error?) throw _safePlatformError(error);
      return Future.wait((response.files ?? []).map(_readPhoto));
    } on MissingPluginException {
      return [];
    } on PlatformException catch (error) {
      throw _safePlatformError(error);
    }
  }

  Future<MaintenancePhoto> _readPhoto(XFile file) async {
    final size = await file.length();
    if (size == 0 || size > MaintenancePhoto.maximumBytes) {
      throw const MaintenancePhotoPickerException(
        'Choose a nonempty photo that is 10 MB or smaller.',
      );
    }
    final bytes = await file.readAsBytes();
    final photo = MaintenancePhoto(
      fileName: file.name,
      bytes: bytes,
      contentType: MaintenancePhoto.mimeType(bytes) ?? '',
    );
    if (photo.validate() case final error?) {
      throw MaintenancePhotoPickerException(error);
    }
    return photo;
  }

  MaintenancePhotoPickerException _safePlatformError(PlatformException error) {
    final denied =
        error.code.toLowerCase().contains('denied') ||
        error.code.toLowerCase().contains('restricted');
    if (denied) {
      final source = error.code.toLowerCase().contains('camera')
          ? 'Camera'
          : 'Photo library';
      return MaintenancePhotoPickerException(
        '$source access is denied. You can allow it in your device settings.',
      );
    }
    return const MaintenancePhotoPickerException(
      'Unable to select a photo. Please try again.',
    );
  }
}
