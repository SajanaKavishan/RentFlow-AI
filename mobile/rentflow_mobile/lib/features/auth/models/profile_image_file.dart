import 'dart:typed_data';

class ProfileImageFile {
  const ProfileImageFile({required this.name, required this.bytes});

  static const maximumBytes = 5 * 1024 * 1024;
  final String name;
  final Uint8List bytes;

  String? get contentType => switch (name.split('.').last.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };

  String? validate() {
    if (bytes.isEmpty || bytes.length > maximumBytes) {
      return 'Choose a photo between 1 byte and 5 MB.';
    }
    final type = contentType;
    if (type == null || !hasImageSignature(bytes, type)) {
      return 'Choose a valid JPEG, PNG, or WEBP photo.';
    }
    return null;
  }

  static bool hasImageSignature(Uint8List bytes, String type) {
    bool startsWith(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[offset + i] != signature[i]) return false;
      }
      return true;
    }

    return switch (type) {
      'image/jpeg' => startsWith([0xff, 0xd8, 0xff]),
      'image/png' => startsWith([
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
      'image/webp' =>
        startsWith([0x52, 0x49, 0x46, 0x46]) &&
            startsWith([0x57, 0x45, 0x42, 0x50], 8),
      _ => false,
    };
  }
}
