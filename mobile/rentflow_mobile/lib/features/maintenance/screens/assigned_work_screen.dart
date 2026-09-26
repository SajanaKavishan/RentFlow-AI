import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/maintenance_request.dart';
import '../services/maintenance_api_service.dart';

class AssignedWorkScreen extends StatefulWidget {
  const AssignedWorkScreen({
    super.key,
    this.maintenanceApiService,
    this.request,
    this.requestId,
  });

  final MaintenanceApiService? maintenanceApiService;
  final MaintenanceRequest? request;
  final String? requestId;

  @override
  State<AssignedWorkScreen> createState() => _AssignedWorkScreenState();
}

class _AssignedWorkScreenState extends State<AssignedWorkScreen> {
  ApiClient? _ownedApiClient;
  late final MaintenanceApiService _apiService;
  MaintenanceRequest? _request;
  List<MaintenanceRequest> _assignedWork = const [];

  bool _isStartingWork = false;
  bool _isCompletingWork = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _request = widget.request;
    if (widget.maintenanceApiService case final service?) {
      _apiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _apiService = MaintenanceApiService(_ownedApiClient!);
    }
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  MaintenanceRequest? get _activeRequest =>
      _request ?? (_assignedWork.isNotEmpty ? _assignedWork.first : null);

  bool get _hasActionableRequest =>
      _activeRequest != null ||
      (widget.requestId != null && widget.requestId!.trim().isNotEmpty);

  bool get _canStartWork => _activeRequest?.status == MaintenanceRequestStatus.approved;

  bool get _canCompleteWork =>
      _activeRequest?.status == MaintenanceRequestStatus.inProgress;

  Future<MaintenanceRequest?> _loadRequest() async {
    if (_request != null) {
      return _request;
    }

    final id = widget.requestId?.trim();
    if (id == null || id.isEmpty) {
      final technicianId = _resolveTechnicianId();
      if (technicianId == null) {
        return null;
      }
      final assignedWork = await _apiService.getAssignedWork(technicianId: technicianId);
      if (mounted) {
        setState(() => _assignedWork = assignedWork);
      }
      return assignedWork.isEmpty ? null : assignedWork.first;
    }

    final loaded = await _apiService.getMaintenanceRequestById(id);
    if (mounted) {
      setState(() => _request = loaded);
    }
    return loaded;
  }

  String? _resolveTechnicianId() {
    final request = widget.request;
    if (request != null && request.technicianId != null) {
      return request.technicianId;
    }
    return null;
  }

  Future<void> _startWork(MaintenanceRequest request) async {
    if (_isStartingWork || _isCompletingWork) return;

    setState(() {
      _isStartingWork = true;
      _errorMessage = null;
    });

    try {
      final updated = await _apiService.startWork(id: request.id);
      if (!mounted) return;
      setState(() {
        _request = updated;
        _errorMessage = null;
      });
      AppSnackbars.show(
        context,
        message: 'Work started for ${updated.title}.',
        tone: SnackTone.success,
      );
    } on MaintenanceApiException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
        AppSnackbars.show(context, message: error.message, tone: SnackTone.error);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Unable to start this maintenance request right now.',
        );
        AppSnackbars.show(
          context,
          message: 'Unable to start this maintenance request right now.',
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStartingWork = false);
      }
    }
  }

  Future<void> _completeWork(MaintenanceRequest request) async {
    if (_isStartingWork || _isCompletingWork) return;

    setState(() {
      _isCompletingWork = true;
      _errorMessage = null;
    });

    try {
      final updated = await _apiService.completeWork(id: request.id);
      if (!mounted) return;
      setState(() {
        _request = updated;
        _errorMessage = null;
      });
      AppSnackbars.show(
        context,
        message: 'Work completed for ${updated.title}.',
        tone: SnackTone.success,
      );
    } on MaintenanceApiException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
        AppSnackbars.show(context, message: error.message, tone: SnackTone.error);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Unable to complete this maintenance request right now.',
        );
        AppSnackbars.show(
          context,
          message: 'Unable to complete this maintenance request right now.',
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCompletingWork = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = _loadRequest();
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: const Text('Assigned Work'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: FutureBuilder<MaintenanceRequest?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppPalette.olive),
            );
          }

          if (snapshot.hasError) {
            final message = snapshot.error is MaintenanceApiException
                ? (snapshot.error as MaintenanceApiException).message
                : 'Unable to load the assigned maintenance work.';
            return AuthenticatedPage(
              child: SharedState(
                title: 'Could not load work order',
                message: message,
                icon: Icons.error_outline,
                actionLabel: 'Retry',
                onAction: () => setState(() {}),
              ),
            );
          }

          final request = _request ?? snapshot.data;
          final hasAssignedWork = _assignedWork.isNotEmpty || (request != null && _hasActionableRequest);
          if (!hasAssignedWork) {
            return AuthenticatedPage(
              child: SharedState(
                title: 'No assigned work found',
                message:
                    'This technician workspace will show active maintenance tasks once a request is assigned.',
                icon: Icons.handyman_outlined,
              ),
            );
          }

          final activeRequest = request ?? _assignedWork.first;
          return AuthenticatedPage(
            maxWidth: 620,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              activeRequest.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          StatusChip(
                            label: _statusLabel(activeRequest.status),
                            tone: _statusTone(activeRequest.status),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        activeRequest.description,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Work details'),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    children: [
                      _InfoRow(label: 'Property', value: activeRequest.propertyId),
                      const Divider(height: AppSpacing.lg),
                      _InfoRow(label: 'Tenant', value: activeRequest.tenantId),
                      const Divider(height: AppSpacing.lg),
                      _InfoRow(
                        label: 'Priority',
                        value: _capitalise(activeRequest.priority.name),
                      ),
                      const Divider(height: AppSpacing.lg),
                      _InfoRow(
                        label: 'Category',
                        value: _capitalise(activeRequest.category.name),
                      ),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ActionError(message: _errorMessage!),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (_canStartWork) ...[
                  FilledButton.icon(
                    key: const ValueKey('start-maintenance-work'),
                    onPressed: _isStartingWork || _isCompletingWork ? null : () => _startWork(activeRequest),
                    icon: _isStartingWork
                        ? const _ButtonProgress()
                        : const Icon(Icons.play_arrow_outlined),
                    label: Text(_isStartingWork ? 'Starting work...' : 'Start work'),
                  ),
                ] else if (_canCompleteWork) ...[
                  FilledButton.icon(
                    key: const ValueKey('complete-maintenance-work'),
                    onPressed: _isStartingWork || _isCompletingWork ? null : () => _completeWork(activeRequest),
                    icon: _isCompletingWork
                        ? const _ButtonProgress()
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_isCompletingWork ? 'Completing work...' : 'Complete work'),
                  ),
                ] else ...[
                  AppCard(
                    color: AppPalette.softCream,
                    child: Text(
                      'This request is currently ${_statusLabel(activeRequest.status).toLowerCase()} and is waiting for the next maintenance stage.',
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(MaintenanceRequestStatus status) => status.name
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ');

  StatusTone _statusTone(MaintenanceRequestStatus status) => switch (status) {
    MaintenanceRequestStatus.approved => StatusTone.success,
    MaintenanceRequestStatus.inProgress => StatusTone.progress,
    MaintenanceRequestStatus.completed => StatusTone.success,
    MaintenanceRequestStatus.rejected ||
    MaintenanceRequestStatus.cancelled => StatusTone.danger,
    _ => StatusTone.pending,
  };

  String _capitalise(String value) {
    final normalised = value.replaceAll('_', ' ');
    final parts = normalised.split(' ');
    return parts
        .map(
          (part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.muted,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        flex: 2,
        child: SelectableText(
          value,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}

class _ActionError extends StatelessWidget {
  const _ActionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: const Color(0xFFF5DDDC),
      borderRadius: BorderRadius.circular(AppRadii.medium),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: AppPalette.danger),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppPalette.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress({this.color = AppPalette.white});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}
