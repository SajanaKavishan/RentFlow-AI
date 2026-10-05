import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../models/viewing.dart';
import '../services/viewing_api_service.dart';

class LandlordCompletionDialog extends StatefulWidget {
  const LandlordCompletionDialog({
    super.key,
    required this.viewing,
    required this.service,
  });
  final Viewing viewing;
  final ViewingApiService service;
  @override
  State<LandlordCompletionDialog> createState() =>
      _LandlordCompletionDialogState();
}

class _LandlordCompletionDialogState extends State<LandlordCompletionDialog> {
  late Viewing _viewing = widget.viewing;
  bool _busy = false;
  String? _error;

  Future<void> _complete() async {
    if (_busy ||
        !_viewing.canMarkCompleted ||
        _viewing.status != ViewingStatus.approved) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final completed = await widget.service.completeViewing(id: _viewing.id);
      _validate(completed);
      if (mounted) Navigator.of(context).pop(true);
    } on ViewingApiException catch (error) {
      if (error.statusCode == 409) {
        try {
          final refreshed = await widget.service.getViewingById(_viewing.id);
          _validate(refreshed);
          if (mounted) setState(() => _viewing = refreshed);
        } catch (_) {
          // Fail closed until the next authoritative fetch.
          if (mounted) {
            setState(
              () => _error =
                  'The viewing changed. Close this reminder and refresh Viewing Requests.',
            );
          }
        }
      }
      if (mounted) setState(() => _error ??= error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to confirm attendance. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _validate(Viewing value) {
    if (value.id != widget.viewing.id ||
        value.propertyId != widget.viewing.propertyId ||
        value.tenantId != widget.viewing.tenantId) {
      throw const ViewingApiException(
        'The viewing service returned an invalid response.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = MaterialLocalizations.of(context);
    final date = _viewing.requestedLocalDate == null
        ? _viewing.requestedDateTime.toLocal()
        : DateTime.parse(_viewing.requestedLocalDate!);
    final time =
        _viewing.requestedDisplayTime ??
        labels.formatTimeOfDay(TimeOfDay.fromDateTime(date));
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('How did the viewing go?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _viewing.propertyTitle ?? 'Your viewing',
                style: AppTypography.cardTitle,
              ),
              const SizedBox(height: 8),
              Text(_viewing.tenant.displayName),
              Text(
                '${labels.formatMediumDate(date)}, $time${_viewing.timeZoneId == null ? '' : ' (${_viewing.timeZoneId})'}',
              ),
              const SizedBox(height: 20),
              const Text('Did the tenant attend?'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppPalette.danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed:
                _busy ||
                    _error != null ||
                    !_viewing.canMarkCompleted ||
                    _viewing.status != ViewingStatus.approved
                ? null
                : _complete,
            child: Text(_busy ? 'Confirming...' : 'Yes, mark completed'),
          ),
        ],
      ),
    );
  }
}
