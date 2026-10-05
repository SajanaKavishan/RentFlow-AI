import 'package:flutter/material.dart';
import '../../../shared/follow_up/follow_up_activity.dart';
import '../services/viewing_review_api_service.dart';
import 'viewing_review_editor.dart';

class OwnViewingReviewCard extends StatefulWidget {
  const OwnViewingReviewCard({
    super.key,
    required this.viewingId,
    required this.api,
  });
  final String viewingId;
  final ViewingReviewApiService api;
  @override
  State<OwnViewingReviewCard> createState() => _OwnViewingReviewCardState();
}

class _OwnViewingReviewCardState extends State<OwnViewingReviewCard> {
  late Future<ViewingReview?> _review;
  @override
  void initState() {
    super.initState();
    _review = widget.api.getOwn(widget.viewingId);
  }

  Future<void> _edit() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FollowUpPause(
        child: _ReviewSheet(viewingId: widget.viewingId, api: widget.api),
      ),
    );
    if (mounted) _reload();
  }

  void _reload() {
    final review = widget.api.getOwn(widget.viewingId);
    setState(() {
      _review = review;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ViewingReview?>(
    future: _review,
    builder: (_, snapshot) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              snapshot.data == null
                  ? 'Share your viewing experience'
                  : 'Your viewing review',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (snapshot.connectionState != ConnectionState.done)
              const Text('Loading review…')
            else if (snapshot.hasError) ...[
              const Text('Could not load your viewing review.'),
              TextButton(onPressed: _reload, child: const Text('Retry review')),
            ] else ...[
              if (snapshot.data case final review?) ...[
                Text(
                  'Property ${'★' * review.propertyRating}${'☆' * (5 - review.propertyRating)} (${review.propertyRating}/5)',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Landlord ${'★' * review.landlordRating}${'☆' * (5 - review.landlordRating)} (${review.landlordRating}/5)',
                  style: const TextStyle(fontSize: 14),
                ),
                if (review.comment != null) Text(review.comment!),
              ] else
                const Text(
                  'Help other renters understand what the viewing was like.',
                ),
              TextButton(
                onPressed: _edit,
                child: Text(
                  snapshot.data == null ? 'Leave a review' : 'Edit review',
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.viewingId, required this.api});
  final String viewingId;
  final ViewingReviewApiService api;
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _editor = GlobalKey<ViewingReviewEditorState>();
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _editor.currentState!.saveIfEntered(requireReview: true);
      if (mounted) Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ViewingReviewEditor(
              key: _editor,
              viewingId: widget.viewingId,
              api: widget.api,
              enabled: !_saving,
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(fontSize: 13)),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save review'),
            ),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}
