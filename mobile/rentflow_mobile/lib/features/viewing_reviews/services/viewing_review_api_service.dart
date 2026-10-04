import 'dart:convert';
import '../../../core/network/api_client.dart';

class ViewingReview {
  const ViewingReview(
    this.id,
    this.viewingId,
    this.propertyRating,
    this.landlordRating,
    this.comment,
  );
  final String id, viewingId;
  final int propertyRating, landlordRating;
  final String? comment;
  factory ViewingReview.fromJson(Map<String, dynamic> json) {
    final property = json['propertyRating'], landlord = json['landlordRating'];
    if (json['id'] is! String ||
        json['viewingId'] is! String ||
        property is! int ||
        landlord is! int ||
        property < 1 ||
        property > 5 ||
        landlord < 1 ||
        landlord > 5) {
      throw const FormatException('Invalid review');
    }
    return ViewingReview(
      json['id'] as String,
      json['viewingId'] as String,
      property,
      landlord,
      json['comment'] as String?,
    );
  }
}

class ViewingReviewApiException implements Exception {
  const ViewingReviewApiException(this.message);
  final String message;
}

class ViewingReviewApiService {
  const ViewingReviewApiService(this.client);
  final ApiClient client;
  Future<ViewingReview?> getOwn(String viewingId) async {
    final response = await client.get(
      client.buildUri('/api/viewings/$viewingId/review'),
    );
    if (response.statusCode == 204) return null;
    if (response.statusCode != 200) {
      throw const ViewingReviewApiException(
        'Could not load your viewing review.',
      );
    }
    final value = ViewingReview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (value.viewingId != viewingId) {
      throw const FormatException('Invalid viewing');
    }
    return value;
  }

  Future<ViewingReview> save(
    String viewingId,
    int property,
    int landlord,
    String comment,
  ) async {
    final response = await client.put(
      client.buildUri('/api/viewings/$viewingId/review'),
      body: jsonEncode({
        'propertyRating': property,
        'landlordRating': landlord,
        'comment': comment,
      }),
    );
    if (response.statusCode != 200) {
      throw const ViewingReviewApiException(
        'Could not save your review. Please try again.',
      );
    }
    try {
      final value = ViewingReview.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (value.viewingId != viewingId ||
          value.propertyRating != property ||
          value.landlordRating != landlord) {
        throw const FormatException();
      }
      return value;
    } catch (_) {
      throw const ViewingReviewApiException(
        'Could not confirm your review. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>> publicSummary(
    String propertyId, {
    bool landlord = false,
  }) async {
    final response = await client.get(
      client.buildUri(
        '/api/properties/$propertyId/${landlord ? 'landlord-viewing-reviews' : 'viewing-reviews'}',
      ),
      authenticated: false,
    );
    if (response.statusCode != 200) {
      throw const ViewingReviewApiException('Viewing reviews unavailable.');
    }
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    return _validateSummary(value);
  }

  Future<Map<String, dynamic>> landlordSummary() async {
    final response = await client.get(
      client.buildUri('/api/landlord/viewing-reviews/summary'),
    );
    if (response.statusCode != 200) {
      throw const ViewingReviewApiException('Could not load viewing feedback.');
    }
    final value = jsonDecode(response.body) as Map<String, dynamic>;
    _validateSummary(value['landlord'] as Map<String, dynamic>);
    if (value['properties'] is! List) {
      throw const FormatException('Invalid properties');
    }
    for (final property in value['properties'] as List) {
      if (property is! Map<String, dynamic> ||
          property['propertyId'] is! String ||
          property['title'] is! String) {
        throw const FormatException('Invalid property feedback');
      }
      _validateSummary({...property, 'reviews': property['recentReviews']});
    }
    return value;
  }

  Map<String, dynamic> _validateSummary(Map<String, dynamic> value) {
    final count = value['reviewCount'], average = value['averageRating'];
    if (count is! int ||
        count < 0 ||
        value['reviews'] is! List ||
        (count > 0 && (average is! num || average < 1 || average > 5))) {
      throw const FormatException('Invalid review summary');
    }
    for (final review in value['reviews'] as List) {
      if (review is! Map<String, dynamic> ||
          review['rating'] is! int ||
          (review['rating'] as int) < 1 ||
          (review['rating'] as int) > 5 ||
          review['comment'] is! String ||
          review['reviewMonth'] is! String ||
          !RegExp(r'^\d{4}-\d{2}$').hasMatch(review['reviewMonth'] as String)) {
        throw const FormatException('Invalid public review');
      }
    }
    return value;
  }
}
