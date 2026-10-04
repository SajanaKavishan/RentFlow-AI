import 'package:flutter/material.dart';

import '../../../features/properties/models/property.dart';
import '../../../features/properties/services/property_api_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/maintenance_technician_choice.dart';
import '../models/maintenance_request.dart';
import '../models/maintenance_status_history.dart';
import '../models/repair_estimate.dart';
import '../services/maintenance_api_service.dart';

String _landlordMaintenanceLabel(Enum value) => value.name
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    )
    .replaceAll('_', ' ')
    .split(' ')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

class LandlordMaintenanceScreen extends StatefulWidget {
  const LandlordMaintenanceScreen({
    super.key,
    required this.landlordId,
    this.propertyApiService,
    this.maintenanceApiService,
  });

  final String landlordId;
  final PropertyApiService? propertyApiService;
  final MaintenanceApiService? maintenanceApiService;

  @override
  State<LandlordMaintenanceScreen> createState() =>
      _LandlordMaintenanceScreenState();
}

class _LandlordMaintenanceScreenState extends State<LandlordMaintenanceScreen> {
  List<Property> _properties = const [];
  String? _selectedPropertyId;
  Future<List<MaintenanceRequest>>? _requests;
  bool _isLoadingProperties = true;
  String? _propertiesError;

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  Future<void> _loadProperties() async {
    setState(() {
      _isLoadingProperties = true;
      _propertiesError = null;
    });

    try {
      final service = widget.propertyApiService;
      if (service == null) {
        throw const PropertyApiException(
          'Property information is currently unavailable.',
        );
      }
      final properties = (await service.getProperties())
          .where((property) => property.landlordId == widget.landlordId)
          .toList(growable: false);
      if (!mounted) return;

      final selectedPropertyId =
          properties.any((property) => property.id == _selectedPropertyId)
          ? _selectedPropertyId
          : properties.firstOrNull?.id;
      setState(() {
        _properties = properties;
        _selectedPropertyId = selectedPropertyId;
        _requests = selectedPropertyId == null
            ? null
            : _loadRequests(selectedPropertyId);
        _isLoadingProperties = false;
      });
    } on PropertyApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _propertiesError = error.message;
        _isLoadingProperties = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _propertiesError = 'Unable to load your properties. Please try again.';
        _isLoadingProperties = false;
      });
    }
  }

  Future<List<MaintenanceRequest>> _loadRequests(String propertyId) {
    final service = widget.maintenanceApiService;
    if (service == null) {
      return Future<List<MaintenanceRequest>>.error(
        const MaintenanceApiException(
          'Maintenance requests are currently unavailable.',
        ),
      );
    }
    return service.getMaintenanceRequestsByProperty(propertyId: propertyId);
  }

  Future<void> _selectProperty(String propertyId) async {
    setState(() {
      _selectedPropertyId = propertyId;
      _requests = _loadRequests(propertyId);
    });
    await _awaitRequests();
  }

  Future<void> _refreshRequests() async {
    final propertyId = _selectedPropertyId;
    if (propertyId == null) return;
    setState(() => _requests = _loadRequests(propertyId));
    await _awaitRequests();
  }

  Future<void> _awaitRequests() async {
    try {
      await _requests;
    } catch (_) {
      // The request FutureBuilder renders the service error with a retry action.
    }
  }

  Future<void> _openRequest(MaintenanceRequest request) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LandlordMaintenanceRequestDetailScreen(
          request: request,
          maintenanceApiService: widget.maintenanceApiService,
          onTriaged: _refreshRequests,
        ),
      ),
    );
    if (updated == true && mounted) await _refreshRequests();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Landlord Maintenance'),
      actions: [
        IconButton(
          tooltip: 'Refresh landlord maintenance',
          onPressed: _isLoadingProperties ? null : _loadProperties,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _isLoadingProperties
          ? const Center(child: CircularProgressIndicator())
          : _propertiesError != null
          ? _LandlordMaintenanceMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load properties',
              message: _propertiesError!,
              actionLabel: 'Try again',
              onAction: _loadProperties,
            )
          : _properties.isEmpty
          ? const _LandlordMaintenanceMessage(
              icon: Icons.home_work_outlined,
              title: 'No properties found',
              message:
                  'Properties associated with your account will appear here.',
            )
          : _buildPropertyRequests(),
    ),
  );

  Widget _buildPropertyRequests() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: DropdownButtonFormField<String>(
          key: const ValueKey('landlord-maintenance-property'),
          initialValue: _selectedPropertyId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Property',
            prefixIcon: Icon(Icons.home_work_outlined),
          ),
          items: _properties
              .map(
                (property) => DropdownMenuItem(
                  value: property.id,
                  child: Text(property.title, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          onChanged: (propertyId) {
            if (propertyId != null) _selectProperty(propertyId);
          },
        ),
      ),
      Expanded(
        child: FutureBuilder<List<MaintenanceRequest>>(
          future: _requests,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _LandlordMaintenanceMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load maintenance requests',
                message: _maintenanceErrorMessage(snapshot.error),
                actionLabel: 'Try again',
                onAction: _refreshRequests,
              );
            }
            final requests = snapshot.data ?? const <MaintenanceRequest>[];
            if (requests.isEmpty) {
              return _LandlordMaintenanceMessage(
                icon: Icons.handyman_outlined,
                title: 'No maintenance requests',
                message:
                    'Requests for ${_selectedProperty?.title ?? 'this property'} will appear here.',
                actionLabel: 'Refresh',
                onAction: _refreshRequests,
              );
            }
            return RefreshIndicator(
              onRefresh: _refreshRequests,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: requests.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) => _MaintenanceRequestCard(
                  request: requests[index],
                  onTap: () => _openRequest(requests[index]),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  Property? get _selectedProperty {
    for (final property in _properties) {
      if (property.id == _selectedPropertyId) return property;
    }
    return null;
  }
}

class LandlordMaintenanceRequestDetailScreen extends StatefulWidget {
  const LandlordMaintenanceRequestDetailScreen({
    super.key,
    required this.request,
    required this.maintenanceApiService,
    this.onTriaged,
  });

  final MaintenanceRequest request;
  final MaintenanceApiService? maintenanceApiService;
  final Future<void> Function()? onTriaged;

  @override
  State<LandlordMaintenanceRequestDetailScreen> createState() =>
      _LandlordMaintenanceRequestDetailScreenState();
}

class _LandlordMaintenanceRequestDetailScreenState
    extends State<LandlordMaintenanceRequestDetailScreen> {
  late Future<MaintenanceRequest> _detail;
  late Future<List<MaintenanceStatusHistory>> _history;
  late Future<RepairEstimate?> _latestEstimate;
  late MaintenanceCategory _category;
  late MaintenancePriority _priority;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _assignmentNotesController =
      TextEditingController();
  Future<List<MaintenanceTechnicianChoice>>? _technicians;
  String? _selectedTechnicianId;
  String? _technicianError;
  bool _isSubmittingTriage = false;
  bool _isAssigningTechnician = false;
  bool _isRequestingEstimate = false;
  bool _isReviewingEstimate = false;
  String? _triageError;
  String? _assignmentError;
  String? _estimateError;
  String? _estimateReviewError;

  MaintenanceApiService get _apiService => widget.maintenanceApiService!;

  @override
  void initState() {
    super.initState();
    _category = widget.request.category;
    _priority = widget.request.priority;
    _startLoadingDetails();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _assignmentNotesController.dispose();
    super.dispose();
  }

  void _startLoadingDetails() {
    final service = widget.maintenanceApiService;
    _technicianError = null;
    if (service == null) {
      _detail = Future<MaintenanceRequest>.error(
        const MaintenanceApiException(
          'Maintenance requests are currently unavailable.',
        ),
      );
      _history = Future<List<MaintenanceStatusHistory>>.error(
        const MaintenanceApiException(
          'Maintenance history is currently unavailable.',
        ),
      );
      _latestEstimate = Future<RepairEstimate?>.error(
        const MaintenanceApiException(
          'Repair estimates are currently unavailable.',
        ),
      );
      _technicians = Future.value(const []);
      return;
    }
    _detail = service.getMaintenanceRequestById(widget.request.id);
    _technicians = _loadTechniciansForRequest(_detail);
    _history = service.getMaintenanceRequestHistory(
      maintenanceRequestId: widget.request.id,
    );
    _latestEstimate = _loadLatestEstimate(_detail);
  }

  Future<RepairEstimate?> _loadLatestEstimate(
    Future<MaintenanceRequest> requestFuture,
  ) async {
    final request = await requestFuture;
    const estimateStatuses = {
      MaintenanceRequestStatus.estimatePending,
      MaintenanceRequestStatus.estimateSubmitted,
      MaintenanceRequestStatus.awaitingLandlordApproval,
      MaintenanceRequestStatus.approved,
      MaintenanceRequestStatus.rejected,
      MaintenanceRequestStatus.inProgress,
      MaintenanceRequestStatus.completed,
    };
    if (!estimateStatuses.contains(request.status)) return null;
    return _apiService.getLatestRepairEstimate(
      maintenanceRequestId: request.id,
    );
  }

  Future<List<MaintenanceTechnicianChoice>> _loadTechniciansForRequest(
    Future<MaintenanceRequest> requestFuture,
  ) async {
    try {
      final request = await requestFuture;
      if (request.status != MaintenanceRequestStatus.triaged ||
          request.technicianId != null) {
        return const [];
      }
      return await _apiService.getMaintenanceTechnicians();
    } on MaintenanceApiException catch (error) {
      _technicianError = error.message;
      return const [];
    } catch (_) {
      _technicianError = 'Unable to load available technicians.';
      return const [];
    }
  }

  Future<void> _refreshDetails() async {
    _startLoadingDetails();
    setState(() {});
    try {
      await Future.wait<Object?>([_detail, _history, _latestEstimate]);
    } catch (_) {
      // The detail and history FutureBuilders provide retryable error states.
    }
  }

  Future<void> _retryTechnicians() async {
    setState(() {
      _technicianError = null;
      _technicians = _apiService.getMaintenanceTechnicians();
    });
    try {
      await _technicians;
    } on MaintenanceApiException catch (error) {
      if (mounted) setState(() => _technicianError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _technicianError = 'Unable to load available technicians.',
        );
      }
    }
  }

  Future<void> _submitTechnicianAssignment() async {
    final technicianId = _selectedTechnicianId;
    if (_isAssigningTechnician || technicianId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign technician?'),
        content: const Text(
          'This will assign the selected technician to this request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isAssigningTechnician = true;
      _assignmentError = null;
    });
    try {
      await _apiService.assignMaintenanceTechnician(
        id: widget.request.id,
        technicianId: technicianId,
        assignmentNotes: _assignmentNotesController.text,
      );
      if (!mounted) return;
      await _refreshDetails();
      if (widget.onTriaged case final refreshList?) await refreshList();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Technician assigned successfully.')),
          );
      }
    } on MaintenanceApiException catch (error) {
      if (mounted) setState(() => _assignmentError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _assignmentError = 'Unable to assign a technician.');
      }
    } finally {
      if (mounted) setState(() => _isAssigningTechnician = false);
    }
  }

  Future<void> _submitEstimateRequest() async {
    if (_isRequestingEstimate) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request estimate?'),
        content: const Text(
          'The assigned technician will be asked to submit a repair estimate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Request estimate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isRequestingEstimate = true;
      _estimateError = null;
    });
    try {
      await _apiService.requestMaintenanceEstimate(id: widget.request.id);
      if (!mounted) return;
      await _refreshDetails();
      if (widget.onTriaged case final refreshList?) await refreshList();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Estimate requested successfully.')),
          );
      }
    } on MaintenanceApiException catch (error) {
      if (mounted) setState(() => _estimateError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _estimateError = 'Unable to request an estimate.');
      }
    } finally {
      if (mounted) setState(() => _isRequestingEstimate = false);
    }
  }

  Future<void> _reviewEstimate(
    RepairEstimate estimate,
    String action,
  ) async {
    if (_isReviewingEstimate) return;
    final reviewNotes = await _showEstimateReviewDialog(action);
    if (reviewNotes == null || !mounted) return;

    setState(() {
      _isReviewingEstimate = true;
      _estimateReviewError = null;
    });
    try {
      final currentRequest = await _apiService.getMaintenanceRequestById(
        widget.request.id,
      );
      final currentEstimate = await _apiService.getLatestRepairEstimate(
        maintenanceRequestId: widget.request.id,
      );
      if (currentRequest.status !=
              MaintenanceRequestStatus.awaitingLandlordApproval ||
          currentEstimate?.id != estimate.id ||
          currentEstimate?.status != RepairEstimateStatus.submitted) {
        if (mounted) {
          setState(
            () => _estimateReviewError =
                'This estimate is no longer awaiting landlord review. Refresh and try again.',
          );
          await _refreshDetails();
        }
        return;
      }

      final reviewRequest = switch (action) {
        'approve' => _apiService.approveRepairEstimate(
            maintenanceRequestId: currentRequest.id,
            estimateId: currentEstimate!.id,
            reviewNotes: reviewNotes,
          ),
        'reject' => _apiService.rejectRepairEstimate(
            maintenanceRequestId: currentRequest.id,
            estimateId: currentEstimate!.id,
            reviewNotes: reviewNotes,
          ),
        'request-revision' => _apiService.requestRepairEstimateRevision(
            maintenanceRequestId: currentRequest.id,
            estimateId: currentEstimate!.id,
            reviewNotes: reviewNotes,
          ),
        _ => throw StateError('Unsupported estimate review action: $action'),
      };
      await reviewRequest;
      if (!mounted) return;
      await _refreshDetails();
      if (widget.onTriaged case final refreshList?) await refreshList();
      if (mounted) {
        final message = switch (action) {
          'approve' => 'Repair estimate approved.',
          'reject' => 'Repair estimate rejected.',
          'request-revision' => 'Revision requested from the technician.',
          _ => 'Repair estimate reviewed.',
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } on MaintenanceApiException catch (error) {
      if (mounted) setState(() => _estimateReviewError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _estimateReviewError = 'Unable to review this estimate.',
        );
      }
    } finally {
      if (mounted) setState(() => _isReviewingEstimate = false);
    }
  }

  Future<String?> _showEstimateReviewDialog(String action) {
    final isApprove = action == 'approve';
    final title = switch (action) {
      'approve' => 'Approve estimate?',
      'reject' => 'Reject estimate?',
      'request-revision' => 'Request estimate revision?',
      _ => 'Review estimate?',
    };
    final message = switch (action) {
      'approve' => 'The estimate will be approved and work may proceed.',
      'reject' => 'The estimate will be rejected. Provide a reason.',
      'request-revision' =>
        'The technician will be asked to revise the estimate. Describe the changes needed.',
      _ => 'Confirm this estimate decision.',
    };
    return showDialog<String>(
      context: context,
      builder: (context) => _EstimateReviewDialog(
        title: title,
        message: message,
        confirmLabel: switch (action) {
          'approve' => 'Approve Estimate',
          'reject' => 'Reject Estimate',
          'request-revision' => 'Request Revision',
          _ => 'Confirm',
        },
        requiresNotes: !isApprove,
      ),
    );
  }

  Future<void> _refreshHistory() async {
    setState(() {
      _history = _apiService.getMaintenanceRequestHistory(
        maintenanceRequestId: widget.request.id,
      );
    });
    try {
      await _history;
    } catch (_) {
      // The history FutureBuilder renders the error and retry action.
    }
  }

  Future<void> _submitTriage() async {
    if (_isSubmittingTriage) return;
    setState(() {
      _isSubmittingTriage = true;
      _triageError = null;
    });
    try {
      await _apiService.triageMaintenanceRequest(
        id: widget.request.id,
        category: _category,
        priority: _priority,
        triageNotes: _notesController.text,
      );
      if (!mounted) return;
      final refreshes = <Future<void>>[_refreshDetails()];
      if (widget.onTriaged case final refreshList?) {
        refreshes.add(refreshList());
      }
      await Future.wait(refreshes);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Request triaged successfully.')),
          );
      }
    } on MaintenanceApiException catch (error) {
      if (mounted) setState(() => _triageError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _triageError = 'Unable to triage this request.');
      }
    } finally {
      if (mounted) setState(() => _isSubmittingTriage = false);
    }
  }

  String _maintenanceErrorMessage(Object? error) =>
      error is MaintenanceApiException
      ? error.message
      : 'Unable to load this maintenance request. Please try again.';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Maintenance request'),
      actions: [
        IconButton(
          tooltip: 'Refresh request details',
          onPressed: _refreshDetails,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<MaintenanceRequest>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _LandlordMaintenanceMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load request details',
            message: _maintenanceErrorMessage(snapshot.error),
            actionLabel: 'Try again',
            onAction: _refreshDetails,
          );
        }
        final request = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _RequestInformationCard(request: request),
            const SizedBox(height: AppSpacing.md),
            _StatusHistoryCard(
              future: _history,
              onRetry: _refreshHistory,
              errorMessage: _maintenanceErrorMessage,
            ),
            if (request.status == MaintenanceRequestStatus.submitted) ...[
              const SizedBox(height: AppSpacing.md),
              _buildTriageSection(),
            ],
            if (request.status == MaintenanceRequestStatus.triaged &&
                request.technicianId == null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildAssignmentSection(),
            ],
            if (request.status == MaintenanceRequestStatus.assigned &&
                request.technicianId != null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildEstimateRequestSection(),
            ],
            if (const {
              MaintenanceRequestStatus.estimatePending,
              MaintenanceRequestStatus.estimateSubmitted,
              MaintenanceRequestStatus.awaitingLandlordApproval,
              MaintenanceRequestStatus.approved,
              MaintenanceRequestStatus.rejected,
              MaintenanceRequestStatus.inProgress,
              MaintenanceRequestStatus.completed,
            }.contains(request.status)) ...[
              const SizedBox(height: AppSpacing.md),
              _buildEstimateReviewSection(request),
            ],
          ],
        );
      },
    ),
  );

  Widget _buildAssignmentSection() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Assign Technician',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        FutureBuilder<List<MaintenanceTechnicianChoice>>(
          future: _technicians,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Text('Loading available technicians…'),
                ],
              );
            }
            if (_technicianError != null || snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _technicianError ??
                        _maintenanceErrorMessage(snapshot.error),
                  ),
                  TextButton(
                    onPressed: _retryTechnicians,
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            final technicians =
                snapshot.data ?? const <MaintenanceTechnicianChoice>[];
            if (technicians.isEmpty) {
              return const Text(
                'No active maintenance technicians are available.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('landlord-technician-choice'),
                  initialValue: _selectedTechnicianId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Technician'),
                  items: technicians
                      .map(
                        (technician) => DropdownMenuItem(
                          value: technician.id,
                          child: Text(
                            technician.name.trim().isEmpty
                                ? technician.id
                                : technician.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _isAssigningTechnician
                      ? null
                      : (id) => setState(() => _selectedTechnicianId = id),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const ValueKey('landlord-assignment-notes'),
                  controller: _assignmentNotesController,
                  enabled: !_isAssigningTechnician,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Assignment notes',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_assignmentError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _assignmentError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  key: const ValueKey('assign-maintenance-technician'),
                  onPressed:
                      _isAssigningTechnician || _selectedTechnicianId == null
                      ? null
                      : _submitTechnicianAssignment,
                  icon: _isAssigningTechnician
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assignment_ind_outlined),
                  label: Text(
                    _isAssigningTechnician ? 'Assigning…' : 'Assign Technician',
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _buildEstimateRequestSection() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Estimate workflow',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Request a repair estimate from the assigned technician to continue.',
        ),
        if (_estimateError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _estimateError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const ValueKey('request-maintenance-estimate'),
          onPressed: _isRequestingEstimate ? null : _submitEstimateRequest,
          icon: _isRequestingEstimate
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.request_quote_outlined),
          label: Text(
            _isRequestingEstimate ? 'Requesting…' : 'Request Estimate',
          ),
        ),
      ],
    ),
  );

  Widget _buildEstimateReviewSection(MaintenanceRequest request) =>
      FutureBuilder<RepairEstimate?>(
        future: _latestEstimate,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppCard(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_maintenanceErrorMessage(snapshot.error)),
                  TextButton(
                    onPressed: _refreshDetails,
                    child: const Text('Retry estimate'),
                  ),
                ],
              ),
            );
          }
          final estimate = snapshot.data;
          if (estimate == null) {
            return const AppCard(
              child: Text('No repair estimate is available for review.'),
            );
          }
          final canReview =
              request.status ==
                  MaintenanceRequestStatus.awaitingLandlordApproval &&
              estimate.status == RepairEstimateStatus.submitted;
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Repair Estimate',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                _DetailRow(
                  label: 'Estimate status',
                  value: _landlordMaintenanceLabel(estimate.status),
                ),
                _DetailRow(
                  label: 'Technician ID',
                  value: estimate.technicianId,
                ),
                _DetailRow(
                  label: 'Labor cost',
                  value: 'LKR ${estimate.laborCost.toStringAsFixed(2)}',
                ),
                _DetailRow(
                  label: 'Parts cost',
                  value: 'LKR ${estimate.partsCost.toStringAsFixed(2)}',
                ),
                _DetailRow(
                  label: 'Additional cost',
                  value: 'LKR ${estimate.additionalCost.toStringAsFixed(2)}',
                ),
                _DetailRow(
                  label: 'Total',
                  value: 'LKR ${estimate.totalCost.toStringAsFixed(2)}',
                ),
                if (estimate.notes?.trim().isNotEmpty ?? false)
                  _DetailRow(label: 'Technician notes', value: estimate.notes!),
                if (estimate.reviewNotes?.trim().isNotEmpty ?? false)
                  _DetailRow(
                    label: 'Review notes',
                    value: estimate.reviewNotes!,
                  ),
                if (_estimateReviewError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _estimateReviewError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (canReview) ...[
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const ValueKey('approve-repair-estimate'),
                    onPressed: _isReviewingEstimate
                        ? null
                        : () => _reviewEstimate(estimate, 'approve'),
                    icon: _isReviewingEstimate
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('Approve Estimate'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('reject-repair-estimate'),
                    onPressed: _isReviewingEstimate
                        ? null
                        : () => _reviewEstimate(estimate, 'reject'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject Estimate'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('request-estimate-revision'),
                    onPressed: _isReviewingEstimate
                        ? null
                        : () => _reviewEstimate(estimate, 'request-revision'),
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Request Revision'),
                  ),
                ],
              ],
            ),
          );
        },
      );

  Widget _buildTriageSection() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Triage Request', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<MaintenanceCategory>(
          key: const ValueKey('landlord-triage-category'),
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Category'),
          items: MaintenanceCategory.values
              .map(
                (category) => DropdownMenuItem(
                  value: category,
                  child: Text(_landlordMaintenanceLabel(category)),
                ),
              )
              .toList(growable: false),
          onChanged: _isSubmittingTriage
              ? null
              : (category) {
                  if (category != null) setState(() => _category = category);
                },
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<MaintenancePriority>(
          key: const ValueKey('landlord-triage-priority'),
          initialValue: _priority,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: MaintenancePriority.values
              .map(
                (priority) => DropdownMenuItem(
                  value: priority,
                  child: Text(_landlordMaintenanceLabel(priority)),
                ),
              )
              .toList(growable: false),
          onChanged: _isSubmittingTriage
              ? null
              : (priority) {
                  if (priority != null) setState(() => _priority = priority);
                },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('landlord-triage-notes'),
          controller: _notesController,
          enabled: !_isSubmittingTriage,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Triage notes',
            alignLabelWithHint: true,
          ),
        ),
        if (_triageError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _triageError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const ValueKey('submit-landlord-triage'),
          onPressed: _isSubmittingTriage ? null : _submitTriage,
          icon: _isSubmittingTriage
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fact_check_outlined),
          label: const Text('Submit Triage'),
        ),
      ],
    ),
  );
}

class _RequestInformationCard extends StatelessWidget {
  const _RequestInformationCard({required this.request});

  final MaintenanceRequest request;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(request.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(request.description, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.md),
        _DetailRow(
          label: 'Category',
          value: _landlordMaintenanceLabel(request.category),
        ),
        _DetailRow(
          label: 'Priority',
          value: _landlordMaintenanceLabel(request.priority),
        ),
        _DetailRow(
          label: 'Status',
          value: _landlordMaintenanceLabel(request.status),
        ),
        _DetailRow(label: 'Tenant ID', value: request.tenantId),
        if (request.technicianId case final technicianId?)
          _DetailRow(label: 'Technician ID', value: technicianId),
      ],
    ),
  );
}

class _StatusHistoryCard extends StatelessWidget {
  const _StatusHistoryCard({
    required this.future,
    required this.onRetry,
    required this.errorMessage,
  });

  final Future<List<MaintenanceStatusHistory>> future;
  final Future<void> Function() onRetry;
  final String Function(Object?) errorMessage;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        FutureBuilder<List<MaintenanceStatusHistory>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(errorMessage(snapshot.error)),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry history'),
                  ),
                ],
              );
            }
            final entries = snapshot.data ?? const <MaintenanceStatusHistory>[];
            if (entries.isEmpty) return const Text('No status history yet.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        '${entry.fromStatus == null ? 'Created' : _landlordMaintenanceLabel(entry.fromStatus!)}'
                        ' → ${_landlordMaintenanceLabel(entry.toStatus)}\n'
                        '${MaterialLocalizations.of(context).formatMediumDate(entry.changedAt.toLocal())}'
                        '${entry.notes == null ? '' : '\n${entry.notes}'}',
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    ),
  );
}

class _EstimateReviewDialog extends StatefulWidget {
  const _EstimateReviewDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.requiresNotes,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool requiresNotes;

  @override
  State<_EstimateReviewDialog> createState() => _EstimateReviewDialogState();
}

class _EstimateReviewDialogState extends State<_EstimateReviewDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const ValueKey('estimate-review-notes'),
            controller: _notesController,
            enabled: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 2000,
            validator: (value) {
              if (widget.requiresNotes && (value == null || value.trim().isEmpty)) {
                return 'Review notes are required.';
              }
              return null;
            },
            decoration: InputDecoration(
              labelText: widget.requiresNotes
                  ? 'Review notes'
                  : 'Review notes (optional)',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.of(context).pop(_notesController.text.trim());
          }
        },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppPalette.primaryText),
          ),
        ),
      ],
    ),
  );
}

class _MaintenanceRequestCard extends StatelessWidget {
  const _MaintenanceRequestCard({required this.request, required this.onTap});

  final MaintenanceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    child: Row(
      children: [
        const Icon(Icons.handyman_outlined, color: AppPalette.olive),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${_landlordMaintenanceLabel(request.category)} · '
                '${_landlordMaintenanceLabel(request.priority)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        StatusChip(
          label: _landlordMaintenanceLabel(request.status),
          tone: request.status == MaintenanceRequestStatus.submitted
              ? StatusTone.pending
              : StatusTone.progress,
        ),
      ],
    ),
  );
}

class _LandlordMaintenanceMessage extends StatelessWidget {
  const _LandlordMaintenanceMessage({
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
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppPalette.olive),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _maintenanceErrorMessage(Object? error) =>
    error is MaintenanceApiException
    ? error.message
    : 'Unable to load maintenance requests. Please try again.';
