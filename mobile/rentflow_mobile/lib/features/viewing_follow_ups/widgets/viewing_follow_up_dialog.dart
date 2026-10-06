import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../properties/services/property_api_service.dart';
import '../../properties/widgets/property_photo.dart';
import '../../rental_applications/services/application_destination.dart';
import '../../rental_applications/services/rental_application_api_service.dart';
import '../../viewing_reviews/services/viewing_review_api_service.dart';
import '../../viewing_reviews/widgets/viewing_review_editor.dart';
import '../models/viewing_follow_up.dart';
import '../services/viewing_follow_up_api_service.dart';

/// Two steps share one dialog route, so their surfaces never overlap.
/// Only the application step responds to the existing server claim.
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
  final _reviewEditor = GlobalKey<ViewingReviewEditorState>();
  bool _applicationStep = false,
      _reviewSaved = false,
      _saving = false,
      _alreadyAnswered = false;
  FollowUpDecision? _savedDecision, _pendingDecision;
  String? _error;

  void _reviewChanged() {
    if (mounted) setState(() => _error = null);
  }

  void _skipReview() {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _applicationStep = true;
      _error = null;
    });
  }

  Future<void> _submitReview() async {
    final editor = _reviewEditor.currentState;
    if (_saving || editor == null || !editor.canSubmit) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await editor.saveIfEntered(requireReview: true);
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _applicationStep = true;
        _reviewSaved = true;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ViewingReviewApiException
              ? error.message
              : 'Could not save your review. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _respond(FollowUpDecision decision) async {
    if (_saving ||
        _alreadyAnswered ||
        !_applicationStep ||
        (_savedDecision != null && _savedDecision != decision) ||
        (_pendingDecision != null && _pendingDecision != decision)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_savedDecision == null) {
        setState(() => _pendingDecision = decision);
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

  Widget get _errorMessage => Semantics(
    liveRegion: true,
    child: Text(
      _error!,
      key: const Key('follow-up-error'),
      style: const TextStyle(fontSize: 13, color: AppPalette.danger),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_applicationStep && !_saving,
    child: _applicationStep ? _applicationDialog() : _reviewDialog(),
  );

  Widget _reviewDialog() => _FollowUpSurface(
    key: const Key('follow-up-review-step'),
    title: 'How did your viewing go?',
    onClose: _saving ? null : () => Navigator.of(context).pop(),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 160,
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
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppPalette.primaryText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            widget.followUp.address,
            widget.followUp.city,
          ].where((v) => v.trim().isNotEmpty).join(', '),
          style: const TextStyle(fontSize: 14, color: AppPalette.primaryText),
        ),
        const SizedBox(height: 16),
        ViewingReviewEditor(
          key: _reviewEditor,
          viewingId: widget.followUp.viewingId,
          api: ViewingReviewApiService(widget.apiService.apiClient),
          enabled: !_saving,
          prefillExisting: true,
          onChanged: _reviewChanged,
        ),
        if (_error != null) ...[const SizedBox(height: 12), _errorMessage],
      ],
    ),
    actions: _StepActions(
      secondary: OutlinedButton(
        key: const Key('follow-up-skip-review'),
        onPressed: _saving ? null : _skipReview,
        child: const Text('Skip review'),
      ),
      primary: FilledButton(
        key: const Key('follow-up-submit-review'),
        onPressed: _saving || !(_reviewEditor.currentState?.canSubmit ?? false)
            ? null
            : _submitReview,
        child: Text(
          _saving
              ? 'Saving review...'
              : _reviewEditor.currentState?.primaryActionLabel ??
                    'Submit review',
        ),
      ),
    ),
  );

  Widget _applicationDialog() => _FollowUpSurface(
    key: const Key('follow-up-application-step'),
    title: 'Would you like to apply?',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_reviewSaved) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              'Review saved',
              style: TextStyle(fontSize: 13, color: AppPalette.darkOlive),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          widget.followUp.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppPalette.primaryText,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "You've completed the viewing. Would you like to continue with a rental application for this property?",
          style: TextStyle(fontSize: 14, color: AppPalette.primaryText),
        ),
        const SizedBox(height: 8),
        const Text(
          'You can still apply later from My Applications.',
          style: TextStyle(fontSize: 13, color: AppPalette.primaryText),
        ),
        if (_error != null) ...[const SizedBox(height: 12), _errorMessage],
      ],
    ),
    actions: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_alreadyAnswered ||
            (_savedDecision == FollowUpDecision.applyNow && _error != null))
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        if (!_alreadyAnswered)
          _StepActions(
            secondary: _savedDecision == null
                ? OutlinedButton(
                    key: const Key('follow-up-not-now'),
                    onPressed:
                        _saving || _pendingDecision == FollowUpDecision.applyNow
                        ? null
                        : () => _respond(FollowUpDecision.notNow),
                    child: Text(
                      _saving && _pendingDecision == FollowUpDecision.notNow
                          ? 'Saving...'
                          : 'Not now',
                    ),
                  )
                : null,
            primary: FilledButton(
              key: const Key('follow-up-apply-now'),
              onPressed: _saving || _pendingDecision == FollowUpDecision.notNow
                  ? null
                  : () => _respond(FollowUpDecision.applyNow),
              child: Text(
                _saving && _pendingDecision == FollowUpDecision.applyNow
                    ? 'Saving...'
                    : _savedDecision == null
                    ? 'Apply now'
                    : 'Try again',
              ),
            ),
          ),
      ],
    ),
  );
}

class _FollowUpSurface extends StatelessWidget {
  const _FollowUpSurface({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.onClose,
  });
  final String title;
  final Widget content, actions;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppPalette.warmCream,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final body = Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Semantics(
                        namesRoute: true,
                        header: true,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.darkOlive,
                          ),
                        ),
                      ),
                    ),
                    if (onClose != null)
                      IconButton(
                        tooltip: 'Dismiss review',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                content,
              ],
            ),
          );
          final footer = Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: actions,
          );
          // Keep actions visible when there is room; allow the whole surface to
          // scroll in short keyboard-constrained viewports and at large text sizes.
          if (constraints.maxHeight < 440) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [body, footer],
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: SingleChildScrollView(child: body)),
              footer,
            ],
          );
        },
      ),
    ),
  );
}

class _StepActions extends StatelessWidget {
  const _StepActions({required this.primary, this.secondary});
  final Widget primary;
  final Widget? secondary;
  @override
  Widget build(BuildContext context) {
    if (secondary == null) return primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(15) >= 24 ||
            constraints.maxWidth < 240) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [secondary!, const SizedBox(height: 8), primary],
          );
        }
        return Row(
          children: [
            Expanded(child: secondary!),
            const SizedBox(width: 10),
            Expanded(child: primary),
          ],
        );
      },
    );
  }
}
