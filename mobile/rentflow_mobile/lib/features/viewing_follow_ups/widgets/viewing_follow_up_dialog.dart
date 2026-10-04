import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../properties/services/property_api_service.dart';
import '../../properties/widgets/property_photo.dart';
import '../../rental_applications/services/application_destination.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../models/viewing_follow_up.dart';
import '../services/viewing_follow_up_api_service.dart';

/// Back/barrier dismissal is disabled: explicit actions give persisted semantics.
class ViewingFollowUpDialog extends StatefulWidget {
  const ViewingFollowUpDialog({
    super.key,
    required this.followUp,
    required this.apiService,
    required this.applicationApiService,
    required this.propertyApiService,
  });
  final ViewingFollowUp followUp;
  final ViewingFollowUpApiService apiService;
  final RentalApplicationApiService applicationApiService;
  final PropertyApiService propertyApiService;
  @override
  State<ViewingFollowUpDialog> createState() => _ViewingFollowUpDialogState();
}

class _ViewingFollowUpDialogState extends State<ViewingFollowUpDialog> {
  bool _saving = false;
  bool _alreadyAnswered = false;
  FollowUpDecision? _savedDecision;
  FollowUpDecision? _pendingDecision;
  String? _error;
  Future<void> _respond(FollowUpDecision decision) async {
    if (_saving ||
        _alreadyAnswered ||
        (_savedDecision != null && _savedDecision != decision)) {
      return;
    }
    setState(() {
      _saving = true;
      _pendingDecision = decision;
      _error = null;
    });
    try {
      if (_savedDecision == null) {
        await widget.apiService.respond(widget.followUp.id, decision);
        _savedDecision = decision;
      }
      if (!mounted) return;
      if (decision == FollowUpDecision.notNow) {
        Navigator.of(context).pop();
        return;
      }
      try {
        final destination = await applicationDestination(
          propertyId: widget.followUp.propertyId,
          propertyTitle: widget.followUp.title,
          apiService: widget.applicationApiService,
        );
        if (mounted) Navigator.of(context).pop(destination);
      } on RentalApplicationApiException catch (error) {
        if (mounted) {
          setState(() => _error = '${error.message} Your choice was saved.');
        }
      }
    } on FollowUpApiException catch (error) {
      if (mounted) {
        setState(() {
          _alreadyAnswered = error.alreadyAnswered;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _savedDecision == null
              ? 'Could not save your choice. Please try again.'
              : 'Your choice was saved, but the application could not be opened. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      backgroundColor: AppPalette.warmCream,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'How did your viewing go?',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.darkOlive,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 130,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: PropertyPhoto(
                    propertyId: widget.followUp.propertyId,
                    propertyApiService: widget.propertyApiService,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.followUp.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  widget.followUp.address,
                  widget.followUp.city,
                ].where((v) => v.trim().isNotEmpty).join(', '),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Would you like to apply for this property?',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can still apply later from My Applications.',
                style: TextStyle(fontSize: 13, color: AppPalette.secondaryText),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('follow-up-error'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppPalette.danger,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_alreadyAnswered ||
                  (_savedDecision == FollowUpDecision.applyNow &&
                      _error != null))
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              if (!_alreadyAnswered)
                Row(
                  children: [
                    if (_savedDecision == null)
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('follow-up-not-now'),
                          onPressed:
                              _saving ||
                                  _pendingDecision == FollowUpDecision.applyNow
                              ? null
                              : () => _respond(FollowUpDecision.notNow),
                          style: OutlinedButton.styleFrom(
                            textStyle: const TextStyle(fontSize: 15),
                          ),
                          child: Text(
                            _saving &&
                                    _pendingDecision == FollowUpDecision.notNow
                                ? 'Saving...'
                                : 'Not now',
                          ),
                        ),
                      ),
                    if (_savedDecision == null) const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const Key('follow-up-apply-now'),
                        onPressed:
                            _saving ||
                                _pendingDecision == FollowUpDecision.notNow
                            ? null
                            : () => _respond(FollowUpDecision.applyNow),
                        style: FilledButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 15),
                        ),
                        child: Text(
                          _saving &&
                                  _pendingDecision == FollowUpDecision.applyNow
                              ? 'Saving...'
                              : _savedDecision == null
                              ? 'Apply now'
                              : 'Try again',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
