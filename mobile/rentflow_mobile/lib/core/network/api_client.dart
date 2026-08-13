import '../constants/api_constants.dart';

/// Placeholder for the application's shared network client.
class ApiClient {
  const ApiClient({this.baseUrl = ApiConstants.baseUrl});

  final String baseUrl;
}
