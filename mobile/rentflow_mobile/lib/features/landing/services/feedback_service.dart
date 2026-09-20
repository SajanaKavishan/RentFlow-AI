class FeedbackMessage {
  const FeedbackMessage({
    required this.name,
    required this.email,
    required this.message,
  });

  final String name;
  final String email;
  final String message;
}

abstract interface class FeedbackService {
  Future<void> send(FeedbackMessage message);
}

class FeedbackTransportUnavailable implements Exception {
  const FeedbackTransportUnavailable();
}

class UnavailableFeedbackService implements FeedbackService {
  const UnavailableFeedbackService();

  @override
  Future<void> send(FeedbackMessage message) async {
    throw const FeedbackTransportUnavailable();
  }
}
