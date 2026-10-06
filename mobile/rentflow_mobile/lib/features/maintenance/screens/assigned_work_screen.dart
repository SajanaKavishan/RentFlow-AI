import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/maintenance_status_history.dart';
import '../models/maintenance_request.dart';
import '../models/repair_estimate.dart';
import '../services/maintenance_api_service.dart';
import '../services/maintenance_photo_picker.dart';
import '../widgets/tenant_maintenance_ui.dart';

class AssignedWorkScreen extends StatefulWidget {
  const AssignedWorkScreen({
    super.key,
    this.maintenanceApiService,
    this.request,
    this.requestId,
    this.technicianId,
    this.photoPicker,
  });

  final MaintenanceApiService? maintenanceApiService;
  final MaintenanceRequest? request;
  final String? requestId;
  final String? technicianId;
  final MaintenancePhotoPicker? photoPicker;

  @override
  State<AssignedWorkScreen> createState() => _AssignedWorkScreenState();
}

class _AssignedWorkScreenState extends State<AssignedWorkScreen> {
  ApiClient? _ownedApiClient;
  late final MaintenanceApiService _apiService;
  late final MaintenancePhotoPicker _photoPicker;
  MaintenanceRequest? _request;
  List<MaintenanceRequest> _assignedWork = const [];
  List<RepairEstimate> _estimates = const [];
  Future<List<MaintenanceStatusHistory>> _historyFuture = Future.value(
    const <MaintenanceStatusHistory>[],
  );
  bool _areEstimatesLoaded = false;
  bool _isLoadingRequestDetails = false;
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
    _photoPicker = widget.photoPicker ?? PlatformMaintenancePhotoPicker();
    _requestFuture = _loadRequest();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  MaintenanceRequest? get _activeRequest =>
      _request ?? (_assignedWork.isNotEmpty ? _assignedWork.first : null);

  bool _isAssignedToCurrentTechnician(MaintenanceRequest? request) {
    final technicianId = widget.technicianId?.trim();
    final authenticatedId = AuthScope.of(context).currentUser?.id;
    return request != null &&
        technicianId != null &&
        technicianId.isNotEmpty &&
        technicianId == authenticatedId &&
        request.technicianId == authenticatedId;
  }

  bool get _hasActionableRequest =>
      _activeRequest != null ||
      (widget.requestId != null && widget.requestId!.trim().isNotEmpty);

  bool get _canStartWork =>
      !_isLoadingRequestDetails &&
      _areEstimatesLoaded &&
      _isAssignedToCurrentTechnician(_activeRequest) &&
      _activeRequest?.status == MaintenanceRequestStatus.approved &&
      _latestEstimate?.status == RepairEstimateStatus.approved;

  bool get _canCompleteWork =>
      !_isLoadingRequestDetails &&
      _isAssignedToCurrentTechnician(_activeRequest) &&
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
        !_isLoadingRequestDetails &&
        request?.status == MaintenanceRequestStatus.estimatePending &&
        (latest == null ||
            latest.status == RepairEstimateStatus.revisionRequested);
  }

  bool get _revisionWasRequested =>
      _latestEstimate?.status == RepairEstimateStatus.revisionRequested;

  bool get _canSubmitEstimateForReview =>
      _areEstimatesLoaded &&
      !_isLoadingRequestDetails &&
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
      if (technicianId == null || technicianId.isEmpty) {
        throw const MaintenanceApiException(
          'Your technician account could not be identified.',
        );
      }
      final assignedWork = (await _apiService.getAssignedWork(
        technicianId: technicianId,
      )).where(_isActiveJob).toList(growable: false);
      final selectedSummary = assignedWork.isEmpty ? null : assignedWork.first;
      if (mounted) {
        setState(() {
          _assignedWork = assignedWork;
          _request = selectedSummary;
        });
      }
      if (selectedSummary == null) return null;
      final selected = await _loadRequestDetails(selectedSummary);
      if (mounted) setState(() => _request = selected);
      _loadHistory(selected);
      await _loadEstimates(selected);
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

  Future<MaintenanceRequest> _loadRequestDetails(
    MaintenanceRequest summary,
  ) async {
    return _apiService.getMaintenanceRequestById(summary.id);
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
      final nextWork = (await _apiService.getAssignedWork(
        technicianId: technicianId,
      )).where(_isActiveJob).toList(growable: false);
      if (!mounted) return;
      final selectedId = _request?.id;
      MaintenanceRequest? selected;
      for (final item in nextWork) {
        if (item.id == selectedId) {
          selected = item;
          break;
        }
      }
      final selectedRequest =
          selected ?? (nextWork.isEmpty ? null : nextWork.first);
      setState(() {
        _assignedWork = nextWork;
        _request = selectedRequest;
        _isLoadingRequestDetails = selectedRequest != null;
        _errorMessage = null;
        _estimates = const [];
        _areEstimatesLoaded = false;
        _historyFuture = Future.value(const <MaintenanceStatusHistory>[]);
      });
      final current = selectedRequest;
      if (current != null) {
        try {
          final detail = await _loadRequestDetails(current);
          if (!mounted || _request?.id != current.id) return;
          setState(() {
            _request = detail;
            _isLoadingRequestDetails = false;
          });
          _loadHistory(detail);
          await _loadEstimates(detail);
        } on MaintenanceApiException catch (error) {
          if (mounted && _request?.id == current.id) {
            setState(() {
              _isLoadingRequestDetails = false;
              _errorMessage = error.message;
            });
          }
        } catch (_) {
          if (mounted && _request?.id == current.id) {
            setState(() {
              _isLoadingRequestDetails = false;
              _errorMessage = 'Unable to load this maintenance request.';
            });
          }
        }
      }
    } on MaintenanceApiException catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingRequestDetails = false;
          _errorMessage = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingRequestDetails = false;
          _errorMessage = 'Unable to refresh assigned work.';
        });
      }
    }
  }

  Future<void> _selectRequest(MaintenanceRequest request) async {
    setState(() {
      _request = request;
      _isLoadingRequestDetails = true;
      _estimates = const [];
      _areEstimatesLoaded = false;
      _estimateErrorMessage = null;
      _errorMessage = null;
      _historyFuture = Future.value(const <MaintenanceStatusHistory>[]);
    });
    _loadHistory(request);
    try {
      final detail = await _loadRequestDetails(request);
      if (!mounted || _request?.id != request.id) return;
      setState(() {
        _request = detail;
        _isLoadingRequestDetails = false;
      });
      await _loadEstimates(detail);
    } on MaintenanceApiException catch (error) {
      if (mounted && _request?.id == request.id) {
        setState(() {
          _isLoadingRequestDetails = false;
          _errorMessage = error.message;
        });
      }
    } catch (_) {
      if (mounted && _request?.id == request.id) {
        setState(() {
          _isLoadingRequestDetails = false;
          _errorMessage = 'Unable to load this maintenance request.';
        });
      }
    }
  }

  void _retryLoad() {
    setState(() => _requestFuture = _loadRequest());
  }

  Future<bool> _confirmWorkAction({
    required String title,
    required String message,
    required String confirmLabel,
    required Key confirmKey,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: confirmKey,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _workActionStillAllowed(
    MaintenanceRequest request, {
    required bool starting,
  }) async {
    final technicianId = AuthScope.of(context).currentUser?.id;
    if (technicianId == null ||
        technicianId != widget.technicianId?.trim() ||
        request.technicianId != technicianId) {
      return false;
    }

    final persistedRequest = await _apiService.getMaintenanceRequestById(
      request.id,
    );
    if (persistedRequest.technicianId != technicianId) return false;
    if (starting) {
      if (persistedRequest.status != MaintenanceRequestStatus.approved) {
        return false;
      }
      final latestEstimate = await _apiService.getLatestRepairEstimate(
        maintenanceRequestId: request.id,
      );
      return latestEstimate?.status == RepairEstimateStatus.approved;
    }
    return persistedRequest.status == MaintenanceRequestStatus.inProgress;
  }

  Future<void> _startWork(MaintenanceRequest request) async {
    if (_isStartingWork ||
        _isCompletingWork ||
        !_canStartWork ||
        !_isAssignedToCurrentTechnician(request)) {
      return;
    }
    final confirmed = await _confirmWorkAction(
      title: 'Start work?',
      message: 'This will mark the approved maintenance work as in progress.',
      confirmLabel: 'Start work',
      confirmKey: const ValueKey('confirm-start-maintenance-work'),
    );
    if (!confirmed || !mounted || _activeRequest?.id != request.id) return;

    setState(() {
      _isStartingWork = true;
      _errorMessage = null;
    });

    try {
      if (!await _workActionStillAllowed(request, starting: true)) {
        await _refreshQueue();
        if (mounted) {
          const message =
              'This request is no longer approved for work or assigned to your technician account.';
          setState(() => _errorMessage = message);
          AppSnackbars.show(context, message: message, tone: SnackTone.error);
        }
        return;
      }
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
    if (_isStartingWork ||
        _isCompletingWork ||
        !_canCompleteWork ||
        !_isAssignedToCurrentTechnician(request)) {
      return;
    }
    setState(() {
      _isCompletingWork = true;
      _errorMessage = null;
    });
    try {
      final completed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppPalette.warmCream,
        builder: (_) => _CompletionSheet(
          request: request,
          apiService: _apiService,
          photoPicker: _photoPicker,
        ),
      );
      if (completed == true && mounted) {
        await _refreshQueue();
        if (!mounted) return;
        AppSnackbars.show(
          context,
          message: 'Work completed for ${request.title}.',
          tone: SnackTone.success,
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
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: RefreshIndicator(
        color: AppPalette.olive,
        onRefresh: _refreshQueue,
        child: FutureBuilder<MaintenanceRequest?>(
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
                physics: const AlwaysScrollableScrollPhysics(),
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
                physics: const AlwaysScrollableScrollPhysics(),
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
              physics: const AlwaysScrollableScrollPhysics(),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.title} · ${_statusLabel(item.status)}',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${maintenanceLabel(item.category)} · ${item.referenceCode ?? 'Reference unavailable'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.secondaryText,
                                  ),
                                ),
                              ],
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
                        Text(
                          activeRequest.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.primaryText,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${maintenanceLabel(activeRequest.category)} · ${activeRequest.referenceCode ?? 'Reference unavailable'}',
                          key: const ValueKey('technician-request-reference'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppPalette.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            MaintenanceBadge.status(activeRequest.status),
                            MaintenanceBadge.priority(activeRequest.priority),
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
                  if (_isLoadingRequestDetails) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const AppCard(
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppPalette.olive,
                            ),
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Text('Loading request details…'),
                        ],
                      ),
                    ),
                  ],
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
                        final message =
                            snapshot.error is MaintenanceApiException
                            ? (snapshot.error as MaintenanceApiException)
                                  .message
                            : 'Unable to load status history.';
                        return _ActionError(message: message);
                      }
                      final history =
                          snapshot.data ?? const <MaintenanceStatusHistory>[];
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
                            ? 'Submit revised estimate'
                            : 'Submit Estimate',
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
                            : 'Mark Complete',
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
      ),
    );
  }

  String _statusLabel(MaintenanceRequestStatus status) => status.name
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ');

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

bool _isActiveJob(MaintenanceRequest request) =>
    request.status != MaintenanceRequestStatus.completed &&
    request.status != MaintenanceRequestStatus.rejected &&
    request.status != MaintenanceRequestStatus.cancelled;

class _CompletionSheet extends StatefulWidget {
  const _CompletionSheet({
    required this.request,
    required this.apiService,
    required this.photoPicker,
  });

  final MaintenanceRequest request;
  final MaintenanceApiService apiService;
  final MaintenancePhotoPicker photoPicker;

  @override
  State<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends State<_CompletionSheet> {
  static const _maximumPhotos = 3;
  final List<_CompletionPhoto> _photos = [];
  bool _submitting = false;
  bool _showSettings = false;
  int _uploadNumber = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recoverLostPhotos();
  }

  Future<void> _recoverLostPhotos() async {
    try {
      final recovered = await widget.photoPicker.recoverLostPhotos();
      if (!mounted || recovered.isEmpty) return;
      setState(() {
        _photos.addAll(
          recovered.take(_maximumPhotos).map(_CompletionPhoto.new),
        );
      });
    } on MaintenancePhotoPickerException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _pick(MaintenancePhotoSource source) async {
    if (_submitting) return;
    if (_photos.length >= _maximumPhotos) {
      setState(() => _error = 'You can add up to 3 completion photos.');
      return;
    }
    try {
      final selected = await widget.photoPicker.pick(source);
      if (!mounted || selected.isEmpty) return;
      final remaining = _maximumPhotos - _photos.length;
      setState(() {
        _photos.addAll(selected.take(remaining).map(_CompletionPhoto.new));
        _error = selected.length > remaining
            ? 'Only the first $remaining photo${remaining == 1 ? '' : 's'} were added. The maximum is 3.'
            : null;
        _showSettings = false;
      });
    } on MaintenancePhotoPickerException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _showSettings = widget.photoPicker.canOpenSettings;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to select a photo. Please try again.');
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_photos.isEmpty) {
      setState(() => _error = 'Add at least one completion photo.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _showSettings = false;
    });
    try {
      for (var index = 0; index < _photos.length; index++) {
        final item = _photos[index];
        if (item.uploaded) continue;
        setState(() => _uploadNumber = index + 1);
        await widget.apiService.uploadCompletionPhoto(
          maintenanceRequestId: widget.request.id,
          fileName: item.photo.fileName,
          contentType: item.photo.contentType,
          bytes: item.photo.bytes,
        );
        if (!mounted) return;
        setState(() => item.uploaded = true);
      }
      setState(() => _uploadNumber = 0);
      await widget.apiService.completeWork(id: widget.request.id);
      if (mounted) Navigator.of(context).pop(true);
    } on MaintenanceApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to finish this job right now. Your uploaded photos have been kept; retry when ready.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadNumber = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.outline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                'Complete this job',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Add 1–3 photos showing the completed work. The job is marked completed only after the evidence is uploaded.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.base),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('take-completion-photo'),
                      onPressed: _submitting || _photos.length >= _maximumPhotos
                          ? null
                          : () => _pick(MaintenancePhotoSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take photo'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('choose-completion-photos'),
                      onPressed: _submitting || _photos.length >= _maximumPhotos
                          ? null
                          : () => _pick(MaintenancePhotoSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose from gallery'),
                    ),
                  ),
                ],
              ),
              if (_photos.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.base),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (var index = 0; index < _photos.length; index++)
                      _CompletionThumbnail(
                        item: _photos[index],
                        index: index,
                        canRemove: !_submitting && !_photos[index].uploaded,
                        onRemove: () => setState(() => _photos.removeAt(index)),
                      ),
                  ],
                ),
              ],
              if (_submitting) ...[
                const SizedBox(height: AppSpacing.base),
                const LinearProgressIndicator(color: AppPalette.olive),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _uploadNumber > 0
                      ? 'Uploading photo $_uploadNumber of ${_photos.length}…'
                      : 'Confirming completion…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.base),
                _ActionError(message: _error!),
                if (_showSettings)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: widget.photoPicker.openSettings,
                      child: const Text('Open settings'),
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                key: const ValueKey('submit-maintenance-completion'),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const _ButtonProgress()
                    : const Icon(Icons.check_circle_outline),
                label: Text(_error == null ? 'Complete job' : 'Retry'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionPhoto {
  _CompletionPhoto(this.photo);
  final MaintenancePhoto photo;
  bool uploaded = false;
}

class _CompletionThumbnail extends StatelessWidget {
  const _CompletionThumbnail({
    required this.item,
    required this.index,
    required this.canRemove,
    required this.onRemove,
  });

  final _CompletionPhoto item;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Completion photo ${index + 1}${item.uploaded ? ', uploaded' : ''}',
    child: Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          child: Image.memory(
            item.photo.bytes,
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 92,
              height: 92,
              color: AppPalette.softCream,
              child: const Icon(Icons.image_outlined),
            ),
          ),
        ),
        if (item.uploaded)
          const Positioned(
            left: 6,
            bottom: 6,
            child: Icon(Icons.check_circle, color: AppPalette.success),
          ),
        if (canRemove)
          Positioned(
            right: 2,
            top: 2,
            child: IconButton.filled(
              key: ValueKey('remove-completion-photo-$index'),
              tooltip: 'Remove photo ${index + 1}',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 17),
            ),
          ),
      ],
    ),
  );
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
    final input = value?.trim() ?? '';
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(input)) {
      return 'Enter a valid currency amount with up to two decimal places.';
    }
    final cost = double.tryParse(input);
    if (cost == null || !cost.isFinite || cost > 7.922816251426433e28) {
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
                maxLength: 4000,
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
          child: const Text('Submit estimate'),
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
