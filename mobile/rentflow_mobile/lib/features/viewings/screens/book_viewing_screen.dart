import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../properties/models/property.dart';
import '../../properties/services/property_api_service.dart';
import '../../properties/widgets/property_photo.dart';
import '../models/viewing.dart';
import '../models/viewing_slots.dart';
import '../services/viewing_api_service.dart';
import 'my_viewings_screen.dart';

class BookViewingScreen extends StatefulWidget {
  const BookViewingScreen({
    super.key,
    required this.propertyId,
    this.propertyTitle,
    this.property,
    this.propertyApiService,
    this.viewingApiService,
  });
  final String propertyId;
  final String? propertyTitle;
  final Property? property;
  final PropertyApiService? propertyApiService;
  final ViewingApiService? viewingApiService;
  @override
  State<BookViewingScreen> createState() => _BookViewingScreenState();
}

class _BookViewingScreenState extends State<BookViewingScreen> {
  final _messageController = TextEditingController();
  ApiClient? _ownedApiClient;
  late final ViewingApiService _api;
  DateTime? _date;
  ViewingSlots? _availability;
  ViewingSlot? _slot;
  String? _slotError;
  String? _submissionError;
  bool _loading = false;
  bool _submitting = false;
  bool _sent = false;
  int _loadVersion = 0;
  bool get _noteValid =>
      _messageController.text.trim().isNotEmpty &&
      // Match the backend's existing UTF-16 string-length contract.
      _messageController.text.trim().length <= 500;

  bool get _propertyValid =>
      widget.propertyId.trim().isNotEmpty &&
      widget.property?.id == widget.propertyId &&
      widget.property!.isAvailable;
  String get _title =>
      widget.property?.title ??
      widget.propertyTitle ??
      'Property details unavailable';
  String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    if (widget.viewingApiService case final service?) {
      _api = service;
    } else {
      _ownedApiClient = ApiClient();
      _api = ViewingApiService(_ownedApiClient!);
    }
    _messageController.addListener(_messageChanged);
  }

  @override
  void dispose() {
    _loadVersion++;
    _messageController
      ..removeListener(_messageChanged)
      ..dispose();
    _ownedApiClient?.close();
    super.dispose();
  }

  void _messageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _date != null && !_date!.isBefore(today) ? _date! : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Choose a viewing date',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _date = selected;
      _slot = null;
      _submissionError = null;
    });
    await _loadSlots();
  }

  Future<void> _loadSlots() async {
    final date = _date;
    if (date == null) return;
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _slot = null;
      _availability = null;
      _slotError = null;
    });
    try {
      final result = await _api.getViewingSlots(
        propertyId: widget.propertyId,
        date: _dateString(date),
      );
      if (!mounted || version != _loadVersion) return;
      setState(() => _availability = result);
    } on ViewingApiException catch (error) {
      if (mounted && version == _loadVersion) {
        setState(() => _slotError = error.message);
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(
          () => _slotError =
              'Viewing times could not be loaded. Please try again.',
        );
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final slot = _slot;
    if (_submitting ||
        !_propertyValid ||
        _date == null ||
        slot == null ||
        !slot.isAvailable ||
        !_noteValid ||
        _loading ||
        !(_availability?.slots.contains(slot) ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submissionError = null;
    });
    try {
      final message = _messageController.text.trim();
      final result = await _api.createViewing(
        propertyId: widget.propertyId,
        requestedDateTime: slot.requestedDateTime,
        requestedDateTimeIso: slot.requestedDateTimeIso,
        tenantMessage: message,
      );
      if (!mounted) return;
      if (result.status != ViewingStatus.pending ||
          result.propertyId != widget.propertyId ||
          result.requestedDateTime.toUtc() != slot.requestedDateTime.toUtc()) {
        throw const ViewingApiException(
          'The viewing service returned an unexpected request response.',
        );
      }
      setState(() => _sent = true);
    } on ViewingApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        setState(
          () => _submissionError =
              'That time is no longer available. Please choose another slot.',
        );
        await _loadSlots();
      } else {
        setState(() => _submissionError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _submissionError =
              'Unable to send the request. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _date == null
        ? 'Select a date'
        : MaterialLocalizations.of(context).formatMediumDate(_date!);
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(leading: const BackButton()),
      body: AuthenticatedPage(
        maxWidth: 580,
        child: _sent
            ? _success()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Request a viewing',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select your preferred date and time',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  _propertyCard(),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Choose a date'),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: ListTile(
                      key: const ValueKey('viewing-date-selector'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: Text(dateLabel),
                      trailing: const Icon(Icons.expand_more),
                      onTap: _submitting || !_propertyValid ? null : _pickDate,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader(title: 'Available times'),
                  const SizedBox(height: 8),
                  _slotPicker(),
                  const SizedBox(height: 24),
                  const SectionHeader(
                    title: 'A note for the landlord *',
                    subtitle: 'Required',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('viewing-message'),
                    controller: _messageController,
                    enabled: !_submitting,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.primaryText,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Add anything helpful about your visit.',
                      counterText:
                          '${_messageController.text.trim().length}/500',
                      errorText:
                          _messageController.text.isNotEmpty && !_noteValid
                          ? _messageController.text.trim().isEmpty
                                ? 'Add a note for the landlord.'
                                : 'The note must not exceed 500 characters.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _summary(dateLabel),
                  if (_submissionError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _submissionError!,
                        key: const ValueKey('book-viewing-error'),
                        style: const TextStyle(color: AppPalette.danger),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const ValueKey('confirm-viewing'),
                    onPressed:
                        !_propertyValid ||
                            _date == null ||
                            _slot == null ||
                            !_slot!.isAvailable ||
                            !_noteValid ||
                            _loading ||
                            _submitting
                        ? null
                        : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.darkOlive,
                      minimumSize: const Size.fromHeight(54),
                    ),
                    child: Text(
                      _submitting
                          ? 'Sending request...'
                          : 'Send viewing request',
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _propertyCard() {
    final property = widget.property;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 76,
              height: 86,
              child: PropertyPhoto(
                propertyId: widget.propertyId,
                propertyApiService: _propertyValid
                    ? widget.propertyApiService
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: Theme.of(context).textTheme.titleMedium),
                if (property != null) ...[
                  const SizedBox(height: 4),
                  Text(property.city),
                  const SizedBox(height: 4),
                  Text(
                    'Rs. ${_rent(property.monthlyRent)} / month',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
                if (!_propertyValid)
                  const Text(
                    'This property is unavailable for viewing requests.',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotPicker() {
    if (_date == null) return const Text('Choose a date to see viewing times.');
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(
          key: ValueKey('viewing-slots-loading'),
          color: AppPalette.olive,
        ),
      );
    }
    if (_slotError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Viewing times could not be loaded.'),
          TextButton(
            onPressed: _submitting ? null : _loadSlots,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    final availability = _availability;
    if (availability == null || availability.slots.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            availability?.state == 'unconfigured'
                ? 'Viewing times have not been configured for this property yet.'
                : 'No viewing times are available on this date.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Times in ${availability.timeZoneId}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (!availability.slots.any((slot) => slot.isAvailable)) ...[
          const Text('No viewing times are available on this date.'),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availability.slots
              .map(
                (slot) => ChoiceChip(
                  key: ValueKey('viewing-slot-${slot.localTime}'),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        slot.displayTime,
                        style: TextStyle(
                          decoration: slot.isAvailable
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                      if (!slot.isAvailable)
                        Text(
                          slot.unavailableReason == 'ApprovedViewing'
                              ? 'Booked'
                              : 'Unavailable',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                  selected: identical(_slot, slot),
                  selectedColor: AppPalette.darkOlive,
                  labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: identical(_slot, slot)
                        ? AppPalette.white
                        : slot.isAvailable
                        ? AppPalette.darkOlive
                        : AppPalette.secondaryText,
                  ),
                  tooltip: slot.isAvailable ? null : 'Unavailable viewing time',
                  onSelected: _submitting || !slot.isAvailable
                      ? null
                      : (_) => setState(() {
                          _slot = slot;
                          _submissionError = null;
                        }),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  String _rent(double rent) => rent
      .toStringAsFixed(0)
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (match) => '${match[1]},',
      );

  Widget _summary(String dateLabel) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Request summary', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(_title, style: Theme.of(context).textTheme.titleMedium),
        if (widget.property != null) Text(widget.property!.city),
        const SizedBox(height: 12),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _summaryValue('Date', dateLabel),
            _summaryValue('Time', _slot?.displayTime ?? 'Select a time'),
            _summaryValue(
              'Duration',
              _availability == null
                  ? 'Choose a date'
                  : '${_availability!.slotDurationMinutes} minutes',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _summaryValue(
          'Note',
          _messageController.text.trim().isEmpty
              ? 'Add a note above'
              : _messageController.text.trim(),
        ),
        if (_availability != null) ...[
          const SizedBox(height: 8),
          Text(
            'Times in ${_availability!.timeZoneId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
  );

  Widget _summaryValue(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppPalette.primaryText),
      ),
    ],
  );

  Widget _success() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 40),
      const Icon(
        Icons.check_circle_outline,
        size: 64,
        color: AppPalette.darkOlive,
      ),
      const SizedBox(height: 20),
      Text(
        'Request sent',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text(
        "We'll let you know when the landlord responds.\nNothing is confirmed until they approve it.",
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 28),
      FilledButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MyViewingsScreen(viewingApiService: _api),
          ),
        ),
        child: const Text('View my requests'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back to property'),
      ),
    ],
  );
}
