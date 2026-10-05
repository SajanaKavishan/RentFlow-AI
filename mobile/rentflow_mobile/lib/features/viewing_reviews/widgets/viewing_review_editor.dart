import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../services/viewing_review_api_service.dart';

class ViewingReviewEditor extends StatefulWidget {
  const ViewingReviewEditor({
    super.key,
    required this.viewingId,
    required this.api,
    this.enabled = true,
    this.prefillExisting = false,
    this.onChanged,
  });
  final String viewingId;
  final ViewingReviewApiService api;
  final bool enabled;
  final bool prefillExisting;
  final VoidCallback? onChanged;
  @override
  State<ViewingReviewEditor> createState() => ViewingReviewEditorState();
}

class ViewingReviewEditorState extends State<ViewingReviewEditor> {
  final _comment = TextEditingController();
  int? _property, _landlord;
  ViewingReview? _existing;
  bool _loading = true, _editing = true;
  String? _error;
  late Future<void> _loadFuture;

  bool get hasExistingReview => _existing != null;
  bool get hasInput =>
      _property != null || _landlord != null || _comment.text.isNotEmpty;
  bool get hasChanges => _existing == null
      ? hasInput
      : _property != _existing!.propertyRating ||
            _landlord != _existing!.landlordRating ||
            _comment.text.trim() != (_existing!.comment ?? '').trim();
  bool get canSubmit =>
      !_loading &&
      _error == null &&
      _property != null &&
      _property! >= 1 &&
      _property! <= 5 &&
      _landlord != null &&
      _landlord! >= 1 &&
      _landlord! <= 5 &&
      _comment.text.length <= 500;
  String get primaryActionLabel => _existing == null
      ? 'Submit review'
      : hasChanges
      ? 'Update review'
      : 'Continue';

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _notify() => widget.onChanged?.call();
  Future<void> _load() async {
    try {
      final review = await widget.api.getOwn(widget.viewingId);
      if (!mounted) return;
      setState(() {
        _existing = review;
        _property = review?.propertyRating;
        _landlord = review?.landlordRating;
        _comment.text = review?.comment ?? '';
        _editing = widget.prefillExisting || review == null;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load your viewing review.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _notify();
      }
    }
  }

  Future<void> saveIfEntered({bool requireReview = false}) async {
    await _loadFuture;
    if (!mounted) {
      throw const ViewingReviewApiException('Please reopen the review.');
    }
    if (_error != null) {
      throw const ViewingReviewApiException(
        'Could not load your viewing review. Please retry or skip review.',
      );
    }
    if (!hasChanges && _existing != null) return;
    if (!hasInput && !requireReview) return;
    if (!canSubmit) {
      throw const ViewingReviewApiException(
        'Choose both ratings from 1 to 5 and use at most 500 comment characters.',
      );
    }
    final saved = await widget.api.save(
      widget.viewingId,
      _property!,
      _landlord!,
      _comment.text.trim(),
    );
    if (mounted) {
      setState(() {
        _existing = saved;
        _comment.text = saved.comment ?? '';
      });
      _notify();
    }
  }

  Widget _stars(
    String label,
    int? value,
    ValueChanged<int> select,
    String key,
  ) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: label,
    value: value == null ? 'Not rated' : 'Selected rating: $value of 5',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppPalette.primaryText),
        ),
        Wrap(
          children: List.generate(
            5,
            (i) => Semantics(
              container: true,
              button: true,
              enabled: widget.enabled,
              label: '$label: ${i + 1} of 5',
              selected: value == i + 1,
              onTap: widget.enabled ? () => _selectRating(select, i + 1) : null,
              child: ExcludeSemantics(
                child: IconButton(
                  key: Key('$key-${i + 1}'),
                  tooltip: '$label: ${i + 1} of 5',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: widget.enabled
                      ? () => _selectRating(select, i + 1)
                      : null,
                  icon: Icon(
                    i < (value ?? 0) ? Icons.star : Icons.star_border,
                    color: AppPalette.darkOlive,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void _selectRating(ValueChanged<int> select, int value) {
    if (!widget.enabled) return;
    setState(() => select(value));
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Semantics(
        liveRegion: true,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Loading your viewing review...',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: AppPalette.danger),
            ),
          ),
          TextButton(
            onPressed: widget.enabled
                ? () {
                    setState(() => _loading = true);
                    _notify();
                    _loadFuture = _load();
                  }
                : null,
            child: const Text('Retry review'),
          ),
        ],
      );
    }
    if (!_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your viewing review is already saved.',
            style: TextStyle(fontSize: 14),
          ),
          Text(
            'Property ${_property!}/5 ? Landlord ${_landlord!}/5',
            style: const TextStyle(fontSize: 13),
          ),
          if (_comment.text.isNotEmpty)
            Text(_comment.text, style: const TextStyle(fontSize: 14)),
          TextButton(
            onPressed: widget.enabled
                ? () => setState(() => _editing = true)
                : null,
            child: const Text('Edit review'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_existing != null) ...[
          const Text(
            'Your review',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppPalette.darkOlive,
            ),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          'Rate your viewing experience',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppPalette.primaryText,
          ),
        ),
        const Text(
          'Optional. Choose both ratings if you share a review.',
          style: TextStyle(fontSize: 13, color: AppPalette.primaryText),
        ),
        const SizedBox(height: 8),
        _stars(
          'Property during the viewing',
          _property,
          (v) => _property = v,
          'property-rating',
        ),
        _stars(
          'Experience with the landlord',
          _landlord,
          (v) => _landlord = v,
          'landlord-rating',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _comment,
          enabled: widget.enabled,
          maxLength: 500,
          minLines: 3,
          maxLines: 4,
          style: const TextStyle(fontSize: 14, color: AppPalette.primaryText),
          decoration: InputDecoration(
            label: const Text('Tell us about your viewing (optional)'),
            filled: true,
            fillColor: AppPalette.white,
            errorText: _comment.text.length > 500
                ? 'Use at most 500 comment characters.'
                : null,
          ),
          onChanged: (_) {
            setState(() {});
            _notify();
          },
        ),
        if (_existing == null && hasInput)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.enabled
                  ? () {
                      setState(() {
                        _property = null;
                        _landlord = null;
                        _comment.clear();
                      });
                      _notify();
                    }
                  : null,
              child: const Text('Clear selections'),
            ),
          ),
      ],
    );
  }
}
