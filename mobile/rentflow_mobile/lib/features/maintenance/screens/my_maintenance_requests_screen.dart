import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../properties/models/property.dart';
import '../models/maintenance_attachment.dart';
import '../models/maintenance_status_history.dart';
import '../models/maintenance_request.dart';
import '../services/maintenance_api_service.dart';
import 'create_maintenance_request_screen.dart';

String _maintenanceEnumLabel(Enum value) {
  return value.name
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

class MyMaintenanceRequestsScreen extends StatefulWidget {
  const MyMaintenanceRequestsScreen({super.key, this.maintenanceApiService});

  final MaintenanceApiService? maintenanceApiService;

  @override
  State<MyMaintenanceRequestsScreen> createState() =>
      _MyMaintenanceRequestsScreenState();
}

class _MyMaintenanceRequestsScreenState
    extends State<MyMaintenanceRequestsScreen> {
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);

  ApiClient? _ownedApiClient;
  late final MaintenanceApiService _apiService;
  late Future<List<MaintenanceRequest>> _requests;
  bool _didLoad = false;
  bool _isLoadingProperties = false;

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

  Future<void> _refresh() async {
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

  Future<Property?> _selectProperty(List<Property> properties) async {
    if (properties.isEmpty) return null;
    return showDialog<Property>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a property'),
        children: properties
            .map(
              (property) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(property),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${property.address}, ${property.city}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _createRequest() async {
    if (_isLoadingProperties) return;
    setState(() => _isLoadingProperties = true);
    Property? property;
    try {
      final properties = await _apiService.getTenantProperties();
      if (!mounted) return;
      setState(() => _isLoadingProperties = false);
      if (properties.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No associated properties'),
            content: const Text(
              'A maintenance request can only be created for a property '
              'associated with your account.',
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
      property = await _selectProperty(properties);
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

    if (!mounted || property == null) return;
    final created = await Navigator.of(context).push<MaintenanceRequest>(
      MaterialPageRoute<MaintenanceRequest>(
        builder: (_) => CreateMaintenanceRequestScreen(
          propertyId: property!.id,
          maintenanceApiService: _apiService,
        ),
      ),
    );
    if (created != null && mounted) {
      await _refresh();
    }
  }

  Future<void> _showRequestDetails(MaintenanceRequest request) async {
    final currentUser = AuthScope.of(context).currentUser;
    if (currentUser == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _MaintenanceRequestDetailsDialog(
        request: request,
        tenantId: currentUser.id,
        maintenanceApiService: _apiService,
      ),
    );
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
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('My Maintenance Requests'),
        actions: [
          IconButton(
            tooltip: 'Create maintenance request',
            onPressed: _isLoadingProperties ? null : _createRequest,
            icon: _isLoadingProperties
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Refresh maintenance requests',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<MaintenanceRequest>>(
          future: _requests,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _olive),
              );
            }

            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load maintenance requests',
                message: _safeErrorMessage(snapshot.error),
                actionLabel: 'Try again',
                onAction: _refresh,
              );
            }

            final requests = snapshot.data ?? const <MaintenanceRequest>[];
            if (requests.isEmpty) {
              return _MessageState(
                icon: Icons.handyman_outlined,
                title: 'No maintenance requests yet',
                message: 'Your maintenance requests will appear here.',
                actionLabel: 'Refresh',
                onAction: _refresh,
              );
            }

            return RefreshIndicator(
              color: _olive,
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final request = requests[index];
                  return _MaintenanceRequestCard(
                    request: request,
                    onTap: () => _showRequestDetails(request),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MaintenanceRequestDetailsDialog extends StatefulWidget {
  const _MaintenanceRequestDetailsDialog({
    required this.request,
    required this.tenantId,
    required this.maintenanceApiService,
  });

  final MaintenanceRequest request;
  final String tenantId;
  final MaintenanceApiService maintenanceApiService;

  @override
  State<_MaintenanceRequestDetailsDialog> createState() =>
      _MaintenanceRequestDetailsDialogState();
}

class _MaintenanceRequestDetailsDialogState
    extends State<_MaintenanceRequestDetailsDialog> {
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
    return AlertDialog(
      title: Text(widget.request.title),
      content: FutureBuilder<MaintenanceRequest>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 64,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Text(_safeErrorMessage(snapshot.error));
          }
          final detail = snapshot.data!;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Status: ${_maintenanceEnumLabel(detail.status)}'),
                Text('Category: ${_maintenanceEnumLabel(detail.category)}'),
                Text('Priority: ${_maintenanceEnumLabel(detail.priority)}'),
                const SizedBox(height: 12),
                Text(detail.description),
                if (detail.tenantAccessNotes != null) ...[
                  const SizedBox(height: 12),
                  Text('Access notes: ${detail.tenantAccessNotes}'),
                ],
                _sectionTitle(context, 'History'),
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
                      return Text(
                        'Unable to load request history. '
                        '${_safeErrorMessage(snapshot.error)}',
                      );
                    }
                    final history =
                        snapshot.data ?? const <MaintenanceStatusHistory>[];
                    if (history.isEmpty) {
                      return const Text('No status history yet.');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: history
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                '${entry.fromStatus == null ? 'Created' : _maintenanceEnumLabel(entry.fromStatus!)}'
                                ' → ${_maintenanceEnumLabel(entry.toStatus)}\n'
                                '${MaterialLocalizations.of(context).formatMediumDate(entry.changedAt.toLocal())}'
                                '${entry.notes == null ? '' : '\n${entry.notes}'}',
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                _sectionTitle(context, 'Attachments'),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Photos and supporting files',
                        style: Theme.of(context).textTheme.bodySmall,
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
                      return Text(
                        'Unable to load attachments. '
                        '${_safeErrorMessage(snapshot.error)}',
                      );
                    }
                    final attachments =
                        snapshot.data ?? const <MaintenanceAttachment>[];
                    if (attachments.isEmpty) {
                      return const Text('No attachments yet.');
                    }
                    return Column(
                      children: attachments
                          .map(
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
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
  const _MaintenanceRequestCard({required this.request, required this.onTap});

  final MaintenanceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final createdAt = request.createdAt.toLocal();
    final createdDate = MaterialLocalizations.of(
      context,
    ).formatFullDate(createdAt);

    return Card(
      color: Colors.white,
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.build_outlined,
                    color: _MyMaintenanceRequestsScreenState._olive,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Created $createdDate',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(status: request.status),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    label: 'Category',
                    value: _maintenanceEnumLabel(request.category),
                  ),
                  _InfoPill(
                    label: 'Priority',
                    value: _maintenanceEnumLabel(request.priority),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFECEFDF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Color(0xFF5D6842),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MaintenanceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final label = _maintenanceEnumLabel(status);

    final Color background;
    final Color foreground;

    switch (status) {
      case MaintenanceRequestStatus.submitted:
      case MaintenanceRequestStatus.triaged:
      case MaintenanceRequestStatus.assigned:
        background = const Color(0xFFE5F1FF);
        foreground = const Color(0xFF1D4ED8);
      case MaintenanceRequestStatus.estimatePending:
      case MaintenanceRequestStatus.estimateSubmitted:
      case MaintenanceRequestStatus.awaitingLandlordApproval:
        background = const Color(0xFFFFF3CD);
        foreground = const Color(0xFF925F00);
      case MaintenanceRequestStatus.approved:
      case MaintenanceRequestStatus.inProgress:
      case MaintenanceRequestStatus.completed:
        background = const Color(0xFFE8F7ED);
        foreground = const Color(0xFF216E4E);
      case MaintenanceRequestStatus.rejected:
      case MaintenanceRequestStatus.cancelled:
        background = const Color(0xFFFDECEC);
        foreground = const Color(0xFF9F2D2D);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 52,
              color: _MyMaintenanceRequestsScreenState._olive,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
