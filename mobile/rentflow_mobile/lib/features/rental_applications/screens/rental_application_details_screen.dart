import 'package:flutter/material.dart';
import '../../../shared/follow_up/follow_up_activity.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../application_documents/models/application_document.dart';
import '../../application_documents/screens/application_documents_screen.dart';
import '../../application_documents/services/application_document_api_service.dart';
import '../../properties/models/property.dart';
import '../../properties/services/property_api_service.dart';
import '../models/rental_application.dart';
import '../services/rental_application_api_service.dart';
import '../widgets/tenant_application_journey.dart';
import 'rental_application_form_screen.dart';

class RentalApplicationDetailsScreen extends StatefulWidget {
  const RentalApplicationDetailsScreen({
    super.key,
    required this.application,
    required this.rentalApplicationApiService,
    this.applicationDocumentApiService,
    this.property,
    this.propertyApiService,
  });

  final RentalApplication application;
  final RentalApplicationApiService rentalApplicationApiService;
  final ApplicationDocumentApiService? applicationDocumentApiService;
  final Property? property;
  final PropertyApiService? propertyApiService;

  @override
  State<RentalApplicationDetailsScreen> createState() =>
      _RentalApplicationDetailsScreenState();
}

class _RentalApplicationDetailsScreenState
    extends State<RentalApplicationDetailsScreen>
    with WidgetsBindingObserver {
  late RentalApplication _application;
  late final ApplicationDocumentApiService _documentApiService;
  late Future<List<ApplicationDocument>> _documents;
  late final PropertyApiService _properties;
  Property? _property;
  bool _refreshing = false;
  bool _fresh = false;
  String? _error;
  bool _isSubmitting = false;
  bool _isWithdrawing = false;

  bool get _isBusy => _isSubmitting || _isWithdrawing;

  bool get _canWithdraw => switch (_application.status) {
    RentalApplicationStatus.draft ||
    RentalApplicationStatus.submitted ||
    RentalApplicationStatus.underReview ||
    RentalApplicationStatus.changesRequested => true,
    RentalApplicationStatus.approved ||
    RentalApplicationStatus.rejected ||
    RentalApplicationStatus.withdrawn => false,
  };

  bool get _canResubmit =>
      _application.status == RentalApplicationStatus.changesRequested;

  bool get _canContinue => _application.status == RentalApplicationStatus.draft;

  bool get _canEdit =>
      _application.status == RentalApplicationStatus.changesRequested;

  @override
  void initState() {
    super.initState();
    _application = widget.application;
    _documentApiService =
        widget.applicationDocumentApiService ??
        ApplicationDocumentApiService(
          widget.rentalApplicationApiService.apiClient,
        );
    _properties =
        widget.propertyApiService ??
        PropertyApiService(widget.rentalApplicationApiService.apiClient);
    _property = widget.property?.id == _application.propertyId
        ? widget.property
        : null;
    _documents = Future.value(const []);
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || _isBusy) return;
    setState(() {
      _refreshing = true;
      _fresh = false;
      _error = null;
    });
    try {
      final application = await widget.rentalApplicationApiService
          .getApplicationById(widget.application.id);
      if (application.id != widget.application.id ||
          application.tenantId != widget.application.tenantId ||
          application.propertyId != widget.application.propertyId) {
        throw const RentalApplicationApiException(
          'The application service returned an invalid response.',
        );
      }
      Property? property = _property;
      try {
        final fetched = await _properties.getPropertyById(
          application.propertyId,
        );
        if (fetched.id == application.propertyId) property = fetched;
      } catch (_) {
        // Retain only a previously fetched real title; property data is optional.
      }
      if (!mounted) return;
      setState(() {
        _application = application;
        _property = property;
        _documents = _loadDocuments();
        _fresh = true;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is RentalApplicationApiException
              ? error.message
              : 'Unable to load this application. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<List<ApplicationDocument>> _loadDocuments() {
    final documents = _documentApiService.getDocumentsForApplication(
      applicationId: _application.id,
    );
    // Handle fast failures before the next frame attaches the FutureBuilder.
    // The original future still delivers its error to the summary's retry UI.
    documents.ignore();
    return documents;
  }

  void _retryDocuments() {
    final documents = _loadDocuments();
    setState(() {
      _documents = documents;
    });
  }

  Future<void> _openForm() async {
    if (!_fresh || _isBusy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RentalApplicationFormScreen(
          propertyId: _application.propertyId,
          propertyTitle: _property?.title,
          application: _application,
          returnToApplicationDetails: true,
          rentalApplicationApiService: widget.rentalApplicationApiService,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openDocuments() async {
    if (!_fresh || _isBusy) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApplicationDocumentsScreen(
          applicationId: _application.id,
          rentalApplicationApiService: widget.rentalApplicationApiService,
          applicationDocumentApiService: _documentApiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _resubmit() async {
    if (!_fresh || !_canResubmit || _isBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.send_outlined),
        title: const Text('Resubmit application?'),
        content: const Text(
          'Resubmit this updated rental application for landlord review?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resubmit application'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final submitted = await widget.rentalApplicationApiService
          .submitApplication(id: _application.id);
      if (!mounted) return;
      setState(() => _application = submitted);
      _showMessage('Application resubmitted successfully.');
    } on RentalApplicationApiException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to resubmit your application right now. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _withdraw() async {
    if (!_fresh || !_canWithdraw || _isBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.undo_outlined),
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
            style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWithdrawing = true);
    try {
      final withdrawn = await widget.rentalApplicationApiService
          .withdrawApplication(id: _application.id);
      if (!mounted) return;
      setState(() => _application = withdrawn);
      _showMessage('Application withdrawn.');
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
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    AppSnackbars.show(
      context,
      message: message,
      tone: isError ? SnackTone.error : SnackTone.success,
    );
  }

  @override
  Widget build(BuildContext context) =>
      FollowUpPause(active: _isSubmitting, child: _buildScaffold(context));

  Widget _buildScaffold(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.warmCream,
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TenantApplicationHeader(
                    eyebrow: 'APPLICATION',
                    title: _property?.title.trim().isNotEmpty == true
                        ? _property!.title
                        : 'Application details',
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 24),
                  if (_refreshing)
                    const LoadingState(
                      title: 'Loading application details',
                      compact: true,
                    ),
                  if (_error != null)
                    SharedState(
                      title: 'Could not load application',
                      message: _error!,
                      actionLabel: 'Try again',
                      onAction: _refresh,
                      compact: true,
                    ),
                  if (_fresh) ...[
                    _statusHero(),
                    const Divider(height: 40),
                    Text(
                      'Application progress',
                      style: applicationSectionTitle,
                    ),
                    const SizedBox(height: 18),
                    _ApplicationTimeline(application: _application),
                    const Divider(height: 40),
                    Text('Documents', style: applicationSectionTitle),
                    const SizedBox(height: 12),
                    _DocumentSummary(
                      documents: _documents,
                      onRetry: _retryDocuments,
                      onOpen: _isBusy ? null : _openDocuments,
                    ),
                    if (_application.status ==
                            RentalApplicationStatus.submitted ||
                        _application.status ==
                            RentalApplicationStatus.underReview) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppPalette.sage,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: AppPalette.olive,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Landlord review',
                                    style: AppTypography.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.darkOlive,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'The landlord reviews your application and makes the final decision.',
                                    style: applicationMetadata,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 40),
                    Text(
                      'Application overview',
                      style: applicationSectionTitle,
                    ),
                    const SizedBox(height: 12),
                    TenantApplicationCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DetailRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Requested move-in',
                            value: MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(_application.moveInDate),
                          ),
                          const Divider(height: 24),
                          _DetailRow(
                            icon: Icons.work_outline,
                            label: 'Occupation',
                            value: _application.occupation,
                          ),
                          const Divider(height: 24),
                          _DetailRow(
                            icon: Icons.people_outline,
                            label: 'Occupants',
                            value: _application.numberOfOccupants.toString(),
                          ),
                          const Divider(height: 24),
                          _DetailRow(
                            icon: Icons.payments_outlined,
                            label: 'Monthly income',
                            value: _application.monthlyIncome.toStringAsFixed(
                              2,
                            ),
                          ),
                          if (_application.tenantNote?.trim().isNotEmpty ==
                              true) ...[
                            const Divider(height: 24),
                            _DetailRow(
                              icon: Icons.notes_outlined,
                              label: 'Your note',
                              value: _application.tenantNote!.trim(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_canResubmit || _canWithdraw) ...[
                      const SizedBox(height: 20),
                      if (_canResubmit)
                        FilledButton.icon(
                          onPressed: _isBusy ? null : _resubmit,
                          icon: _isSubmitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppPalette.white,
                                  ),
                                )
                              : const Icon(Icons.send_outlined, size: 18),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          label: Text(
                            _isSubmitting
                                ? 'Resubmitting...'
                                : 'Resubmit application',
                          ),
                        ),
                      if (_canWithdraw)
                        TextButton(
                          onPressed: _isBusy ? null : _withdraw,
                          style: TextButton.styleFrom(
                            foregroundColor: AppPalette.danger,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: Text(
                            _isWithdrawing
                                ? 'Withdrawing...'
                                : 'Withdraw application',
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _statusHero() {
    final response = _application.landlordResponse?.trim();
    final hasResponse = response != null && response.isNotEmpty;
    final actionRequired =
        _application.status == RentalApplicationStatus.changesRequested;
    final (title, body) = switch (_application.status) {
      RentalApplicationStatus.draft => (
        'Finish your application',
        'Your application is saved as a draft. Review your details and documents before submitting.',
      ),
      RentalApplicationStatus.submitted => (
        'Application submitted',
        'Your application has been submitted for landlord review.',
      ),
      RentalApplicationStatus.underReview => (
        'Under landlord review',
        'The landlord is reviewing your application. You can check back here for updates.',
      ),
      RentalApplicationStatus.changesRequested => (
        hasResponse ? response : 'Updates requested',
        'Update your application details or documents, then resubmit for landlord review.',
      ),
      RentalApplicationStatus.approved => (
        'Your application is approved',
        'The landlord has approved your rental application.',
      ),
      RentalApplicationStatus.rejected => (
        'Application declined',
        'The landlord has declined your rental application.',
      ),
      RentalApplicationStatus.withdrawn => (
        'Application withdrawn',
        'This application has been withdrawn.',
      ),
    };
    return TenantApplicationCard(
      key: const ValueKey('application-status-hero'),
      actionRequired: actionRequired,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TenantApplicationStatusChip(status: _application.status),
          ),
          const SizedBox(height: 16),
          Text(title, style: applicationSectionTitle),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTypography.body.copyWith(color: AppPalette.secondaryText),
          ),
          if (hasResponse && !actionRequired) ...[
            const SizedBox(height: 16),
            Text(
              'Landlord response',
              style: applicationMetadata.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(response, style: AppTypography.body),
          ],
          if (_canContinue || _canEdit) ...[
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('continue-rental-application'),
              onPressed: _isBusy ? null : _openForm,
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.darkOlive,
                foregroundColor: AppPalette.white,
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                textStyle: AppTypography.button.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Continue application'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppPalette.olive),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: applicationMetadata),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.body.copyWith(color: AppPalette.darkOlive),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ApplicationTimeline extends StatelessWidget {
  const _ApplicationTimeline({required this.application});
  final RentalApplication application;
  @override
  Widget build(BuildContext context) {
    // UpdatedAt can also mean a tenant edit, so never label it as a review
    // milestone or a decision date. SubmittedAt is the latest submission.
    final events = <(String, DateTime)>[
      ('Application created', application.createdAt),
      if (application.submittedAt case final timestamp?)
        ('Application submitted', timestamp),
      if (application.updatedAt case final timestamp?
          when timestamp != application.submittedAt &&
              timestamp != application.createdAt)
        ('Last updated', timestamp),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          _TimelineItem(
            label: events[i].$1,
            timestamp: events[i].$2,
            isLast: i == events.length - 1,
          ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.label,
    required this.timestamp,
    required this.isLast,
  });
  final String label;
  final DateTime timestamp;
  final bool isLast;
  @override
  Widget build(BuildContext context) {
    final local = timestamp.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date =
        '${localizations.formatMediumDate(local)} at ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 5),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isLast ? AppPalette.darkOlive : AppPalette.sage,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  const Expanded(
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppPalette.outline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.body.copyWith(
                      color: AppPalette.darkOlive,
                      fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(date, style: applicationMetadata),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentSummary extends StatelessWidget {
  const _DocumentSummary({
    required this.documents,
    required this.onRetry,
    required this.onOpen,
  });
  final Future<List<ApplicationDocument>> documents;
  final VoidCallback onRetry;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => TenantApplicationCard(
    child: FutureBuilder<List<ApplicationDocument>>(
      future: documents,
      builder: (context, snapshot) {
        final Widget summary;
        if (snapshot.connectionState != ConnectionState.done) {
          summary = Text(
            'Loading document summary',
            style: applicationMetadata,
          );
        } else if (snapshot.hasError) {
          summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The document summary is currently unavailable.',
                style: applicationMetadata,
              ),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          );
        } else {
          final count = snapshot.data?.length ?? 0;
          summary = Text(
            count == 0
                ? 'No documents uploaded'
                : '$count ${count == 1 ? 'document' : 'documents'} uploaded',
            style: applicationMetadata,
          );
        }
        return ApplicationJourneyActionRow(
          summary: summary,
          label: 'Manage',
          actionKey: const ValueKey('manage-application-documents'),
          onPressed: onOpen,
        );
      },
    ),
  );
}
