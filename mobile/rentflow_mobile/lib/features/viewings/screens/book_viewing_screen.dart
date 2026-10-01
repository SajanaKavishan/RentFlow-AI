import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/viewing.dart';
import '../services/viewing_api_service.dart';

class BookViewingScreen extends StatefulWidget {
  const BookViewingScreen({
    super.key,
    required this.propertyId,
    this.propertyTitle,
    this.viewingApiService,
  });

  final String propertyId;
  final String? propertyTitle;
  final ViewingApiService? viewingApiService;

  @override
  State<BookViewingScreen> createState() => _BookViewingScreenState();
}

class _BookViewingScreenState extends State<BookViewingScreen> {
  final _messageController = TextEditingController();
  ApiClient? _ownedApiClient;
  late final ViewingApiService _viewingApiService;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _submissionError;
  bool _isSubmitting = false;

  bool get _hasPropertyReference => widget.propertyId.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.viewingApiService case final service?) {
      _viewingApiService = service;
    } else {
      _ownedApiClient = ApiClient();
      _viewingApiService = ViewingApiService(_ownedApiClient!);
    }
    _messageController.addListener(_onMessageChanged);
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_onMessageChanged)
      ..dispose();
    _ownedApiClient?.close();
    super.dispose();
  }

  void _onMessageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Choose a viewing date',
    );

    if (selected == null || !mounted) return;
    setState(() {
      _selectedDate = selected;
      _submissionError = null;
      if (_selectedTime != null && !_combinedDateTime().isAfter(now)) {
        _selectedTime = null;
      }
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime:
          _selectedTime ??
          TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))),
      helpText: 'Choose a viewing time',
    );

    if (selected == null || !mounted) return;
    if (_selectedDate != null) {
      final dateTime = _combine(_selectedDate!, selected);
      if (!dateTime.isAfter(DateTime.now())) {
        _setError('Please choose a time in the future.');
        return;
      }
    }

    setState(() {
      _selectedTime = selected;
      _submissionError = null;
    });
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime _combinedDateTime() => _combine(_selectedDate!, _selectedTime!);

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_hasPropertyReference) {
      _setError(
        'A real property reference is required before a viewing can be booked.',
      );
      return;
    }

    final date = _selectedDate;
    final time = _selectedTime;
    if (date == null || time == null) {
      _setError('Choose a date and time before booking.');
      return;
    }

    final requestedDateTime = _combine(date, time);
    if (!requestedDateTime.isAfter(DateTime.now())) {
      _setError('Please choose a viewing time in the future.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });

    try {
      final message = _messageController.text.trim();
      final createdViewing = await _viewingApiService.createViewing(
        propertyId: widget.propertyId,
        requestedDateTime: requestedDateTime,
        tenantMessage: message.isEmpty ? null : message,
      );

      if (!mounted) return;
      setState(() {
        _selectedDate = null;
        _selectedTime = null;
        _messageController.clear();
      });
      AppSnackbars.show(
        context,
        message:
            'Viewing request created. Status: ${_statusLabel(createdViewing.status)}.',
        tone: SnackTone.success,
      );
    } on ViewingApiException catch (error) {
      if (mounted) _setError(error.message);
    } catch (_) {
      if (mounted) {
        _setError('Unable to book the viewing right now. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _setError(String message) {
    setState(() => _submissionError = message);
    AppSnackbars.show(context, message: message, tone: SnackTone.error);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final dateLabel = _selectedDate == null
        ? 'Select a date'
        : localizations.formatMediumDate(_selectedDate!);
    final timeLabel = _selectedTime == null
        ? 'Select a time'
        : localizations.formatTimeOfDay(_selectedTime!);

    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: const Text('Book a Viewing'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: AuthenticatedPage(
        maxWidth: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              eyebrow: 'Viewing request',
              title: 'Choose a time that works for you',
              subtitle:
                  'The property owner will review the request and respond.',
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Selected property'),
            const SizedBox(height: AppSpacing.md),
            _PropertySummary(
              propertyId: widget.propertyId,
              propertyTitle: widget.propertyTitle,
              isAvailable: _hasPropertyReference,
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(title: 'Date and time'),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                children: [
                  _SelectionTile(
                    key: const ValueKey('viewing-date-selector'),
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: dateLabel,
                    isSelected: _selectedDate != null,
                    onTap: _isSubmitting ? null : _pickDate,
                  ),
                  const Divider(height: AppSpacing.lg),
                  _SelectionTile(
                    key: const ValueKey('viewing-time-selector'),
                    icon: Icons.schedule_outlined,
                    label: 'Time',
                    value: timeLabel,
                    isSelected: _selectedTime != null,
                    onTap: _isSubmitting ? null : _pickTime,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Message',
              subtitle: 'Optional note for the property owner.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('viewing-message'),
              controller: _messageController,
              enabled: !_isSubmitting,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Add anything helpful about your visit.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            const SectionHeader(title: 'Booking summary'),
            const SizedBox(height: AppSpacing.md),
            _BookingSummary(
              propertyId: widget.propertyId,
              date: dateLabel,
              time: timeLabel,
              message: _messageController.text.trim(),
            ),
            if (_submissionError case final error?) ...[
              const SizedBox(height: AppSpacing.base),
              _SubmissionError(message: error),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (_isSubmitting) ...[
              const LinearProgressIndicator(
                key: ValueKey('viewing-submitting'),
                color: AppPalette.olive,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Confirming your viewing with RentFlow...',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            FilledButton.icon(
              key: const ValueKey('confirm-viewing'),
              onPressed: _isSubmitting || !_hasPropertyReference
                  ? null
                  : _submit,
              icon: _isSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppPalette.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isSubmitting ? 'Confirming...' : 'Confirm Viewing'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertySummary extends StatelessWidget {
  const _PropertySummary({
    required this.propertyId,
    required this.isAvailable,
    this.propertyTitle,
  });

  final String propertyId;
  final String? propertyTitle;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) => AppCard(
    color: isAvailable ? AppPalette.sage : AppPalette.white,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: AppPalette.darkOlive,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.home_work_outlined, color: AppPalette.white),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                propertyTitle == null ? 'Property reference' : 'Selected home',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppPalette.muted),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                isAvailable ? (propertyTitle ?? propertyId) : 'Unavailable',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isAvailable
                    ? propertyTitle == null
                          ? 'Property details are not available in the mobile integration. This reference will be sent with your request.'
                          : 'This home will be included with your viewing request.'
                    : 'Property selection is not integrated. A viewing cannot be booked without a real property reference.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!isAvailable) ...[
                const SizedBox(height: AppSpacing.sm),
                const StatusChip(
                  label: 'Integration pending',
                  tone: StatusTone.warning,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadii.medium),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isSelected ? AppPalette.sage : AppPalette.softCream,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Icon(icon, color: AppPalette.darkOlive),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isSelected
                        ? AppPalette.primaryText
                        : AppPalette.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppPalette.olive),
        ],
      ),
    ),
  );
}

class _BookingSummary extends StatelessWidget {
  const _BookingSummary({
    required this.propertyId,
    required this.date,
    required this.time,
    required this.message,
  });

  final String propertyId;
  final String date;
  final String time;
  final String message;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      children: [
        _SummaryRow(
          icon: Icons.home_work_outlined,
          label: 'Property',
          value: propertyId.trim().isEmpty ? 'Unavailable' : propertyId,
        ),
        const Divider(height: AppSpacing.lg),
        _SummaryRow(
          icon: Icons.calendar_today_outlined,
          label: 'Date',
          value: date,
        ),
        const Divider(height: AppSpacing.lg),
        _SummaryRow(icon: Icons.schedule_outlined, label: 'Time', value: time),
        const Divider(height: AppSpacing.lg),
        _SummaryRow(
          icon: Icons.chat_bubble_outline,
          label: 'Message',
          value: message.isEmpty ? 'No message added.' : message,
        ),
      ],
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
      Icon(icon, size: 19, color: AppPalette.olive),
      const SizedBox(width: AppSpacing.md),
      SizedBox(
        width: 64,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppPalette.muted),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppPalette.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _SubmissionError extends StatelessWidget {
  const _SubmissionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('book-viewing-error'),
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

String _statusLabel(ViewingStatus status) => switch (status) {
  ViewingStatus.pending => 'Pending',
  ViewingStatus.approved => 'Approved',
  ViewingStatus.rejected => 'Rejected',
  ViewingStatus.cancelled => 'Cancelled',
  ViewingStatus.completed => 'Completed',
};
