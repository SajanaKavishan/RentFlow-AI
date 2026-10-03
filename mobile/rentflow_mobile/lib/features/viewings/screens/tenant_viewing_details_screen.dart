import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../properties/models/landlord_contact.dart';
import '../../properties/models/property.dart';
import '../../properties/screens/property_details_screen.dart';
import '../../properties/services/property_api_service.dart';
import '../../properties/widgets/landlord_contact_card.dart'
    show landlordDialerUri;
import '../../properties/widgets/property_photo.dart';
import '../models/viewing.dart';
import '../services/viewing_api_service.dart';

class TenantViewingDetailsScreen extends StatefulWidget {
  const TenantViewingDetailsScreen({
    super.key,
    required this.viewingId,
    required this.viewingApiService,
    this.propertyApiService,
    this.nowProvider,
  });

  final String viewingId;
  final ViewingApiService viewingApiService;
  final PropertyApiService? propertyApiService;
  final DateTime Function()? nowProvider;

  @override
  State<TenantViewingDetailsScreen> createState() =>
      _TenantViewingDetailsScreenState();
}

class _TenantViewingDetailsScreenState extends State<TenantViewingDetailsScreen>
    with WidgetsBindingObserver {
  late final PropertyApiService _properties;
  Viewing? _viewing;
  Property? _property;
  LandlordContact? _landlordContact;
  String? _error;
  bool _refreshing = false;
  bool _cancelling = false;
  bool _fresh = false;
  bool _calling = false;
  Timer? _cancellationExpiry;

  DateTime get _now => widget.nowProvider?.call() ?? DateTime.now();
  bool get _canCancel => _fresh && (_viewing?.canCancel ?? false);
  bool get _windowClosed =>
      _fresh &&
      _viewing?.status == ViewingStatus.approved &&
      !_viewing!.canCancel;

  @override
  void initState() {
    super.initState();
    _properties =
        widget.propertyApiService ??
        PropertyApiService(widget.viewingApiService.apiClient);
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancellationExpiry?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _refresh();
    }
  }

  void _checkIdentity(Viewing viewing) {
    if (viewing.id != widget.viewingId ||
        (_viewing != null &&
            (viewing.propertyId != _viewing!.propertyId ||
                viewing.tenantId != _viewing!.tenantId))) {
      throw const ViewingApiException(
        'The viewing service returned an invalid response.',
      );
    }
  }

  void _setViewing(Viewing viewing) {
    _viewing = viewing;
    _fresh = true;
    _cancellationExpiry?.cancel();
    if (viewing.canCancel) {
      // The timestamp schedules a server refresh, never a local policy decision.
      // Refresh just after the inclusive Approved boundary.
      final refreshAt =
          viewing.cancellationDeadline ?? viewing.requestedDateTime;
      final delay =
          refreshAt.difference(_now) + const Duration(milliseconds: 1);
      _cancellationExpiry = Timer(
        delay <= Duration.zero ? const Duration(seconds: 30) : delay,
        _refresh,
      );
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || _cancelling) return;
    setState(() {
      _refreshing = true;
      _fresh = false;
      _landlordContact = null;
      _error = null;
    });
    try {
      final viewing = await widget.viewingApiService.getViewingById(
        widget.viewingId,
      );
      _checkIdentity(viewing);
      Property? property;
      try {
        final fetched = await _properties.getPropertyById(viewing.propertyId);
        if (fetched.id == viewing.propertyId) property = fetched;
      } catch (_) {
        // A removed property must not hide the authoritative viewing.
      }
      LandlordContact? contact;
      if (viewing.status == ViewingStatus.approved && !viewing.canCancel) {
        try {
          contact = await _properties.getLandlordContact(viewing.propertyId);
        } catch (_) {
          // Public contact is optional and always fails closed.
        }
      }
      if (!mounted) return;
      setState(() {
        _setViewing(viewing);
        _property = property;
        _landlordContact = contact;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to refresh this viewing. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _callLandlord() async {
    if (!_windowClosed || _landlordContact == null || _calling) return;
    setState(() => _calling = true);
    try {
      // Recheck publication before launching, including after a privacy change.
      final contact = await _properties.getLandlordContact(
        _viewing!.propertyId,
      );
      if (!mounted) return;
      setState(() => _landlordContact = contact);
      final uri = contact == null
          ? null
          : landlordDialerUri(contact.phoneNumber);
      if (uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Missing contact or a device without a dialer must stay safe.
    } finally {
      if (mounted) setState(() => _calling = false);
    }
    if (mounted) {
      AppSnackbars.show(
        context,
        message: 'Calling is not available right now.',
      );
    }
  }

  Future<void> _openProperty() async {
    final property = _property;
    if (property == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PropertyDetailsScreen(
          property: property,
          propertyApiService: _properties,
          viewingApiService: widget.viewingApiService,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _cancel() async {
    if (!_canCancel || _cancelling || _refreshing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this viewing?'),
        content: const Text(
          'The viewing request will be cancelled and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep viewing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel viewing'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_canCancel) return;
    setState(() => _cancelling = true);
    try {
      final cancelled = await widget.viewingApiService.cancelViewing(
        id: widget.viewingId,
      );
      _checkIdentity(cancelled);
      if (cancelled.status != ViewingStatus.cancelled) {
        throw const ViewingApiException(
          'The viewing service did not confirm the cancellation.',
        );
      }
      if (!mounted) return;
      setState(() {
        _setViewing(cancelled);
        _error = null;
      });
      AppSnackbars.show(context, message: 'Viewing cancelled.');
    } catch (error) {
      if (!mounted) return;
      AppSnackbars.show(
        context,
        message: error is ViewingApiException
            ? error.message
            : 'Unable to cancel the viewing right now. Please try again.',
        tone: SnackTone.error,
      );
      // Status or the cancellation window may have changed while this was open.
      setState(() => _cancelling = false);
      await _refresh();
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton.outlined(
                        tooltip: 'Back to my viewings',
                        style: IconButton.styleFrom(
                          backgroundColor: AppPalette.white,
                          side: const BorderSide(color: AppPalette.outline),
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MY VIEWINGS', style: _eyebrow),
                            const SizedBox(height: 4),
                            Text(
                              'Viewing details',
                              style: AppTypography.pageTitle.copyWith(
                                fontWeight: FontWeight.w500,
                                color: AppPalette.darkOlive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                  if (_error != null) ...[
                    SharedState(
                      title: _viewing == null
                          ? 'Could not load viewing'
                          : 'Could not refresh viewing',
                      message: _error!,
                      actionLabel: 'Try again',
                      onAction: _refresh,
                      compact: true,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_viewing case final viewing?) ...[
                    _propertySummary(),
                    const SizedBox(height: 20),
                    _StatusHero(viewing: viewing),
                    const SizedBox(height: 24),
                    _schedule(viewing),
                    if (viewing.tenantMessage?.trim() case final note?
                        when note.isNotEmpty) ...[
                      _separator,
                      _heading('Your note'),
                      const SizedBox(height: 12),
                      AppCard(
                        color: AppPalette.softCream,
                        child: Container(
                          padding: const EdgeInsets.only(left: 12),
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: AppPalette.sage),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SENT WITH YOUR REQUEST', style: _eyebrow),
                              const SizedBox(height: 12),
                              Text('“$note”', style: _body),
                            ],
                          ),
                        ),
                      ),
                    ],
                    _separator,
                    _heading('Landlord response'),
                    const SizedBox(height: 12),
                    _LandlordResponse(viewing: viewing),
                    _separator,
                    _lastUpdated(viewing),
                    const SizedBox(height: 24),
                  ],
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.darkOlive,
                      foregroundColor: AppPalette.white,
                      textStyle: AppTypography.button,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Back to my viewings'),
                  ),
                  if (_canCancel) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _cancelling || _refreshing ? null : _cancel,
                      style: TextButton.styleFrom(
                        foregroundColor: AppPalette.danger,
                        textStyle: AppTypography.button,
                      ),
                      child: Text(
                        _cancelling ? 'Cancelling...' : 'Cancel request',
                      ),
                    ),
                    Text(
                      _viewing?.status == ViewingStatus.approved
                          ? 'You can cancel up to 5 hours before the viewing.'
                          : 'You can cancel before the viewing takes place.',
                      textAlign: TextAlign.center,
                      style: _helper,
                    ),
                  ],
                  if (_windowClosed) ...[
                    const SizedBox(height: 16),
                    _heading('Need help with this viewing?'),
                    const SizedBox(height: 6),
                    Text(
                      _landlordContact != null
                          ? 'Your cancellation window has closed. If your plans change, contact the landlord directly.'
                          : 'Your cancellation window has closed. Please follow the viewing arrangements provided by the landlord.',
                      style: _body.copyWith(color: AppPalette.secondaryText),
                    ),
                    if (_landlordContact != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _calling ? null : _callLandlord,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppPalette.darkOlive,
                          textStyle: AppTypography.button,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.phone_outlined, size: 18),
                        label: const Text('Call landlord'),
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

  Widget _propertySummary() {
    final property = _property;
    final location = [property?.address, property?.city]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(', ');
    return Semantics(
      button: property != null,
      child: InkWell(
        key: const ValueKey('viewing-property-summary'),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        onTap: property == null ? null : _openProperty,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.small),
              child: SizedBox.square(
                dimension: 68,
                child: PropertyPhoto(
                  propertyId: _viewing!.propertyId,
                  propertyApiService: property == null ? null : _properties,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR REQUESTED HOME', style: _eyebrow),
                  const SizedBox(height: 6),
                  Text(
                    property?.title ?? 'Property details unavailable',
                    style: AppTypography.cardTitle.copyWith(
                      color: AppPalette.darkOlive,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppPalette.muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: Text(location, style: _secondary)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _schedule(Viewing viewing) {
    final localizations = MaterialLocalizations.of(context);
    // Prefer API property-zone fields. Legacy records follow the established
    // Asia/Colombo convention rather than the device's time zone.
    final local = _colombo(viewing.requestedDateTime);
    final date = DateTime.tryParse(viewing.requestedLocalDate ?? '') ?? local;
    final time =
        viewing.requestedDisplayTime ??
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    final heading = switch (viewing.status) {
      ViewingStatus.approved => 'Confirmed viewing',
      ViewingStatus.completed => 'Viewing date',
      _ => 'Requested viewing',
    };
    final month = localizations.formatMonthYear(date).split(' ').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _heading(heading)),
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: AppPalette.olive,
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    month
                        .substring(0, month.length < 3 ? month.length : 3)
                        .toUpperCase(),
                    style: _eyebrow,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: AppTypography.pageTitle.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppPalette.darkOlive,
                    ),
                  ),
                ],
              ),
              Container(
                width: 1,
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: AppPalette.outline,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(localizations.formatFullDate(date), style: _body),
                    const SizedBox(height: 4),
                    Text('$time · Local property time', style: _secondary),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (viewing.status == ViewingStatus.pending) ...[
          const SizedBox(height: 10),
          Text(
            'Keep this time in mind while you await a response.',
            style: _helper,
          ),
        ],
      ],
    );
  }

  Widget _lastUpdated(Viewing viewing) {
    final localizations = MaterialLocalizations.of(context);
    final updated = _colombo(viewing.updatedAt ?? viewing.createdAt);
    final today = DateUtils.isSameDay(updated, _colombo(_now));
    final date = today ? 'Today' : localizations.formatShortDate(updated);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(updated));
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text('Last updated', style: _helper),
        Text('$date at $time', style: _helper),
      ],
    );
  }
}

DateTime _colombo(DateTime value) =>
    value.toUtc().add(const Duration(hours: 5, minutes: 30));

final _eyebrow = AppTypography.eyebrow.copyWith(
  color: AppPalette.olive,
  fontWeight: FontWeight.w600,
);
final _body = AppTypography.body.copyWith(color: AppPalette.darkOlive);
final _secondary = AppTypography.label.copyWith(
  color: AppPalette.secondaryText,
  fontWeight: FontWeight.w400,
);
final _helper = AppTypography.caption.copyWith(
  fontSize: 12,
  color: AppPalette.secondaryText,
  fontWeight: FontWeight.w400,
);
const _separator = Divider(height: 40, thickness: 1);
Widget _heading(String text) => Text(
  text,
  style: AppTypography.cardTitle.copyWith(
    color: AppPalette.darkOlive,
    fontWeight: FontWeight.w500,
  ),
);

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.viewing});
  final Viewing viewing;

  @override
  Widget build(BuildContext context) {
    final hasResponse = viewing.landlordResponse?.trim().isNotEmpty ?? false;
    final (title, body, color, foreground) = switch (viewing.status) {
      ViewingStatus.pending => (
        'Waiting for the landlord',
        'Your request has been sent. Your viewing is not confirmed until the landlord approves it.',
        const Color(0xFFFBF0D4),
        AppPalette.warning,
      ),
      ViewingStatus.approved => (
        'Your viewing is confirmed',
        hasResponse
            ? 'The landlord has approved your request. See their message below before you visit.'
            : 'The landlord has approved your request.',
        AppPalette.sage,
        AppPalette.darkOlive,
      ),
      ViewingStatus.rejected => (
        'Viewing request declined',
        'The landlord was unable to approve this viewing request.',
        const Color(0xFFF5DDDC),
        AppPalette.danger,
      ),
      ViewingStatus.cancelled => (
        'Viewing request cancelled',
        'This viewing request has been cancelled.',
        AppPalette.softCream,
        AppPalette.neutral,
      ),
      ViewingStatus.completed => (
        'Viewing completed',
        'This viewing has already taken place.',
        AppPalette.progress,
        AppPalette.darkOlive,
      ),
    };
    return AppCard(
      key: const ValueKey('viewing-status-hero'),
      color: color,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            viewing.status.name.toUpperCase(),
            style: _eyebrow.copyWith(color: foreground),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTypography.sectionTitle.copyWith(
              fontWeight: FontWeight.w500,
              color: AppPalette.darkOlive,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTypography.bodySmall.copyWith(
              color: AppPalette.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandlordResponse extends StatelessWidget {
  const _LandlordResponse({required this.viewing});
  final Viewing viewing;

  @override
  Widget build(BuildContext context) {
    final response = viewing.landlordResponse?.trim();
    final hasResponse = response != null && response.isNotEmpty;
    final pending = viewing.status == ViewingStatus.pending;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppPalette.softCream,
          child: Icon(
            hasResponse ? Icons.person_outline : Icons.notifications_none,
            size: 20,
            color: AppPalette.olive,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasResponse
                    ? response
                    : pending
                    ? 'No response yet'
                    : 'No message provided',
                style: _body,
              ),
              if (!hasResponse && pending) ...[
                const SizedBox(height: 6),
                Text(
                  "You'll be notified when the landlord responds to your request.",
                  style: _secondary,
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return hasResponse
        ? AppCard(padding: const EdgeInsets.all(14), child: content)
        : content;
  }
}
