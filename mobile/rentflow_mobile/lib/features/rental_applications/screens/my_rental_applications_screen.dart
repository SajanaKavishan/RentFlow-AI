import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../application_documents/screens/application_documents_screen.dart';
import '../../application_documents/services/application_document_api_service.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/rental_application_status_chip.dart';

class MyRentalApplicationsScreen extends StatefulWidget {
  const MyRentalApplicationsScreen({
    super.key,
    this.rentalApplicationApiService,
  });

  final RentalApplicationApiService? rentalApplicationApiService;

  @override
  State<MyRentalApplicationsScreen> createState() =>
      _MyRentalApplicationsScreenState();
}

class _MyRentalApplicationsScreenState
    extends State<MyRentalApplicationsScreen> {
  static const _olive = AppPalette.primary;

  ApiClient? _ownedApiClient;
  late final RentalApplicationApiService _apiService;
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
    _applications = _apiService.getMyApplications();
  }

  @override
  void dispose() {
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = _apiService.getMyApplications();
    setState(() {
      _applications = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the safe error state for this request.
    }
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
    RentalApplication? submitted;
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
    final now = DateTime.now().toUtc();
    final submittedApplication = (submitted ?? application).copyWith(
      status: RentalApplicationStatus.submitted,
      submittedAt: submitted?.submittedAt ?? now,
      updatedAt: submitted?.updatedAt ?? now,
    );
    final previousApplications = _applications;
    setState(() {
      _applications = _applicationsWithSubmission(
        previousApplications,
        submittedApplication,
      );
    });
    _showMessage(
      isResubmission
          ? 'Application resubmitted successfully.'
          : 'Application submitted successfully.',
    );

    try {
      final refreshedApplications = await _apiService.getMyApplications();
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
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : _olive,
        ),
      );
  }

  String _safeErrorMessage(Object? error) {
    if (error is RentalApplicationApiException) return error.message;
    return 'Unable to load your rental applications. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'My Applications',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<RentalApplication>>(
          future: _applications,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingState(
                title: 'Loading your applications',
                message: 'Getting the latest application updates.',
              );
            }

            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load applications',
                message: _safeErrorMessage(snapshot.error),
                actionLabel: 'Try again',
                onAction: _refresh,
                isError: true,
              );
            }

            final applications = snapshot.data ?? const <RentalApplication>[];
            if (applications.isEmpty) {
              return _MessageState(
                icon: Icons.description_outlined,
                title: 'No applications yet',
                message:
                    'Applications you create for a property will appear here.',
                actionLabel: 'Refresh',
                onAction: _refresh,
              );
            }

            return RefreshIndicator(
              color: AppPalette.primary,
              onRefresh: _refresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  AppSpacing.lg,
                  AppSpacing.base,
                  AppSpacing.xl,
                ),
                itemCount: applications.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: _ApplicationsHeader(count: applications.length),
                    );
                  }

                  final application = applications[index - 1];
                  final isSubmitting = _submittingIds.contains(application.id);
                  final isWithdrawing = _withdrawingIds.contains(
                    application.id,
                  );
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == applications.length ? 0 : AppSpacing.md,
                    ),
                    child: _ApplicationCard(
                      application: application,
                      canSubmit: _canSubmit(application),
                      canWithdraw: _canWithdraw(application),
                      isSubmitting: isSubmitting,
                      isWithdrawing: isWithdrawing,
                      onSubmit: () => _confirmSubmission(application),
                      onWithdraw: () => _confirmWithdrawal(application),
                      onDocuments: () => _openDocuments(application),
                    ),
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

class _ApplicationsHeader extends StatelessWidget {
  const _ApplicationsHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Application journey',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Pull down to check for status updates.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          '$count ${count == 1 ? 'application' : 'applications'}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppPalette.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.application,
    required this.canSubmit,
    required this.canWithdraw,
    required this.isSubmitting,
    required this.isWithdrawing,
    required this.onSubmit,
    required this.onWithdraw,
    required this.onDocuments,
  });

  final RentalApplication application;
  final bool canSubmit;
  final bool canWithdraw;
  final bool isSubmitting;
  final bool isWithdrawing;
  final VoidCallback onSubmit;
  final VoidCallback onWithdraw;
  final VoidCallback onDocuments;

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(application.moveInDate);
    final isBusy = isSubmitting || isWithdrawing;
    final isResubmission =
        application.status == RentalApplicationStatus.changesRequested;
    final (updateLabel, updateTimestamp) = switch (application) {
      RentalApplication(updatedAt: final timestamp?) => ('Updated', timestamp),
      RentalApplication(submittedAt: final timestamp?) => (
        'Submitted',
        timestamp,
      ),
      _ => ('Created', application.createdAt),
    };

    return Card(
      key: ValueKey('application-card-${application.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: isResubmission
          ? RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFB88635), width: 1.5),
              borderRadius: BorderRadius.circular(AppRadii.card),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isResubmission
                        ? const Color(0xFFF2E4D2)
                        : const Color(0xFFECEFDF),
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                  child: Icon(
                    isResubmission
                        ? Icons.priority_high_rounded
                        : Icons.description_outlined,
                    color: isResubmission
                        ? const Color(0xFF755028)
                        : AppPalette.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isResubmission ? 'ACTION NEEDED' : 'RENTAL APPLICATION',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isResubmission
                              ? const Color(0xFF755028)
                              : AppPalette.muted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Move in $date',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppPalette.text,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                RentalApplicationStatusChip(status: application.status),
              ],
            ),
            if (isResubmission) ...[
              const SizedBox(height: AppSpacing.base),
              _ChangesRequestedCallout(
                landlordResponse: application.landlordResponse,
              ),
            ],
            const SizedBox(height: AppSpacing.base),
            _ApplicationInfoRow(
              icon: Icons.home_work_outlined,
              label: 'Property reference',
              value: application.propertyId,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _SummaryItem(
                  icon: Icons.badge_outlined,
                  label: application.occupation,
                ),
                _SummaryItem(
                  icon: Icons.people_outline,
                  label:
                      '${application.numberOfOccupants} '
                      '${application.numberOfOccupants == 1 ? 'occupant' : 'occupants'}',
                ),
                _SummaryItem(
                  icon: Icons.payments_outlined,
                  label:
                      'Income ${application.monthlyIncome.toStringAsFixed(2)}',
                ),
              ],
            ),
            if (_hasText(application.tenantNote)) ...[
              const SizedBox(height: AppSpacing.base),
              _DetailBlock(
                label: 'Your note',
                value: application.tenantNote!.trim(),
              ),
            ],
            if (!isResubmission && _hasText(application.landlordResponse)) ...[
              const SizedBox(height: AppSpacing.md),
              _DetailBlock(
                label: 'Landlord response',
                value: application.landlordResponse!.trim(),
                highlighted: true,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _ApplicationTimestamp(
              label: updateLabel,
              timestamp: updateTimestamp,
            ),
            const SizedBox(height: AppSpacing.base),
            const Divider(height: 1, color: AppPalette.border),
            const SizedBox(height: AppSpacing.base),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: ValueKey('application-documents-${application.id}'),
                onPressed: isBusy ? null : onDocuments,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Documents'),
              ),
            ),
            if (canSubmit) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isBusy ? null : onSubmit,
                  icon: isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(
                    isSubmitting
                        ? (isResubmission ? 'Resubmitting...' : 'Submitting...')
                        : (isResubmission
                              ? 'Resubmit application'
                              : 'Submit application'),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
            if (canWithdraw) ...[
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: isBusy ? null : onWithdraw,
                  icon: isWithdrawing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.undo_outlined),
                  label: Text(
                    isWithdrawing ? 'Withdrawing...' : 'Withdraw application',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppPalette.danger,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
}

class _ChangesRequestedCallout extends StatelessWidget {
  const _ChangesRequestedCallout({required this.landlordResponse});

  final String? landlordResponse;

  @override
  Widget build(BuildContext context) {
    final response = landlordResponse?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E2),
        border: Border.all(color: const Color(0xFFE2BF86)),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.edit_notifications_outlined,
                size: 20,
                color: Color(0xFF755028),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Changes requested by the landlord',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF755028),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (response != null && response.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(response, style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Review the request, update available details or documents, then resubmit.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
          ),
        ],
      ),
    );
  }
}

class _ApplicationInfoRow extends StatelessWidget {
  const _ApplicationInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppPalette.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationTimestamp extends StatelessWidget {
  const _ApplicationTimestamp({required this.label, required this.timestamp});

  final String label;

  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final localTimestamp = timestamp.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(localTimestamp);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localTimestamp),
    );

    return Row(
      children: [
        const Icon(
          Icons.schedule_outlined,
          size: 18,
          color: AppPalette.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label $date at $time',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppPalette.muted),
          ),
        ),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppPalette.primary),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFECEFDF) : const Color(0xFFF5F3ED),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppPalette.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(value),
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
    required this.actionLabel,
    required this.onAction,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            key: ValueKey(
              isError ? 'applications-error' : 'applications-empty',
            ),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isError
                          ? const Color(0xFFF5DDDC)
                          : const Color(0xFFECEFDF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 32,
                      color: isError ? AppPalette.danger : AppPalette.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppPalette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppPalette.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_outlined),
                    label: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          key: const ValueKey('applications-loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 34,
              child: CircularProgressIndicator(
                color: AppPalette.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppPalette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
