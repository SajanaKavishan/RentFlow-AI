class PropertyMatchingRequest {
  const PropertyMatchingRequest({
    this.preferredCity,
    this.maximumMonthlyRent,
    this.minimumBedrooms,
    this.minimumBathrooms,
    this.preferredAmenities = const [],
  });

  final String? preferredCity;
  final double? maximumMonthlyRent;
  final int? minimumBedrooms;
  final int? minimumBathrooms;
  final List<String> preferredAmenities;

  Map<String, dynamic> toJson() {
    return {
      'preferredCity': preferredCity,
      'maximumMonthlyRent': maximumMonthlyRent,
      'minimumBedrooms': minimumBedrooms,
      'minimumBathrooms': minimumBathrooms,
      'preferredAmenities': preferredAmenities,
    };
  }
}

class PropertyMatchingResponse {
  const PropertyMatchingResponse({
    required this.matches,
    required this.summary,
  });

  final List<PropertyMatch> matches;
  final String summary;

  factory PropertyMatchingResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final matchesJson = json['matches'];

    if (matchesJson is! List) {
      throw const FormatException();
    }

    return PropertyMatchingResponse(
      matches: matchesJson.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException();
        }

        return PropertyMatch.fromJson(item);
      }).toList(growable: false),
      summary: json['summary'] is String
          ? json['summary'] as String
          : '',
    );
  }
}

class PropertyMatch {
  const PropertyMatch({
    required this.propertyId,
    required this.title,
    required this.city,
    required this.monthlyRent,
    required this.bedrooms,
    required this.bathrooms,
    required this.amenities,
    required this.matchScore,
    required this.matchReasons,
  });

  final String propertyId;
  final String title;
  final String city;
  final double monthlyRent;
  final int bedrooms;
  final int bathrooms;
  final List<String> amenities;
  final int matchScore;
  final List<String> matchReasons;

  factory PropertyMatch.fromJson(Map<String, dynamic> json) {
    return PropertyMatch(
      propertyId: json['propertyId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      monthlyRent: _asDouble(json['monthlyRent']),
      bedrooms: _asInt(json['bedrooms']),
      bathrooms: _asInt(json['bathrooms']),
      amenities: _stringList(json['amenities']),
      matchScore: _asInt(json['matchScore']),
      matchReasons: _stringList(json['matchReasons']),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _asInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}