import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/maintenance_status_history.dart';
import '../models/maintenance_request.dart';
import '../models/repair_estimate.dart';
import '../services/maintenance_api_service.dart';

class AssignedWorkScreen extends StatefulWidget {
  const AssignedWorkScreen({
    super.key,
    this.maintenanceApiService,
    this.request,
    this.requestId,
    this.technicianId,
  });

  final MaintenanceApiService? maintenanceApiService;
  final MaintenanceRequest? request;
  final String? requestId;
  final String? technicianId;

  @override
  State<AssignedWorkScreen> createState() => _AssignedWorkScreenState();
}

class _AssignedWorkScreenState extends State<AssignedWorkScreen> {
  ApiClient? _ownedApiClient;
  late final MaintenanceApiService _apiService;
  MaintenanceRequest? _request;
  List<MaintenanceRequest> _assignedWork = const [];
  List<RepairEstimate> _estimates = const [];
  Future<List<MaintenanceStatusHistory>> _historyFuture =
      Future.value(const <MaintenanceStatusHistory>[]);
  bool _areEstimatesLoaded = false;
  late Future<MaintenanceRequest?> _requestFuture;

  bool _isStartingWork = false;
  bool _isCompletingWork = false;
  bool _isSubmittingEstimate = false;
  String? _errorMessage;
  String? _estimateErrorMessage;

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
    _requestFuture = _loadRequest();
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

  bool get _canStartWork =>
      _activeRequest?.status == MaintenanceRequestStatus.approved;

  bool get _canCompleteWork =>
      _activeRequest?.status == MaintenanceRequestStatus.inProgress;

  RepairEstimate? get _latestEstimate {
    if (_estimates.isEmpty) return null;
    return _estimates.reduce(
      (latest, item) =>
          item.versionNumber > latest.versionNumber ? item : latest,
    );
  }

  bool get _canCreateEstimate {
    final request = _activeRequest;
    final latest = _latestEstimate;
    return _areEstimatesLoaded &&
        request?.status == MaintenanceRequestStatus.estimatePending &&
        (latest == null ||
            latest.status == RepairEstimateStatus.revisionRequested);
  }

  bool get _revisionWasRequested =>
      _latestEstimate?.status == RepairEstimateStatus.revisionRequested;

  bool get _canSubmitEstimateForReview =>
      _areEstimatesLoaded &&
      _activeRequest?.status == MaintenanceRequestStatus.estimateSubmitted &&
      _latestEstimate?.status == RepairEstimateStatus.submitted;

  Future<MaintenanceRequest?> _loadRequest() async {
    if (_request != null) {
      final loaded = await _apiService.getMaintenanceRequestById(_request!.id);
      if (mounted) setState(() => _request = loaded);
      _loadHistory(loaded);
      await _loadEstimates(loaded);
      return loaded;
    }

    final id = widget.requestId?.trim();
    if (id == null || id.isEmpty) {
      final technicianId = widget.technicianId?.trim();
      if (technicianId == null || technicianId.isEmpty) return null;
      final assignedWork = await _apiService.getAssignedWork(
        technicianId: technicianId,
      );
      if (mounted) {
        setState(() {
          _assignedWork = assignedWork;
          _request = assignedWork.isEmpty ? null : assignedWork.first;
        });
      }
      final selected = assignedWork.isEmpty ? null : assignedWork.first;
      if (selected != null) await _loadEstimates(selected);
      if (selected != null) _loadHistory(selected);
      return selected;
    }

    final loaded = await _apiService.getMaintenanceRequestById(id);
    if (mounted) {
      setState(() => _request = loaded);
    }
    _loadHistory(loaded);
    await _loadEstimates(loaded);
    return loaded;
  }

  void _loadHistory(MaintenanceRequest request) {
    _historyFuture = _apiService.getMaintenanceRequestHistory(
      maintenanceRequestId: request.id,
    );
  }

  Future<void> _loadEstimates(MaintenanceRequest request) async {
    try {
      final estimates = await _apiService.getRepairEstimates(
        maintenanceRequestId: request.id,
      );
      if (!mounted || _request?.id != request.id) return;
      setState(() {
        _estimates = estimates;
        _areEstimatesLoaded = true;
        _estimateErrorMessage = null;
      });
    } on MaintenanceApiException catch (error) {
      if (!mounted || _request?.id != request.id) return;
      setState(() {
        _estimates = const [];
        _areEstimatesLoaded = false;
        _estimateErrorMessage = error.message;
      });
    } catch (_) {
      if (!mounted || _request?.id != request.id) return;
      setState(() {
        _estimates = const [];
        _areEstimatesLoaded = false;
        _estimateErrorMessage = 'Unable to load repair estimates.';
      });
    }
  }

  Future<void> _refreshQueue() async {
    final technicianId = widget.technicianId?.trim();
    if (technicianId == null || technicianId.isEmpty) {
      setState(
        () =>
            _errorMessage = 'Your technician account could not be identified.',
      );
      return;
    }
    try {
      final nextWork = await _apiService.getAssignedWork(
        technicianId: technicianId,
      );
      if (!mounted) return;
      final selectedId = _request?.id;
      MaintenanceRequest? selected;
      for (final item in nextWork) {
        if (item.id == selectedId) {
          selected = item;
          break;
        }
      }
      setState(() {
        _assignedWork = nextWork;
        _request = selected ?? (nextWork.isEmpty ? null : nextWork.first);
        _errorMessage = null;
        _estimates = const [];
        _areEstimatesLoaded = false;
        _historyFuture = Future.value(const <MaintenanceStatusHistory>[]);
      });
      final current = _request;
      if (current != null) {
        _loadHistory(current);
        await _loadEstimates(current);
      }
    } on MaintenanceApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Unable to refresh assigned work.');
      }
    }
  }

  void _selectRequest(MaintenanceRequest request) {
    setState(() {
      _request = request;
      _estimates = const [];
      _areEstimatesLoaded = false;
      _estimateErrorMessage = null;
      _errorMessage = null;
      _historyFuture = Future.value(const <MaintenanceStatusHistory>[]);
    });
    _loadHistory(request);
    _loadEstimates(request);
  }

  void _retryLoad() {
    setState(() => _requestFuture = _loadRequest());
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
      await _refreshQueue();
      if (!mounted) return;
      AppSnackbars.show(
        context,
        message: 'Work started for ${updated.title}.',
        tone: SnackTone.success,
      );
    } on MaintenanceApiException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
        AppSnackbars.show(
          context,
          message: error.message,
          tone: SnackTone.error,
        );
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
      await _refreshQueue();
      if (!mounted) return;
      AppSnackbars.show(
        context,
        message: 'Work completed for ${updated.title}.',
        tone: SnackTone.success,
      );
    } on MaintenanceApiException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
        AppSnackbars.show(
          context,
          message: error.message,
          tone: SnackTone.error,
        );
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

  Future<_EstimateDraft?> _showEstimateForm() => showDialog<_EstimateDraft>(
    context: context,
    builder: (_) => const _EstimateFormDialog(),
  );

  Future<void> _createEstimate(MaintenanceRequest request) async {
    if (_isSubmittingEstimate || !_canCreateEstimate) return;
    final technicianId = AuthScope.of(context).currentUser?.id;
    if (technicianId == null ||
        (widget.technicianId != null &&
            widget.technicianId!.trim() != technicianId)) {
      setState(() {
        _estimateErrorMessage =
            'Your technician account could not be identified.';
      });
      return;
    }

    setState(() {
      _isSubmittingEstimate = true;
      _estimateErrorMessage = null;
    });

    try {
      final persistedRequest = await _apiService.getMaintenanceRequestById(
        request.id,
      );
      final persistedEstimate = await _apiService.getLatestRepairEstimate(
        maintenanceRequestId: request.id,
      );
      if (!_requestCanReceiveEstimate(persistedRequest, persistedEstimate)) {
        if (mounted) {
          setState(() => _request = persistedRequest);
          await _loadEstimates(persistedRequest);
          setState(
            () => _estimateErrorMessage =
                'This request is no longer awaiting an estimate.',
          );
        }
        return;
      }

      if (mounted) setState(() => _isSubmittingEstimate = false);
      final draft = await _showEstimateForm();
      if (draft == null || !mounted) return;

      setState(() => _isSubmittingEstimate = true);
      final created = await _apiService.createRepairEstimate(
        maintenanceRequestId: persistedRequest.id,
        technicianId: technicianId,
        laborCost: draft.laborCost,
        partsCost: draft.partsCost,
        additionalCost: draft.additionalCost,
        notes: draft.notes,
      );
      if (!mounted) return;
      setState(() => _estimates = [..._estimates, created]);

      await _refreshQueue();
      if (!mounted) return;
      AppSnackbars.show(
        context,
        message: 'Estimate created. Submit it for landlord review when ready.',
        tone: SnackTone.success,
      );
    } on MaintenanceApiException catch (error) {
      if (mounted) {
        setState(() => _estimateErrorMessage = error.message);
        AppSnackbars.show(
          context,
          message: error.message,
          tone: SnackTone.error,
        );
      }
    } catch (_) {
      if (mounted) {
        const message = 'Unable to create the repair estimate right now.';
        setState(() => _estimateErrorMessage = message);
        AppSnackbars.show(context, message: message, tone: SnackTone.error);
      }
    } finally {
      if (mounted) setState(() => _isSubmittingEstimate = false);
    }
  }

  Future<void> _submitEstimateForReview(MaintenanceRequest request) async {
    if (_isSubmittingEstimate || !_canSubmitEstimateForReview) return;
    final technicianId = AuthScope.of(context).currentUser?.id;
    if (technicianId == null ||
        (widget.technicianId != null &&
            widget.technicianId!.trim() != technicianId)) {
      setState(() {
        _estimateErrorMessage =
            'Your technician account could not be identified.';
      });
      return;
    }

    setState(() {
      _isSubmittingEstimate = true;
      _estimateErrorMessage = null;
    });

    try {
      final persistedRequest = await _apiService.getMaintenanceRequestById(
        request.id,
      );
      final persistedEstimate = await _apiService.getLatestRepairEstimate(
        maintenanceRequestId: request.id,
      );
      if (persistedRequest.technicianId != technicianId ||
          persistedRequest.status !=
              MaintenanceRequestStatus.estimateSubmitted ||
          persistedEstimate?.status != RepairEstimateStatus.submitted) {
        if (mounted) {
          setState(() => _request = persistedRequest);
          await _loadEstimates(persistedRequest);
          setState(
            () => _estimateErrorMessage =
                'The request or estimate status changed. Refresh and try again.',
          );
        }
        return;
      }

      final updated = await _apiService.submitEstimateForReview(
        maintenanceRequestId: persistedRequest.id,
        estimateId: persistedEstimate!.id,
      );
      if (!mounted) return;
      setState(() {
        _request = updated;
        _estimateErrorMessage = null;
      });
      await _refreshQueue();
    } on MaintenanceApiException catch (error) {
      if (mounted) setState(() => _estimateErrorMessage = error.message);
      if (mounted) {
        AppSnackbars.show(
          context,
          message: error.message,
          tone: SnackTone.error,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _estimateErrorMessage =
              'Unable to submit the estimate for review right now.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingEstimate = false);
      }
    }
  }

  bool _requestCanReceiveEstimate(
    MaintenanceRequest request,
    RepairEstimate? latestEstimate,
  ) {
    final hasRevision =
        latestEstimate?.status == RepairEstimateStatus.revisionRequested;
    return request.technicianId == AuthScope.of(context).currentUser?.id &&
        request.status == MaintenanceRequestStatus.estimatePending &&
        (latestEstimate == null || hasRevision);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: const Text('Assigned Work'),
        actions: [
          if (widget.technicianId != null)
            IconButton(
              tooltip: 'Refresh assigned work',
              onPressed:
                  _isStartingWork || _isCompletingWork || _isSubmittingEstimate
                  ? null
                  : _refreshQueue,
              icon: const Icon(Icons.refresh),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: FutureBuilder<MaintenanceRequest?>(
        future: _requestFuture,
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
                onAction: _retryLoad,
              ),
            );
          }

          final request = _request ?? snapshot.data;
          final hasAssignedWork =
              _assignedWork.isNotEmpty ||
              (request != null && _hasActionableRequest);
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
                if (widget.technicianId != null &&
                    _assignedWork.length > 1) ...[
                  const SectionHeader(title: 'Your assigned requests'),
                  const SizedBox(height: AppSpacing.sm),
                  ..._assignedWork.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: OutlinedButton(
                        onPressed: () => _selectRequest(item),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${item.title} · ${_statusLabel(item.status)}',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
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
                const SectionHeader(title: 'Attachments'),
                const SizedBox(height: AppSpacing.md),
                const AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.attach_file, color: AppPalette.olive),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Attachments are currently available to tenants only.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Status history'),
                const SizedBox(height: AppSpacing.md),
                FutureBuilder<List<MaintenanceStatusHistory>>(
                  future: _historyFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const AppCard(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppPalette.olive,
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      final message = snapshot.error is MaintenanceApiException
                          ? (snapshot.error as MaintenanceApiException).message
                          : 'Unable to load status history.';
                      return _ActionError(message: message);
                    }
                    final history =
                        snapshot.data ??
                        const <MaintenanceStatusHistory>[];
                    if (history.isEmpty) {
                      return const AppCard(
                        child: Text('No status history yet.'),
                      );
                    }
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: history
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: Text(
                                  '${entry.fromStatus == null ? 'Created' : _statusLabel(entry.fromStatus!)}'
                                  ' → ${_statusLabel(entry.toStatus)}\n'
                                  '${MaterialLocalizations.of(context).formatMediumDate(entry.changedAt.toLocal())}'
                                  '${entry.notes == null ? '' : '\n${entry.notes}'}',
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Work details'),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    children: [
                      _InfoRow(
                        label: 'Property',
                        value: activeRequest.propertyId,
                      ),
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
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Repair estimates'),
                const SizedBox(height: AppSpacing.md),
                if (_estimateErrorMessage != null) ...[
                  _ActionError(message: _estimateErrorMessage!),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_revisionWasRequested) ...[
                  AppCard(
                    color: AppPalette.softCream,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.rate_review_outlined,
                              color: AppPalette.olive,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Revision requested by landlord',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        if (_latestEstimate?.reviewNotes
                                case final reviewNotes?
                            when reviewNotes.trim().isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text('Requested changes: $reviewNotes'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (!_areEstimatesLoaded)
                  AppCard(
                    child: Text(
                      _estimateErrorMessage == null
                          ? 'Loading repair estimates...'
                          : 'Estimate history is unavailable until refreshed.',
                    ),
                  )
                else if (_estimates.isEmpty)
                  const AppCard(
                    child: Text('No repair estimate has been submitted yet.'),
                  )
                else
                  ..._estimates.map(
                    (estimate) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _EstimateCard(estimate: estimate),
                    ),
                  ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ActionError(message: _errorMessage!),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (_canCreateEstimate) ...[
                  FilledButton.icon(
                    key: const ValueKey('create-maintenance-estimate'),
                    onPressed: _isSubmittingEstimate
                        ? null
                        : () => _createEstimate(activeRequest),
                    icon: _isSubmittingEstimate
                        ? const _ButtonProgress(color: AppPalette.olive)
                        : const Icon(Icons.request_quote_outlined),
                    label: Text(
                      _isSubmittingEstimate
                          ? 'Submitting estimate...'
                          : _revisionWasRequested
                          ? 'Create revised estimate'
                          : 'Create estimate',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_canSubmitEstimateForReview) ...[
                  OutlinedButton.icon(
                    key: const ValueKey(
                      'submit-maintenance-estimate-for-review',
                    ),
                    onPressed: _isSubmittingEstimate
                        ? null
                        : () => _submitEstimateForReview(activeRequest),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Submit estimate for review'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_canStartWork) ...[
                  FilledButton.icon(
                    key: const ValueKey('start-maintenance-work'),
                    onPressed: _isStartingWork || _isCompletingWork
                        ? null
                        : () => _startWork(activeRequest),
                    icon: _isStartingWork
                        ? const _ButtonProgress()
                        : const Icon(Icons.play_arrow_outlined),
                    label: Text(
                      _isStartingWork ? 'Starting work...' : 'Start work',
                    ),
                  ),
                ] else if (_canCompleteWork) ...[
                  FilledButton.icon(
                    key: const ValueKey('complete-maintenance-work'),
                    onPressed: _isStartingWork || _isCompletingWork
                        ? null
                        : () => _completeWork(activeRequest),
                    icon: _isCompletingWork
                        ? const _ButtonProgress()
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _isCompletingWork
                          ? 'Completing work...'
                          : 'Complete work',
                    ),
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
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
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
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppPalette.muted),
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

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.estimate});

  final RepairEstimate estimate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Estimate · v${estimate.versionNumber}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusChip(
                label: _estimateStatusLabel(estimate.status),
                tone: _estimateStatusTone(estimate.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            label: 'Labor',
            value: 'LKR ${estimate.laborCost.toStringAsFixed(2)}',
          ),
          const Divider(height: AppSpacing.md),
          _InfoRow(
            label: 'Parts',
            value: 'LKR ${estimate.partsCost.toStringAsFixed(2)}',
          ),
          const Divider(height: AppSpacing.md),
          _InfoRow(
            label: 'Additional',
            value: 'LKR ${estimate.additionalCost.toStringAsFixed(2)}',
          ),
          const Divider(height: AppSpacing.md),
          _InfoRow(
            label: 'Total',
            value: 'LKR ${estimate.totalCost.toStringAsFixed(2)}',
          ),
          if (estimate.notes?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Technician notes: ${estimate.notes}'),
          ],
          if (estimate.reviewNotes?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Review notes: ${estimate.reviewNotes}'),
          ],
        ],
      ),
    );
  }
}

class _EstimateFormDialog extends StatefulWidget {
  const _EstimateFormDialog();

  @override
  State<_EstimateFormDialog> createState() => _EstimateFormDialogState();
}

class _EstimateFormDialogState extends State<_EstimateFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _laborController = TextEditingController();
  final _partsController = TextEditingController();
  final _additionalController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _laborController.dispose();
    _partsController.dispose();
    _additionalController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _validateCost(String? value) {
    final cost = double.tryParse(value?.trim() ?? '');
    if (cost == null || !cost.isFinite) {
      return 'Enter a valid cost (use 0 when not applicable).';
    }
    if (cost < 0) return 'Cost cannot be negative.';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _EstimateDraft(
        laborCost: double.parse(_laborController.text.trim()),
        partsCost: double.parse(_partsController.text.trim()),
        additionalCost: double.parse(_additionalController.text.trim()),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Repair estimate breakdown'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _costField(_laborController, 'Labor cost'),
              const SizedBox(height: AppSpacing.sm),
              _costField(_partsController, 'Parts cost'),
              const SizedBox(height: AppSpacing.sm),
              _costField(_additionalController, 'Additional cost'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save-maintenance-estimate'),
          onPressed: _submit,
          child: const Text('Create and submit estimate'),
        ),
      ],
    );
  }

  TextFormField _costField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'LKR ',
          border: const OutlineInputBorder(),
        ),
        validator: _validateCost,
      );
}

class _EstimateDraft {
  const _EstimateDraft({
    required this.laborCost,
    required this.partsCost,
    required this.additionalCost,
    required this.notes,
  });

  final double laborCost;
  final double partsCost;
  final double additionalCost;
  final String? notes;
}

String _estimateStatusLabel(RepairEstimateStatus status) {
  final label = status.name
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ');
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

StatusTone _estimateStatusTone(RepairEstimateStatus status) => switch (status) {
  RepairEstimateStatus.approved => StatusTone.success,
  RepairEstimateStatus.revisionRequested => StatusTone.progress,
  RepairEstimateStatus.rejected ||
  RepairEstimateStatus.superseded => StatusTone.danger,
  _ => StatusTone.pending,
};

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
