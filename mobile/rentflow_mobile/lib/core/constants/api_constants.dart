abstract final class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5277',
  );

  static const String propertiesPath = '/api/properties';
  static const String viewingsPath = '/api/viewings';
  static const String rentalApplicationsPath = '/api/rental-applications';
  static const String applicationDocumentsPath = '/api/application-documents';
  static const String notificationsPath = '/api/notifications';
  static const String authPath = '/api/auth';
}