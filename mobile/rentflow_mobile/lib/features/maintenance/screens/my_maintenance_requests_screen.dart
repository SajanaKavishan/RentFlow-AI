import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../properties/models/property.dart';
import '../models/maintenance_attachment.dart';
import '../models/maintenance_status_history.dart';
import '../models/maintenance_request.dart';
import '../services/maintenance_api_service.dart';
import '../services/maintenance_photo_picker.dart';
import '../widgets/tenant_maintenance_ui.dart';
import 'create_maintenance_request_screen.dart';

class MyMaintenanceRequestsScreen extends StatefulWidget {
  const MyMaintenanceRequestsScreen({
    super.key,
    this.maintenanceApiService,
    this.photoPicker,
  });

  final MaintenanceApiService? maintenanceApiService;
  final MaintenancePhotoPicker? photoPicker;

  @override
  State<MyMaintenanceRequestsScreen> createState() =>
      _MyMaintenanceRequestsScreenState();
}

class _MyMaintenanceRequestsScreenState
    extends State<MyMaintenanceRequestsScreen> {
  static const _olive = AppPalette.darkOlive;
  static const _warmBackground = AppPalette.warmCream;

  ApiClient? _ownedApiClient;
  late final MaintenanceApiService _apiService;
  late Future<List<MaintenanceRequest>> _requests;
  Future<void>? _refreshOperation;
  bool _didLoad = false;
  bool _isLoadingProperties = false;
  TenantMaintenanceFilter _filter = TenantMaintenanceFilter.all;
  final Set<String> _expandedIds = {};
  final Map<String, GlobalKey> _cardKeys = {};
  String? _trackId;

  @override
  void initState() {
    super.initState();
    if (widget.maintenanceApiService case final service?) {
      _apiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _apiService = MaintenanceApiService(_ownedApiClient!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    final currentUser = AuthScope.of(context).currentUser;
    if (currentUser == null) {
      _requests = Future.value(const <MaintenanceRequest>[]);
    } else {
      _requests = _apiService.getMyMaintenanceRequests(
        tenantId: currentUser.id,
      );
    }
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _refresh() => _refreshOperation ??= _reloadRequests()
      .whenComplete(() => _refreshOperation = null);

  Future<void> _reloadRequests() async {
    final currentUser = AuthScope.of(context).currentUser;
    if (currentUser == null) {
      setState(() {
        _requests = Future.value(const <MaintenanceRequest>[]);
      });
      return;
    }

    final request = _apiService.getMyMaintenanceRequests(
      tenantId: currentUser.id,
    );
    setState(() {
      _requests = request;
    });

    try {
      await request;
    } catch (_) {
      // FutureBuilder displays a safe error state for this request.
    }
  }

  Future<void> _createRequest() async {
    if (_isLoadingProperties) return;
    setState(() => _isLoadingProperties = true);
    List<Property> eligibleProperties = [];
    try {
      final properties = await _apiService.getTenantProperties();
      if (!mounted) return;
      setState(() => _isLoadingProperties = false);
      if (properties.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppPalette.white,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            contentPadding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
            actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppPalette.outline),
            ),
            titleTextStyle: const TextStyle(
              fontSize: 18,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: AppPalette.primaryText,
            ),
            title: const Text('No associated properties'),
            content: const Text(
              'An active lease for this property is required before '
              'you can submit a maintenance request.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppPalette.secondaryText,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      eligibleProperties = properties;
    } on MaintenanceApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to load your associated properties.'),
          ),
        );
      return;
    } finally {
      if (mounted) setState(() => _isLoadingProperties = false);
    }

    if (!mounted || eligibleProperties.isEmpty) return;
    final created = await Navigator.of(context).push<MaintenanceRequest>(
      MaterialPageRoute<MaintenanceRequest>(
        builder: (_) => CreateMaintenanceRequestScreen(
          propertyId: eligibleProperties.first.id,
          properties: eligibleProperties,
          photoPicker: widget.photoPicker,
          maintenanceApiService: _apiService,
        ),
      ),
    );
    if (!mounted) return;
    if (created != null) {
      setState(() {
        _filter = TenantMaintenanceFilter.all;
        _expandedIds.add(created.id);
        _trackId = created.id;
      });
    }
    // Also refresh when a tenant leaves confirmation with system Back.
    if (_refreshOperation case final refresh?) await refresh;
    if (!mounted) return;
    await _refresh();
  }

  String _safeErrorMessage(Object? error) {
    if (error is MaintenanceApiException) {
      return error.message;
    }

    return 'Unable to load your maintenance requests. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _warmBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              key: const ValueKey('maintenance-header'),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final title = Text(
                    key: const ValueKey('maintenance-title'),
                    'Maintenance',
                    style: AppTypography.pageTitle.copyWith(
                      fontSize: 22,
                      color: AppPalette.primaryText,
                    ),
                  );
                  final action = Tooltip(
                    message: 'Create maintenance request',
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: textScale > 1.45 ? 260 : 150,
                      ),
                      child: FilledButton.icon(
                        key: const ValueKey('new-maintenance-request'),
                        onPressed: _isLoadingProperties ? null : _createRequest,
                        style: FilledButton.styleFrom(
                          backgroundColor: _olive,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(44, 42),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _isLoadingProperties
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: 'Loading properties',
                                ),
                              )
                            : const Icon(Icons.add, size: 16),
                        label: const Text('New Request'),
                      ),
                    ),
                  );
                  if (textScale > 1.45) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 8), action],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 10),
                      action,
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: _olive,
                onRefresh: _refresh,
                child: FutureBuilder<List<MaintenanceRequest>>(
                  future: _requests,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData &&
                        !snapshot.hasError) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: _olive,
                          semanticsLabel: 'Loading maintenance requests',
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: _MessageState(
                                  icon: Icons.cloud_off_outlined,
                                  title: 'Could not load maintenance requests',
                                  message: _safeErrorMessage(snapshot.error),
                                  actionLabel: 'Retry',
                                  onAction: _refresh,
                                ),
                              ),
                            ),
                      );
                    }
                    final requests =
                        snapshot.data ?? const <MaintenanceRequest>[];
                    final visible = requests
                        .where((r) => _filter.includes(r.status))
                        .toList();
                    if (_trackId != null &&
                        visible.any((r) => r.id == _trackId)) {
                      final trackedId = _trackId!;
                      _trackId = null;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final cardContext =
                            _cardKeys[trackedId]?.currentContext;
                        if (mounted && cardContext != null) {
                          Scrollable.ensureVisible(
                            cardContext,
                            duration: const Duration(milliseconds: 250),
                          );
                        }
                      });
                    }
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              key: const ValueKey('maintenance-summary-row'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final group
                                    in TenantMaintenanceFilter.values.skip(
                                      1,
                                    )) ...[
                                  Expanded(
                                    child: _SummaryCard(
                                      group: group,
                                      count: requests
                                          .where(
                                            (r) => group.includes(r.status),
                                          )
                                          .length,
                                    ),
                                  ),
                                  if (group != TenantMaintenanceFilter.resolved)
                                    const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            key: const ValueKey('maintenance-filter-strip'),
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final filter
                                    in TenantMaintenanceFilter.values) ...[
                                  ChoiceChip(
                                    key: ValueKey('filter-${filter.name}'),
                                    label: Text(filter.label),
                                    selected: _filter == filter,
                                    showCheckmark: false,
                                    selectedColor: _olive,
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: AppPalette.outline,
                                    ),
                                    shape: const StadiumBorder(),
                                    labelPadding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: const VisualDensity(
                                      horizontal: -2,
                                      vertical: -3,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    labelStyle: TextStyle(
                                      color: _filter == filter
                                          ? Colors.white
                                          : AppPalette.primaryText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    onSelected: (_) =>
                                        setState(() => _filter = filter),
                                  ),
                                  if (filter !=
                                      TenantMaintenanceFilter.resolved)
                                    const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 13),
                          const Divider(
                            key: ValueKey('maintenance-section-divider'),
                            height: 1,
                            thickness: 1,
                            color: AppPalette.outline,
                          ),
                          const SizedBox(height: 14),
                          if (requests.isEmpty)
                            _MessageState(
                              icon: Icons.handyman_outlined,
                              title: 'No maintenance requests yet.',
                              message:
                                  'Your maintenance requests will appear here.',
                            )
                          else if (visible.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Text(
                                'No requests in this filter.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            for (final request in visible)
                              Padding(
                                key: _cardKeys.putIfAbsent(
                                  request.id,
                                  GlobalKey.new,
                                ),
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _MaintenanceRequestCard(
                                  request: request,
                                  expanded: _expandedIds.contains(request.id),
                                  onTap: () => setState(() {
                                    if (!_expandedIds.remove(request.id)) {
                                      _expandedIds.add(request.id);
                                    }
                                  }),
                                  details:
                                      _expandedIds.contains(request.id) &&
                                          AuthScope.of(context).currentUser !=
                                              null
                                      ? _MaintenanceRequestDetails(
                                          key: ValueKey('detail-${request.id}'),
                                          request: request,
                                          tenantId: AuthScope.of(
                                            context,
                                          ).currentUser!.id,
                                          maintenanceApiService: _apiService,
                                        )
                                      : null,
                                ),
                              ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.group, required this.count});

  final TenantMaintenanceFilter group;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (group) {
      TenantMaintenanceFilter.open => (
        const Color(0xFFFFF4D8),
        AppPalette.warning,
      ),
      TenantMaintenanceFilter.inProgress => (
        const Color(0xFFE9EDE1),
        AppPalette.darkOlive,
      ),
      TenantMaintenanceFilter.resolved => (
        const Color(0xFFE7F2E2),
        AppPalette.success,
      ),
      TenantMaintenanceFilter.all => (
        AppPalette.softCream,
        AppPalette.primaryText,
      ),
    };

    return Semantics(
      label: '$count ${group.label} maintenance requests',
      container: true,
      excludeSemantics: true,
      child: Container(
        key: ValueKey('summary-${group.name}'),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              key: ValueKey('count-${group.name}'),
              style: TextStyle(
                height: 1,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              group.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                height: 1.15,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppPalette.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceRequestDetails extends StatefulWidget {
  const _MaintenanceRequestDetails({
    super.key,
    required this.request,
    required this.tenantId,
    required this.maintenanceApiService,
  });

  final MaintenanceRequest request;
  final String tenantId;
  final MaintenanceApiService maintenanceApiService;

  @override
  State<_MaintenanceRequestDetails> createState() =>
      _MaintenanceRequestDetailsState();
}

class _MaintenanceRequestDetailsState
    extends State<_MaintenanceRequestDetails> {
  late Future<MaintenanceRequest> _detail;
  late Future<List<MaintenanceStatusHistory>> _history;
  late Future<List<MaintenanceAttachment>> _attachments;
  bool _isPicking = false;
  bool _isUploading = false;
  final Set<String> _openingIds = {};
  final Set<String> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    _detail = widget.maintenanceApiService.getMaintenanceRequestById(
      widget.request.id,
    );
    _history = widget.maintenanceApiService.getMaintenanceRequestHistory(
      maintenanceRequestId: widget.request.id,
    );
    _attachments = _loadAttachments();
  }

  Future<List<MaintenanceAttachment>> _loadAttachments() {
    return widget.maintenanceApiService.getMaintenanceRequestAttachments(
      maintenanceRequestId: widget.request.id,
      tenantId: widget.tenantId,
    );
  }

  Future<void> _refreshAttachments() async {
    final refreshed = _loadAttachments();
    setState(() => _attachments = refreshed);
    try {
      await refreshed;
    } catch (_) {
      // The FutureBuilder renders the safe error state.
    }
  }

  Future<void> _uploadAttachment() async {
    if (_isPicking || _isUploading) return;
    setState(() => _isPicking = true);
    _SelectedMaintenanceFile? file;
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (selected != null) {
        file = _SelectedMaintenanceFile(
          name: selected.name,
          bytes: await selected.readAsBytes(),
        );
      }
    } on Exception {
      if (mounted) _showMessage('Unable to select an attachment.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
    if (!mounted || file == null) return;
    if (file.bytes.isEmpty) {
      _showMessage('The selected attachment could not be read.');
      return;
    }
    if (file.bytes.length > MaintenancePhoto.maximumBytes) {
      _showMessage('Each photo must be 10 MB or smaller.');
      return;
    }

    final contentType = _contentTypeFor(file.name);
    if (contentType == null) {
      _showMessage('Only JPEG, PNG, and WEBP attachments are supported.');
      return;
    }

    setState(() => _isUploading = true);
    try {
      await widget.maintenanceApiService.uploadMaintenanceAttachment(
        maintenanceRequestId: widget.request.id,
        tenantId: widget.tenantId,
        fileName: file.name,
        contentType: contentType,
        bytes: file.bytes,
      );
      if (!mounted) return;
      _showMessage('Attachment uploaded.');
      await _refreshAttachments();
    } on MaintenanceApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Unable to upload the attachment.');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _openAttachment(MaintenanceAttachment attachment) async {
    if (_openingIds.contains(attachment.id)) return;
    setState(() => _openingIds.add(attachment.id));
    try {
      final url = await widget.maintenanceApiService
          .requestMaintenanceAttachmentDownloadUrl(
            maintenanceRequestId: widget.request.id,
            attachmentId: attachment.id,
            tenantId: widget.tenantId,
          );
      if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
          mounted) {
        _showMessage('No app was available to open this attachment.');
      }
    } on MaintenanceApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Unable to open the attachment.');
    } finally {
      if (mounted) setState(() => _openingIds.remove(attachment.id));
    }
  }

  Future<void> _deleteAttachment(MaintenanceAttachment attachment) async {
    if (_deletingIds.contains(attachment.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this attachment?'),
        content: Text('${attachment.fileName} will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingIds.add(attachment.id));
    try {
      await widget.maintenanceApiService.deleteMaintenanceAttachment(
        maintenanceRequestId: widget.request.id,
        attachmentId: attachment.id,
        tenantId: widget.tenantId,
      );
      if (!mounted) return;
      _showMessage('Attachment deleted.');
      await _refreshAttachments();
    } on MaintenanceApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Unable to delete the attachment.');
    } finally {
      if (mounted) setState(() => _deletingIds.remove(attachment.id));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _contentTypeFor(String name) {
    return switch (name.toLowerCase().split('.').last) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: FutureBuilder<MaintenanceRequest>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 64,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_safeErrorMessage(snapshot.error)),
                TextButton(
                  onPressed: () => setState(() {
                    _detail = widget.maintenanceApiService
                        .getMaintenanceRequestById(widget.request.id);
                  }),
                  child: const Text('Retry details'),
                ),
              ],
            );
          }
          final detail = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionTitle(context, 'DESCRIPTION', top: 0),
              Text(
                detail.description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppPalette.secondaryText,
                ),
              ),
              if (detail.preferredAccessWindow case final access?) ...[
                _sectionTitle(context, 'PREFERRED ACCESS'),
                Text(
                  access.label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppPalette.primaryText,
                  ),
                ),
              ],
              if (detail.tenantAccessNotes != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Access notes: ${detail.tenantAccessNotes}',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppPalette.primaryText,
                  ),
                ),
              ],
              FutureBuilder<List<MaintenanceStatusHistory>>(
                future: _history,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unable to load request history. '
                          '${_safeErrorMessage(snapshot.error)}',
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _history = widget.maintenanceApiService
                                .getMaintenanceRequestHistory(
                                  maintenanceRequestId: widget.request.id,
                                );
                          }),
                          child: const Text('Retry history'),
                        ),
                      ],
                    );
                  }
                  final history =
                      snapshot.data ?? const <MaintenanceStatusHistory>[];
                  if (history.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(context, 'UPDATES'),
                      ...history.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 4, right: 10),
                                child: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: AppPalette.olive,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${entry.fromStatus == null ? 'Created' : maintenanceLabel(entry.fromStatus!)}'
                                      ' → ${maintenanceLabel(entry.toStatus)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: AppPalette.primaryText,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${MaterialLocalizations.of(context).formatMediumDate(entry.changedAt.toLocal())}'
                                      ' · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.changedAt.toLocal()))}'
                                      '${entry.notes == null ? '' : '\n${entry.notes}'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: AppPalette.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Photos and supporting files',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppPalette.secondaryText,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isPicking || _isUploading
                        ? null
                        : _uploadAttachment,
                    icon: _isPicking || _isUploading
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file),
                    label: const Text('Add'),
                  ),
                ],
              ),
              FutureBuilder<List<MaintenanceAttachment>>(
                future: _attachments,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unable to load attachments. '
                          '${_safeErrorMessage(snapshot.error)}',
                        ),
                        TextButton(
                          onPressed: _refreshAttachments,
                          child: const Text('Retry attachments'),
                        ),
                      ],
                    );
                  }
                  final attachments =
                      snapshot.data ?? const <MaintenanceAttachment>[];
                  if (attachments.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(context, 'ATTACHMENTS'),
                      ...attachments.map(
                        (attachment) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.insert_drive_file),
                          title: Text(attachment.fileName),
                          subtitle: Text(
                            '${attachment.contentType} · '
                            '${_formatFileSize(attachment.fileSize)}',
                          ),
                          onTap: () => _openAttachment(attachment),
                          trailing: IconButton(
                            tooltip: 'Delete attachment',
                            onPressed: _deletingIds.contains(attachment.id)
                                ? null
                                : () => _deleteAttachment(attachment),
                            icon: _deletingIds.contains(attachment.id)
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, {double top = 16}) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 7),
      child: Text(
        title,
        style: AppTypography.eyebrow.copyWith(
          color: AppPalette.primaryText,
          letterSpacing: .7,
        ),
      ),
    );
  }
}

String _safeErrorMessage(Object? error) {
  if (error is MaintenanceApiException) return error.message;
  return 'Please try again.';
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _SelectedMaintenanceFile {
  const _SelectedMaintenanceFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class _MaintenanceRequestCard extends StatelessWidget {
  const _MaintenanceRequestCard({
    required this.request,
    required this.onTap,
    required this.expanded,
    this.details,
  });
  final MaintenanceRequest request;
  final VoidCallback onTap;
  final bool expanded;
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C303C1F),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: ValueKey('request-toggle-${request.id}'),
            button: true,
            expanded: expanded,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MaintenanceSurface(
                        padding: const EdgeInsets.all(7),
                        radius: 11,
                        selected: true,
                        child: Icon(
                          maintenanceCategoryIcon(request.category),
                          size: 18,
                          color: AppPalette.darkOlive,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.title,
                              style: AppTypography.cardTitle.copyWith(
                                fontSize: 14,
                                color: AppPalette.primaryText,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                maintenanceLabel(request.category),
                                if (request.referenceCode != null)
                                  request.referenceCode!,
                              ].join(' \u00b7 '),
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: AppPalette.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 7),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final badges = Wrap(
                                  spacing: 5,
                                  runSpacing: 5,
                                  children: [
                                    MaintenanceBadge.status(request.status),
                                    MaintenanceBadge.priority(request.priority),
                                  ],
                                );
                                final date = Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(
                                    request.createdAt.toLocal(),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.4,
                                    color: AppPalette.secondaryText,
                                  ),
                                );
                                if (MediaQuery.textScalerOf(context).scale(1) >
                                    1.3) {
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [badges, date],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(child: badges),
                                    const SizedBox(width: 6),
                                    date,
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: AppPalette.olive,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (details != null) ...[
            const Divider(height: 1, color: AppPalette.outline),
            Material(color: Colors.transparent, child: details!),
          ],
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppPalette.progress,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 21,
                color: _MyMaintenanceRequestsScreenState._olive,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: AppPalette.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppPalette.secondaryText,
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                key: ValueKey('maintenance-$actionLabel-action'),
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  side: const BorderSide(color: AppPalette.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
