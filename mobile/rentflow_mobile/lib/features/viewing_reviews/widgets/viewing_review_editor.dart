import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../services/viewing_review_api_service.dart';

class ViewingReviewEditor extends StatefulWidget {
  const ViewingReviewEditor({
    super.key,
    required this.viewingId,
    required this.api,
    this.enabled = true,
  });
  final String viewingId;
  final ViewingReviewApiService api;
  final bool enabled;
  @override
  State<ViewingReviewEditor> createState() => ViewingReviewEditorState();
}

class ViewingReviewEditorState extends State<ViewingReviewEditor> {
  final _comment = TextEditingController();
  int? _property, _landlord;
  ViewingReview? _existing;
  bool _loading = true, _editing = true, _changed = false;
  String? _error;
  late Future<void> _loadFuture;
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

  Future<void> _load() async {
    try {
      final review = await widget.api.getOwn(widget.viewingId);
      if (!mounted) return;
      setState(() {
        _existing = review;
        _property = review?.propertyRating;
        _landlord = review?.landlordRating;
        _comment.text = review?.comment ?? '';
        _editing = review == null;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load your viewing review.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> saveIfEntered({bool requireReview = false}) async {
    await _loadFuture;
    if (!mounted) {
      throw const ViewingReviewApiException('Please reopen the review.');
    }
    if (!_changed && _existing != null) return;
    final entered =
        _property != null || _landlord != null || _comment.text.isNotEmpty;
    if (!entered && !requireReview) return;
    if (_property == null || _landlord == null) {
      throw const ViewingReviewApiException(
        'Choose both ratings to submit a review, or clear the review to continue without one.',
      );
    }
    final saved = await widget.api.save(
      widget.viewingId,
      _property!,
      _landlord!,
      _comment.text,
    );
    if (mounted) {
      setState(() {
        _existing = saved;
        _changed = false;
      });
    }
  }

  Widget _stars(
    String label,
    int? value,
    ValueChanged<int> select,
    String key,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 14)),
      Wrap(
        children: List.generate(
          5,
          (i) => IconButton(
            key: Key('$key-${i + 1}'),
            tooltip: '$label: ${i + 1} of 5',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: widget.enabled
                ? () {
                    setState(() {
                      select(i + 1);
                      _changed = true;
                    });
                  }
                : null,
            icon: Icon(
              i < (value ?? 0) ? Icons.star : Icons.star_border,
              color: AppPalette.darkOlive,
            ),
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Loading your viewing review…',
          style: TextStyle(fontSize: 13),
        ),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          Text(_error!, style: const TextStyle(fontSize: 13)),
          TextButton(
            onPressed: widget.enabled
                ? () {
                    setState(() => _loading = true);
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
            'Property ${_property!}/5 · Landlord ${_landlord!}/5',
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
        const Text(
          'Rate your viewing experience',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const Text(
          'Optional. Choose both ratings if you share a review.',
          style: TextStyle(fontSize: 12),
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
        TextField(
          controller: _comment,
          enabled: widget.enabled,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Tell us about your viewing (optional)',
          ),
          onChanged: (_) => _changed = true,
        ),
        if (_existing == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.enabled
                  ? () => setState(() {
                      _property = null;
                      _landlord = null;
                      _comment.clear();
                      _changed = false;
                    })
                  : null,
              child: const Text('Clear review'),
            ),
          ),
      ],
    );
  }
}
