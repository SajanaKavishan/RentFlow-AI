import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../application_documents/screens/application_documents_screen.dart';
import '../../application_documents/services/application_document_api_service.dart';
import '../../properties/models/property.dart';
import '../../properties/screens/property_list_screen.dart';
import '../../properties/services/property_api_service.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/tenant_application_journey.dart';
import 'rental_application_details_screen.dart';
import 'rental_application_form_screen.dart';

class MyRentalApplicationsScreen extends StatefulWidget {
  const MyRentalApplicationsScreen({
    super.key,
    this.rentalApplicationApiService,
    this.propertyApiService,
  });

  final RentalApplicationApiService? rentalApplicationApiService;
  final PropertyApiService? propertyApiService;

  @override
  State<MyRentalApplicationsScreen> createState() =>
      _MyRentalApplicationsScreenState();
}

class _MyRentalApplicationsScreenState
    extends State<MyRentalApplicationsScreen> {
  ApiClient? _ownedApiClient;
  late final RentalApplicationApiService _apiService;
  late final PropertyApiService _propertyApiService;
  final Map<String, Property?> _properties = {};
  late Future<List<RentalApplication>> _applications;
  final Set<String> _submittingIds = {};
  final Set<String> _withdrawingIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.rentalApplicationApiService case final service?) {
      _apiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _apiService = RentalApplicationApiService(_ownedApiClient!);
    }
    _propertyApiService =
        widget.propertyApiService ?? PropertyApiService(_apiService.apiClient);
    _applications = _loadApplications();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = _loadApplications();
    setState(() {
      _applications = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the safe error state for this request.
    }
  }

  Future<List<RentalApplication>> _loadApplications() async {
    final applications = await _apiService.getMyApplications();
    await Future.wait(
      applications.map((a) => a.propertyId).toSet().map((id) async {
        try {
          final property = await _propertyApiService.getPropertyById(id);
          _properties[id] = property.id == id ? property : null;
        } catch (_) {
          // Optional property information must not hide an application.
          _properties[id] = null;
        }
      }),
    );
    return applications;
  }

  Future<void> _browseProperties() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Browse properties')),
          body: PropertyListScreen(
            propertyApiService: _propertyApiService,
            rentalApplicationApiService: _apiService,
          ),
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  bool _canWithdraw(RentalApplication application) {
    return switch (application.status) {
      RentalApplicationStatus.draft ||
      RentalApplicationStatus.submitted ||
      RentalApplicationStatus.underReview ||
      RentalApplicationStatus.changesRequested => true,
      RentalApplicationStatus.approved ||
      RentalApplicationStatus.rejected ||
      RentalApplicationStatus.withdrawn => false,
    };
  }

  void _openDocuments(RentalApplication application) {
    if (kDebugMode) {
      debugPrint(
        '[MyApplications] Open Documents selectedApplicationId=${application.id}',
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApplicationDocumentsScreen(
          applicationId: application.id,
          rentalApplicationApiService: _apiService,
          applicationDocumentApiService: ApplicationDocumentApiService(
            _apiService.apiClient,
          ),
        ),
      ),
    );
  }

  Future<void> _openDetails(RentalApplication application) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RentalApplicationDetailsScreen(
          application: application,
          rentalApplicationApiService: _apiService,
          property: _properties[application.propertyId],
          propertyApiService: _propertyApiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _continueApplication(RentalApplication application) async {
    if (!_canSubmit(application)) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RentalApplicationFormScreen(
          propertyId: application.propertyId,
          propertyTitle: _properties[application.propertyId]?.title,
          application: application,
          rentalApplicationApiService: _apiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  bool _canSubmit(RentalApplication application) {
    return application.status == RentalApplicationStatus.draft ||
        application.status == RentalApplicationStatus.changesRequested;
  }

  Future<void> _confirmSubmission(RentalApplication application) async {
    if (!_canSubmit(application) ||
        _submittingIds.contains(application.id) ||
        _withdrawingIds.contains(application.id)) {
      return;
    }

    final isResubmission =
        application.status == RentalApplicationStatus.changesRequested;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isResubmission ? 'Resubmit application?' : 'Submit application?',
        ),
        content: Text(
          isResubmission
              ? 'Resubmit this rental application for landlord review?'
              : 'Submit this rental application for landlord review?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              isResubmission ? 'Resubmit application' : 'Submit application',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _submittingIds.add(application.id);
    });
    late final RentalApplication submitted;
    try {
      submitted = await _apiService.submitApplication(id: application.id);
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
      return;
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to submit your application right now. Please try again.',
          isError: true,
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _submittingIds.remove(application.id);
        });
      }
    }

    if (!mounted) return;
    final previousApplications = _applications;
    setState(() {
      _applications = _applicationsWithSubmission(
        previousApplications,
        submitted,
      );
    });
    _showMessage(
      isResubmission
          ? 'Application resubmitted successfully.'
          : 'Application submitted successfully.',
    );

    try {
      final refreshedApplications = await _loadApplications();
      if (!mounted) return;
      setState(() {
        _applications = Future.value(refreshedApplications);
      });
    } catch (_) {
      if (mounted) {
        _showMessage(
          isResubmission
              ? 'Application resubmitted, but your applications could not be refreshed.'
              : 'Application submitted, but your applications could not be refreshed.',
          isError: true,
        );
      }
    }
  }

  Future<List<RentalApplication>> _applicationsWithSubmission(
    Future<List<RentalApplication>> previousApplications,
    RentalApplication submittedApplication,
  ) async {
    try {
      final currentApplications = await previousApplications;
      return currentApplications
          .map(
            (item) => item.id == submittedApplication.id
                ? submittedApplication
                : item,
          )
          .toList(growable: false);
    } catch (_) {
      return [submittedApplication];
    }
  }

  Future<void> _confirmWithdrawal(RentalApplication application) async {
    if (_withdrawingIds.contains(application.id) ||
        _submittingIds.contains(application.id)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw this application?'),
        content: const Text(
          'The application will be withdrawn and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep application'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _withdrawingIds.add(application.id);
    });
    try {
      await _apiService.withdrawApplication(id: application.id);
      if (!mounted) return;
      _showMessage('Application withdrawn.');
      await _refresh();
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to withdraw the application right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _withdrawingIds.remove(application.id);
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    AppSnackbars.show(
      context,
      message: message,
      tone: isError ? SnackTone.error : SnackTone.success,
    );
  }

  List<RentalApplication> _prioritized(List<RentalApplication> applications) {
    final indexed = applications.asMap().entries.toList(growable: false);
    int rank(RentalApplicationStatus status) => switch (status) {
      RentalApplicationStatus.changesRequested => 0,
      RentalApplicationStatus.draft => 1,
      RentalApplicationStatus.submitted ||
      RentalApplicationStatus.underReview => 2,
      RentalApplicationStatus.approved ||
      RentalApplicationStatus.rejected ||
      RentalApplicationStatus.withdrawn => 3,
    };
    indexed.sort((left, right) {
      final statusOrder = rank(
        left.value.status,
      ).compareTo(rank(right.value.status));
      return statusOrder != 0 ? statusOrder : left.key.compareTo(right.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  String _safeErrorMessage(Object? error) {
    if (error is RentalApplicationApiException) return error.message;
    return 'Unable to load your rental applications. Please try again.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.warmCream,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: TenantApplicationHeader(
              eyebrow: 'RENTAL JOURNEY',
              title: 'My applications',
              onBack: Navigator.of(context).canPop()
                  ? () => Navigator.of(context).maybePop()
                  : null,
              onNew: _browseProperties,
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RentalApplication>>(
              future: _applications,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(24),
                      child: LoadingState(
                        key: ValueKey('applications-loading'),
                        title: 'Loading your applications',
                        message: 'Getting the latest application updates.',
                        compact: true,
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _ApplicationListState(
                    isError: true,
                    title: 'Could not load applications',
                    message: _safeErrorMessage(snapshot.error),
                    onRetry: _refresh,
                  );
                }
                final applications = _prioritized(snapshot.data ?? const []);
                if (applications.isEmpty) {
                  return _ApplicationListState(
                    title: 'No applications yet',
                    message:
                        'Find a home you like, then start an application from its property page.',
                    onBrowse: _browseProperties,
                    onRetry: _refresh,
                  );
                }
                return RefreshIndicator(
                  color: AppPalette.olive,
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: applications.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 20),
                    itemBuilder: (context, index) {
                      final application = applications[index];
                      return _ApplicationCard(
                        application: application,
                        propertyTitle:
                            _properties[application.propertyId]?.title,
                        canSubmit: _canSubmit(application),
                        canWithdraw: _canWithdraw(application),
                        isSubmitting: _submittingIds.contains(application.id),
                        isWithdrawing: _withdrawingIds.contains(application.id),
                        onSubmit: () => _confirmSubmission(application),
                        onWithdraw: () => _confirmWithdrawal(application),
                        onDocuments: () => _openDocuments(application),
                        onDetails: () => _openDetails(application),
                        onContinue: () => _continueApplication(application),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.application,
    required this.propertyTitle,
    required this.canSubmit,
    required this.canWithdraw,
    required this.isSubmitting,
    required this.isWithdrawing,
    required this.onSubmit,
    required this.onWithdraw,
    required this.onDocuments,
    required this.onDetails,
    required this.onContinue,
  });
  final RentalApplication application;
  final String? propertyTitle;
  final bool canSubmit;
  final bool canWithdraw;
  final bool isSubmitting;
  final bool isWithdrawing;
  final VoidCallback onSubmit;
  final VoidCallback onWithdraw;
  final VoidCallback onDocuments;
  final VoidCallback onDetails;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final busy = isSubmitting || isWithdrawing;
    final actionRequired =
        application.status == RentalApplicationStatus.changesRequested;
    final continueApplication =
        actionRequired || application.status == RentalApplicationStatus.draft;
    final response = application.landlordResponse?.trim();
    final metadata = [
      'Created ${applicationDate(context, application.createdAt)}',
      if (application.submittedAt case final timestamp?)
        'Submitted ${applicationDate(context, timestamp)}',
    ].join(' \u00b7 ');
    final summary = actionRequired && response != null && response.isNotEmpty
        ? response
        : application.updatedAt != null
        ? 'Updated ${applicationDate(context, application.updatedAt!)}'
        : applicationStatusSummary(application.status);
    return TenantApplicationCard(
      key: ValueKey('application-card-${application.id}'),
      actionRequired: actionRequired,
      onTap: busy ? null : onDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TenantApplicationStatusChip(
                    status: application.status,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('application-actions-${application.id}'),
                tooltip: 'Application actions',
                enabled: !busy,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.more_horiz,
                        size: 20,
                        color: AppPalette.olive,
                      ),
                onSelected: (value) {
                  switch (value) {
                    case 'documents':
                      onDocuments();
                    case 'submit':
                      onSubmit();
                    case 'withdraw':
                      onWithdraw();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'documents',
                    key: ValueKey('application-documents-${application.id}'),
                    child: const Text('Documents'),
                  ),
                  if (canSubmit)
                    PopupMenuItem(
                      value: 'submit',
                      child: Text(
                        actionRequired
                            ? 'Resubmit application'
                            : 'Submit application',
                      ),
                    ),
                  if (canWithdraw)
                    const PopupMenuItem(
                      value: 'withdraw',
                      child: Text('Withdraw application'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            propertyTitle?.trim().isNotEmpty == true
                ? propertyTitle!
                : 'Property details unavailable',
            style: AppTypography.sectionTitle.copyWith(
              fontWeight: FontWeight.w500,
              color: AppPalette.darkOlive,
            ),
          ),
          const SizedBox(height: 6),
          Text(metadata, style: applicationMetadata),
          const Divider(height: 28, thickness: 1),
          ApplicationJourneyActionRow(
            summary: Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: applicationMetadata,
            ),
            label: continueApplication ? 'Continue' : 'View details',
            actionKey: ValueKey('application-details-${application.id}'),
            onPressed: busy
                ? null
                : continueApplication
                ? onContinue
                : onDetails,
          ),
        ],
      ),
    );
  }
}

class _ApplicationListState extends StatelessWidget {
  const _ApplicationListState({
    required this.title,
    required this.message,
    required this.onRetry,
    this.onBrowse,
    this.isError = false,
  });
  final String title;
  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback? onBrowse;
  final bool isError;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        key: ValueKey(isError ? 'applications-error' : 'applications-empty'),
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: isError
                ? const Color(0xFFF5DDDC)
                : AppPalette.sage,
            child: Icon(
              isError ? Icons.cloud_off_outlined : Icons.description_outlined,
              color: isError ? AppPalette.danger : AppPalette.olive,
              size: 26,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: applicationSectionTitle,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppPalette.secondaryText),
          ),
          const SizedBox(height: 20),
          if (onBrowse != null)
            FilledButton(
              onPressed: onBrowse,
              child: const Text('Browse properties'),
            ),
          if (isError)
            OutlinedButton(onPressed: onRetry, child: const Text('Try again'))
          else
            TextButton(onPressed: onRetry, child: const Text('Refresh')),
        ],
      ),
    ),
  );
}
