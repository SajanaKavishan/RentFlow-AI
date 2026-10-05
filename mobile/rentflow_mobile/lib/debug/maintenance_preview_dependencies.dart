import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/auth/token_storage.dart';
import '../core/network/api_client.dart';
import '../features/auth/controllers/auth_controller.dart';
import '../features/auth/models/current_user.dart';
import '../features/auth/services/auth_service.dart';
import '../features/maintenance/models/maintenance_attachment.dart';
import '../features/maintenance/models/maintenance_request.dart';
import '../features/maintenance/models/maintenance_status_history.dart';
import '../features/maintenance/services/maintenance_api_service.dart';
import '../features/maintenance/services/maintenance_photo_picker.dart';
import '../features/properties/models/property.dart';

/// Owned only by the separate debug entry point. No live transport or storage.
class MaintenancePreviewDependencies {
  factory MaintenancePreviewDependencies() {
    if (!kDebugMode) {
      throw UnsupportedError('Maintenance preview requires a debug build.');
    }
    final storage = _PreviewTokenStorage();
    final client = ApiClient(
      baseUrl: 'https://maintenance-preview.invalid',
      tokenStorage: storage,
      httpClient: _OfflineClient(),
    );
    return MaintenancePreviewDependencies._(
      client,
      AuthController(
        authService: _PreviewAuthService(client),
        tokenStorage: storage,
      ),
      MaintenancePreviewService._(client),
    );
  }

  MaintenancePreviewDependencies._(this._client, this.auth, this.maintenance);

  final ApiClient _client;
  final AuthController auth;
  final MaintenancePreviewService maintenance;
  // Optional native capture exercises permissions without enabling live API I/O.
  final MaintenancePhotoPicker photoPicker =
      const bool.fromEnvironment('MAINTENANCE_PREVIEW_USE_PLATFORM_PICKER')
      ? PlatformMaintenancePhotoPicker()
      : PreviewMaintenancePhotoPicker();

  void dispose() {
    auth.dispose();
    _client.close();
  }
}

String _id(int number) =>
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';

final _fixtureTime = DateTime.utc(2026, 10, 5, 9);
final _tenantId = _id(1);
final _propertyId = _id(2);

class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('The maintenance preview cannot make network requests.');
  }
}

class _PreviewTokenStorage implements TokenStorage {
  String? _token = 'debug-preview-session';

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> deleteToken() async => _token = null;
}

class _PreviewAuthService extends AuthService {
  const _PreviewAuthService(super.apiClient);

  @override
  Future<CurrentUser> getCurrentUser() async => CurrentUser(
    id: _tenantId,
    fullName: 'Preview Tenant',
    email: 'tenant@preview.invalid',
    phoneNumber: '+94000000000',
    role: UserRole.tenant,
  );
}

/// Typed overrides for the real tenant screens, with session-local mutations.
class MaintenancePreviewService extends MaintenanceApiService {
  MaintenancePreviewService._(super.apiClient) {
    final fixtures = [
      (
        'Kitchen faucet dripping',
        'Water drips from the kitchen faucet and pools below the sink.',
        MaintenanceCategory.plumbing,
        MaintenancePriority.high,
        [MaintenanceRequestStatus.submitted],
      ),
      (
        'Bedroom outlet not working',
        'The outlet beside the bedroom door has stopped supplying power.',
        MaintenanceCategory.electrical,
        MaintenancePriority.normal,
        [
          MaintenanceRequestStatus.submitted,
          MaintenanceRequestStatus.assigned,
          MaintenanceRequestStatus.inProgress,
        ],
      ),
      (
        'Refrigerator making unusual noise',
        'A grinding noise came from the refrigerator. The fan was replaced.',
        MaintenanceCategory.appliance,
        MaintenancePriority.low,
        [
          MaintenanceRequestStatus.submitted,
          MaintenanceRequestStatus.assigned,
          MaintenanceRequestStatus.inProgress,
          MaintenanceRequestStatus.completed,
        ],
      ),
    ];
    for (var index = 0; index < fixtures.length; index++) {
      final (title, description, category, priority, statuses) =
          fixtures[index];
      final createdAt = _fixtureTime.subtract(Duration(days: index + 1));
      final request = _request(
        id: _id(1001 + index),
        title: title,
        description: description,
        category: category,
        priority: priority,
        status: statuses.last,
        createdAt: createdAt,
        updatedAt: createdAt.add(Duration(hours: statuses.length - 1)),
        tenantAccessNotes: 'Please knock before entering.',
        preferredAccessWindow: index == 2
            ? null
            : PreferredAccessWindow.morning,
      );
      _requests.add(request);
      _history[request.id] = [
        for (var step = 0; step < statuses.length; step++)
          MaintenanceStatusHistory(
            id: _id(4000 + index * 10 + step),
            fromStatus: step == 0 ? null : statuses[step - 1],
            toStatus: statuses[step],
            changedAt: createdAt.add(Duration(hours: step)),
            notes: statuses[step] == MaintenanceRequestStatus.completed
                ? 'Fan replaced and tested.'
                : null,
          ),
      ];
    }
    _attachments[_requests.first.id] = [
      MaintenanceAttachment(
        id: _id(3000),
        maintenanceRequestId: _requests.first.id,
        fileName: 'kitchen-faucet.jpg',
        contentType: 'image/jpeg',
        fileSize: 2048,
        attachmentType: null,
        uploadedByUserId: _tenantId,
        createdAt: _requests.first.createdAt,
      ),
    ];
  }

  final List<MaintenanceRequest> _requests = [];
  final Map<String, List<MaintenanceStatusHistory>> _history = {};
  final Map<String, List<MaintenanceAttachment>> _attachments = {};
  int _createdCount = 0;
  int _attachmentCount = 0;

  MaintenanceRequest _request({
    required String id,
    required String title,
    required String description,
    required MaintenanceCategory category,
    required MaintenancePriority priority,
    required MaintenanceRequestStatus status,
    required DateTime createdAt,
    DateTime? updatedAt,
    String? tenantAccessNotes,
    PreferredAccessWindow? preferredAccessWindow,
  }) => MaintenanceRequest(
    id: id,
    referenceCode: 'MR-20261005${id.substring(id.length - 8)}',
    preferredAccessWindow: preferredAccessWindow,
    propertyId: _propertyId,
    tenantId: _tenantId,
    technicianId: status == MaintenanceRequestStatus.submitted ? null : _id(4),
    title: title,
    description: description,
    category: category,
    priority: priority,
    status: status,
    tenantAccessNotes: tenantAccessNotes,
    triageNotes: null,
    assignmentNotes: null,
    cancellationReason: null,
    completedAt: status == MaintenanceRequestStatus.completed
        ? updatedAt
        : null,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  @override
  Future<List<Property>> getTenantProperties() async => [
    Property(
      id: _propertyId,
      landlordId: _id(3),
      title: 'Preview apartment',
      description: 'Debug fixture for visual inspection.',
      address: '12 Preview Lane',
      city: 'Colombo',
      monthlyRent: 100000,
      bedrooms: 2,
      bathrooms: 1,
      isAvailable: false,
      createdAt: _fixtureTime,
      updatedAt: null,
      amenities: const [],
    ),
  ];

  @override
  Future<List<MaintenanceRequest>> getMyMaintenanceRequests({
    required String tenantId,
  }) async =>
      _requests.where((request) => request.tenantId == tenantId).toList();

  @override
  Future<MaintenanceRequest> getMaintenanceRequestById(String id) async =>
      _requests.firstWhere((request) => request.id == id);

  @override
  Future<List<MaintenanceStatusHistory>> getMaintenanceRequestHistory({
    required String maintenanceRequestId,
  }) async => List.of(_history[maintenanceRequestId] ?? []);

  @override
  Future<List<MaintenanceAttachment>> getMaintenanceRequestAttachments({
    required String maintenanceRequestId,
    required String tenantId,
  }) async => List.of(_attachments[maintenanceRequestId] ?? []);

  @override
  Future<MaintenanceRequest> createMaintenanceRequest({
    required String tenantId,
    required String propertyId,
    String? title,
    required String description,
    required MaintenanceCategory category,
    required MaintenancePriority priority,
    required PreferredAccessWindow preferredAccessWindow,
    String? tenantAccessNotes,
  }) async {
    if (tenantId != _tenantId || propertyId != _propertyId) {
      throw const MaintenanceApiException(
        'Unknown preview tenant or property.',
      );
    }
    final createdAt = _fixtureTime.add(Duration(minutes: _createdCount));
    final request = _request(
      id: _id(2000 + _createdCount++),
      title: title == null || title.trim().isEmpty
          ? _displayTitle(description, category)
          : title.trim(),
      description: description,
      category: category,
      priority: priority,
      status: MaintenanceRequestStatus.submitted,
      createdAt: createdAt,
      tenantAccessNotes: tenantAccessNotes,
      preferredAccessWindow: preferredAccessWindow,
    );
    _requests.insert(0, request);
    _history[request.id] = [
      MaintenanceStatusHistory(
        id: _id(5000 + _createdCount),
        fromStatus: null,
        toStatus: request.status,
        changedAt: createdAt,
        notes: null,
      ),
    ];
    return request;
  }

  @override
  Future<MaintenanceAttachment> uploadMaintenanceAttachment({
    required String maintenanceRequestId,
    required String tenantId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
    String? attachmentType,
  }) async {
    if ((_attachments[maintenanceRequestId]?.length ?? 0) >=
        MaintenancePhoto.maximumCount) {
      throw const MaintenanceApiException('A request can have up to 5 photos.');
    }
    await getMaintenanceRequestById(maintenanceRequestId);
    if (tenantId != _tenantId) {
      throw const MaintenanceApiException('Unknown preview tenant.');
    }
    final attachment = MaintenanceAttachment(
      id: _id(3001 + _attachmentCount++),
      maintenanceRequestId: maintenanceRequestId,
      fileName: fileName,
      contentType: contentType,
      fileSize: bytes.length,
      attachmentType: attachmentType,
      uploadedByUserId: tenantId,
      createdAt: _fixtureTime,
    );
    (_attachments[maintenanceRequestId] ??= []).add(attachment);
    return attachment;
  }

  String _displayTitle(String description, MaintenanceCategory category) {
    final normalized = description.trim().replaceAll(RegExp(r'\s+'), ' ');
    final sentence = RegExp(r'^.*?[.!?](?=\s|$)').firstMatch(normalized);
    final title = sentence == null
        ? normalized
        : sentence.group(0)!.replaceFirst(RegExp(r'[.!?]+$'), '');
    if (title.trim().isEmpty) {
      return '${category.name[0].toUpperCase()}${category.name.substring(1)} issue';
    }
    if (title.length <= 200) return title;
    final boundary = title.lastIndexOf(' ', 199);
    return title.substring(0, boundary > 0 ? boundary : 200).trimRight();
  }

  @override
  Future<void> deleteMaintenanceAttachment({
    required String maintenanceRequestId,
    required String attachmentId,
    required String tenantId,
  }) async {
    _attachments[maintenanceRequestId]?.removeWhere(
      (a) => a.id == attachmentId,
    );
  }

  @override
  Future<Uri> requestMaintenanceAttachmentDownloadUrl({
    required String maintenanceRequestId,
    required String attachmentId,
    required String tenantId,
  }) async {
    throw const MaintenanceApiException(
      'Attachment downloads are unavailable in the offline preview.',
    );
  }
}

/// Fixture images are selected locally and pass the production image validation.
class PreviewMaintenancePhotoPicker extends MaintenancePhotoPicker {
  PreviewMaintenancePhotoPicker({this.permissionDenied = false});
  final bool permissionDenied;

  @override
  Future<List<MaintenancePhoto>> pick(MaintenancePhotoSource source) async {
    if (permissionDenied) {
      throw const MaintenancePhotoPickerException(
        'Camera access is denied. You can allow it in your device settings.',
      );
    }
    final bytes = (await rootBundle.load(
      'assets/auth/residence.png',
    )).buffer.asUint8List();
    return [
      for (
        var index = 0;
        index < (source == MaintenancePhotoSource.camera ? 1 : 3);
        index++
      )
        MaintenancePhoto(
          fileName: 'preview-photo-${index + 1}.png',
          bytes: bytes,
          contentType: 'image/png',
        ),
    ];
  }
}
