import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
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
  static const _olive = Color(0xFF5D6842);
  static const _warmBackground = Color(0xFFF7F5EF);

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
      backgroundColor: _warmBackground,
      appBar: AppBar(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        title: const Text('My Rental Applications'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<RentalApplication>>(
          future: _applications,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _olive),
              );
            }

            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load applications',
                message: _safeErrorMessage(snapshot.error),
                actionLabel: 'Try again',
                onAction: _refresh,
              );
            }

            final applications = snapshot.data ?? const <RentalApplication>[];
            if (applications.isEmpty) {
              return _MessageState(
                icon: Icons.description_outlined,
                title: 'No applications yet',
                message: 'Your rental applications will appear here.',
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
                itemCount: applications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final application = applications[index];
                  final isSubmitting = _submittingIds.contains(application.id);
                  final isWithdrawing = _withdrawingIds.contains(
                    application.id,
                  );
                  return _ApplicationCard(
                    application: application,
                    canSubmit: _canSubmit(application),
                    canWithdraw: _canWithdraw(application),
                    isSubmitting: isSubmitting,
                    isWithdrawing: isWithdrawing,
                    onSubmit: () => _confirmSubmission(application),
                    onWithdraw: () => _confirmWithdrawal(application),
                    onDocuments: () => _openDocuments(application),
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
    final submittedAt = application.submittedAt;
    final isBusy = isSubmitting || isWithdrawing;
    final isResubmission =
        application.status == RentalApplicationStatus.changesRequested;

    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.home_work_outlined,
                  color: _MyRentalApplicationsScreenState._olive,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Move in $date',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(application.occupation),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                RentalApplicationStatusChip(status: application.status),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryItem(
                  icon: Icons.payments_outlined,
                  label:
                      'Income ${application.monthlyIncome.toStringAsFixed(2)}',
                ),
                _SummaryItem(
                  icon: Icons.people_outline,
                  label:
                      '${application.numberOfOccupants} '
                      '${application.numberOfOccupants == 1 ? 'occupant' : 'occupants'}',
                ),
              ],
            ),
            if (_hasText(application.tenantNote)) ...[
              const SizedBox(height: 16),
              _DetailBlock(
                label: 'Your note',
                value: application.tenantNote!.trim(),
              ),
            ],
            if (_hasText(application.landlordResponse)) ...[
              const SizedBox(height: 12),
              _DetailBlock(
                label: 'Landlord response',
                value: application.landlordResponse!.trim(),
                highlighted: true,
              ),
            ],
            if (submittedAt != null) ...[
              const SizedBox(height: 12),
              _SubmittedAt(timestamp: submittedAt),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: ValueKey('application-documents-${application.id}'),
              onPressed: isBusy ? null : onDocuments,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Documents'),
            ),
            if (canSubmit) ...[
              const SizedBox(height: 16),
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
                    backgroundColor: _MyRentalApplicationsScreenState._olive,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
            if (canWithdraw) ...[
              SizedBox(height: canSubmit ? 4 : 16),
              Align(
                alignment: Alignment.centerRight,
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
                    foregroundColor: Colors.red.shade700,
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

class _SubmittedAt extends StatelessWidget {
  const _SubmittedAt({required this.timestamp});

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
          color: _MyRentalApplicationsScreenState._olive,
        ),
        const SizedBox(width: 6),
        Expanded(child: Text('Submitted $date at $time')),
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
        color: const Color(0xFFF5F3ED),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: _MyRentalApplicationsScreenState._olive),
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: _MyRentalApplicationsScreenState._olive,
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
              color: _MyRentalApplicationsScreenState._olive,
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
