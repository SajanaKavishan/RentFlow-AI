import 'package:flutter/material.dart';
import '../../properties/services/property_api_service.dart';
import '../../../shared/home/landlord_workspace_service.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/rental_application_status_chip.dart';
import 'landlord_rental_application_details_screen.dart';

class LandlordRentalApplicationsScreen extends StatefulWidget {
  const LandlordRentalApplicationsScreen({
    super.key,
    this.propertyId,
    this.propertyApiService,
    this.rentalApplicationApiService,
  });

  final String? propertyId;
  final PropertyApiService? propertyApiService;
  final RentalApplicationApiService? rentalApplicationApiService;

  @override
  State<LandlordRentalApplicationsScreen> createState() =>
      _LandlordRentalApplicationsScreenState();
}

class _LandlordRentalApplicationsScreenState
    extends State<LandlordRentalApplicationsScreen> {
  ApiClient? _ownedApiClient;
  late final RentalApplicationApiService _apiService;
  Future<List<RentalApplication>>? _applications;

  bool get _hasPropertyId =>
      widget.propertyApiService != null ||
      (widget.propertyId != null && widget.propertyId!.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    if (widget.rentalApplicationApiService case final service?) {
      _apiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _apiService = RentalApplicationApiService(_ownedApiClient!);
    }
    _load();
  }

  Future<List<RentalApplication>> _fetch() => widget.propertyApiService != null
      ? LandlordWorkspaceService(
          widget.propertyApiService!,
        ).applications(_apiService)
      : _apiService.getApplicationsByProperty(widget.propertyId!.trim());

  void _load() {
    _applications = _hasPropertyId ? _fetch() : null;
  }

  Future<void> _refresh() async {
    if (!_hasPropertyId) return;
    final request = _fetch();
    setState(() {
      _applications = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder renders the API-backed error state.
    }
  }

  Future<void> _openDetails(RentalApplication application) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LandlordRentalApplicationDetailsScreen(
          application: application,
          rentalApplicationApiService: _apiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  List<RentalApplication> _prioritized(List<RentalApplication> items) {
    final indexed = items.asMap().entries.toList(growable: false);
    int rank(RentalApplicationStatus status) => switch (status) {
      RentalApplicationStatus.submitted => 0,
      RentalApplicationStatus.underReview => 1,
      RentalApplicationStatus.changesRequested => 2,
      _ => 3,
    };
    indexed.sort((left, right) {
      final statusOrder = rank(
        left.value.status,
      ).compareTo(rank(right.value.status));
      if (statusOrder != 0) return statusOrder;
      final leftUpdated = left.value.updatedAt ?? left.value.createdAt;
      final rightUpdated = right.value.updatedAt ?? right.value.createdAt;
      final dateOrder = rightUpdated.compareTo(leftUpdated);
      return dateOrder != 0 ? dateOrder : left.key.compareTo(right.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  String _safeError(Object? error) {
    if (error is RentalApplicationApiException) return error.message;
    return 'Unable to load rental applications. Please try again.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    appBar: AppBar(
      title: const Text('Rental Applications'),
      actions: [
        if (_hasPropertyId)
          IconButton(
            tooltip: 'Refresh applications',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    ),
    body: !_hasPropertyId
        ? const ModuleUnavailableState(
            title: 'Application queue unavailable',
            explanation:
                'Applications will appear when property management supplies a property reference. Property integration is pending.',
          )
        : FutureBuilder<List<RentalApplication>>(
            future: _applications,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingState(
                  title: 'Loading applications',
                  message:
                      'Checking the latest applications for this property.',
                );
              }
              if (snapshot.hasError) {
                return ErrorState(
                  message: _safeError(snapshot.error),
                  onRetry: _refresh,
                );
              }
              final applications = _prioritized(
                snapshot.data ?? const <RentalApplication>[],
              );
              if (applications.isEmpty) {
                return const EmptyState(
                  title: 'No rental applications',
                  message:
                      'Real tenant applications for this property will appear here.',
                );
              }
              return RefreshIndicator(
                color: AppPalette.olive,
                onRefresh: _refresh,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppSpacing.page,
                  itemCount: applications.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.base),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader(
                              title: 'Review queue',
                              subtitle:
                                  'Submitted, under review and changes requested first.',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              '${applications.length} total · ${applications.where((item) => item.status == RentalApplicationStatus.submitted || item.status == RentalApplicationStatus.underReview).length} ready for your decision',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: AppPalette.olive),
                            ),
                          ],
                        ),
                      );
                    }
                    final application = applications[index - 1];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == applications.length
                            ? 0
                            : AppSpacing.md,
                      ),
                      child: _ApplicationReviewCard(
                        application: application,
                        onOpen: () => _openDetails(application),
                      ),
                    );
                  },
                ),
              );
            },
          ),
  );
}

class _ApplicationReviewCard extends StatelessWidget {
  const _ApplicationReviewCard({
    required this.application,
    required this.onOpen,
  });

  final RentalApplication application;
  final VoidCallback onOpen;

  bool get _needsReview => switch (application.status) {
    RentalApplicationStatus.submitted ||
    RentalApplicationStatus.underReview ||
    RentalApplicationStatus.changesRequested => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return AppCard(
      key: ValueKey('landlord-application-card-${application.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      application.status ==
                              RentalApplicationStatus.changesRequested
                          ? 'AWAITING TENANT UPDATE'
                          : _needsReview
                          ? 'READY FOR REVIEW'
                          : 'APPLICATION',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.olive,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .7,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    RentalApplicationStatusChip(status: application.status),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open application',
                onPressed: onOpen,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Reference(
            label: 'Property',
            value: application.propertyTitle ?? 'Property details unavailable',
          ),
          const SizedBox(height: AppSpacing.sm),
          _Reference(
            label: 'Applicant',
            value: application.applicantName ?? 'Applicant name unavailable',
          ),
          const Divider(height: AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Timestamp(
                label: 'Submitted',
                value: application.submittedAt == null
                    ? 'Not recorded'
                    : _formatTimestamp(localizations, application.submittedAt!),
              ),
              const SizedBox(height: AppSpacing.xs),
              _Timestamp(
                label: 'Updated',
                value: application.updatedAt == null
                    ? 'Not recorded'
                    : _formatTimestamp(localizations, application.updatedAt!),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Reference extends StatelessWidget {
  const _Reference({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: AppSpacing.xs),
      SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class _Timestamp extends StatelessWidget {
  const _Timestamp({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.schedule_outlined, size: 16, color: AppPalette.muted),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          '$label $value',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ],
  );
}

String _formatTimestamp(MaterialLocalizations localizations, DateTime value) {
  final local = value.toLocal();
  return '${localizations.formatMediumDate(local)}, ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
