class PropertyImage {
  const PropertyImage({
    required this.id,
    required this.isPrimary,
    required this.sortOrder,
  });

  final String id;
  final bool isPrimary;
  final int sortOrder;

  factory PropertyImage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Invalid property image ID.');
    }
    return PropertyImage(
      id: id,
      isPrimary: json['isPrimary'] == true,
      sortOrder: json['sortOrder'] is int ? json['sortOrder'] as int : 0,
    );
  }
}

class PublicLandlordSummary {
  const PublicLandlordSummary({
    required this.displayName,
    this.memberSinceYear,
    required this.hasProfileImage,
  });

  final String displayName;
  final int? memberSinceYear;
  final bool hasProfileImage;

  factory PublicLandlordSummary.fromJson(Map<String, dynamic> json) =>
      PublicLandlordSummary(
        displayName: json['displayName'] is String
            ? (json['displayName'] as String).trim()
            : '',
        memberSinceYear:
            json['memberSinceYear'] is int &&
                (json['memberSinceYear'] as int) > 0
            ? json['memberSinceYear'] as int
            : null,
        hasProfileImage: json['hasProfileImage'] == true,
      );
}
