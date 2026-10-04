import 'dart:convert';
import '../../../core/network/api_client.dart';
import '../models/viewing_follow_up.dart';

class ViewingFollowUpApiService {
  const ViewingFollowUpApiService(this.apiClient);
  final ApiClient apiClient;
  Future<ViewingFollowUp?> claimNext() async {
    final response = await apiClient.post(
      apiClient.buildUri('/api/viewing-follow-ups/next/claim'),
    );
    if (response.statusCode == 204) return null;
    if (response.statusCode != 200) {
      throw const FollowUpApiException('Unable to check viewing follow-ups.');
    }
    try {
      return ViewingFollowUp.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const FollowUpApiException(
        'The viewing follow-up response was invalid.',
      );
    }
  }

  Future<void> respond(String id, FollowUpDecision decision) async {
    final response = await apiClient.post(
      apiClient.buildUri('/api/viewing-follow-ups/$id/respond'),
      body: jsonEncode({'decision': decision.value}),
    );
    if (response.statusCode != 200) {
      throw const FollowUpApiException(
        'Could not save your choice. Please try again.',
      );
    }
    try {
      final value = jsonDecode(response.body) as Map<String, dynamic>;
      if (value['followUpId'] != id ||
          value['decision'] != decision.value ||
          value['respondedAt'] is! String ||
          DateTime.tryParse(value['respondedAt'] as String) == null) {
        throw const FormatException();
      }
    } catch (_) {
      throw const FollowUpApiException(
        'Could not confirm your choice. Please try again.',
      );
    }
  }
}

class FollowUpApiException implements Exception {
  const FollowUpApiException(this.message);
  final String message;
}
