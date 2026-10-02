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
        _loading ||
        !(_availability?.slots.contains(slot) ?? false)) {
      return;
    }
    if (_messageController.text.characters.length > 500) {
      setState(
        () => _submissionError = 'The note must not exceed 500 characters.',
      );
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
        tenantMessage: message.isEmpty ? null : message,
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
      appBar: AppBar(
        title: const Text(
          'REQUEST A VIEWING',
          style: TextStyle(fontSize: 13, letterSpacing: 1.2),
        ),
      ),
      body: AuthenticatedPage(
        maxWidth: 580,
        child: _sent
            ? _success()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose a time',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  _propertyCard(),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Choose a date'),
                  const SizedBox(height: 8),
                  AppCard(
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
                  const SectionHeader(title: 'Choose a time'),
                  const SizedBox(height: 8),
                  _slotPicker(),
                  const SizedBox(height: 24),
                  const SectionHeader(
                    title: 'A note for the landlord',
                    subtitle: 'Optional',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('viewing-message'),
                    controller: _messageController,
                    enabled: !_submitting,
                    maxLines: 3,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: "Anything you'd like them to know?",
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Requested viewing',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(_title),
                        Text(
                          '$dateLabel · ${_slot?.displayTime ?? 'Choose a time'}',
                        ),
                        if (_availability != null)
                          Text(
                            'Times in ${_availability!.timeZoneId}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          _messageController.text.trim().isEmpty
                              ? 'No message added'
                              : _messageController.text.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
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
                            _loading ||
                            _submitting
                        ? null
                        : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.darkOlive,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(
                      _submitting ? 'Sending request...' : 'Confirm Viewing',
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
              propertyApiService: _propertyValid ? widget.propertyApiService : null,
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
                    'Rs. ${property.monthlyRent.toStringAsFixed(0)} / month',
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
    if (_date == null) return const Text('Choose a date to see viewing times');
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
          Text(_slotError!),
          TextButton(
            onPressed: _submitting ? null : _loadSlots,
            child: const Text('Retry viewing times'),
          ),
        ],
      );
    }
    final availability = _availability;
    if (availability == null || availability.slots.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No viewing times are available on this date.'),
          if (availability?.state == 'unconfigured')
            const Text(
              'The landlord has not configured viewing availability yet.',
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availability.slots
              .map(
                (slot) => ChoiceChip(
                  key: ValueKey('viewing-slot-${slot.localTime}'),
                  label: Text(slot.displayTime),
                  selected: identical(_slot, slot),
                  selectedColor: AppPalette.darkOlive,
                  labelStyle: TextStyle(
                    color: identical(_slot, slot)
                        ? AppPalette.white
                        : AppPalette.darkOlive,
                  ),
                  onSelected: _submitting
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
