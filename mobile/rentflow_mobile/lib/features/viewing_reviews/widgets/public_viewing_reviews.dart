import 'package:flutter/material.dart';
import 'viewing_rating_summary.dart';
import '../services/viewing_review_api_service.dart';

class PublicViewingReviews extends StatefulWidget {
  const PublicViewingReviews({
    super.key,
    required this.propertyId,
    required this.api,
    this.landlord = false,
    this.summary,
  });
  final String propertyId;
  final ViewingReviewApiService api;
  final bool landlord;
  final Future<Map<String, dynamic>>? summary;
  @override
  State<PublicViewingReviews> createState() => _PublicViewingReviewsState();
}

class _PublicViewingReviewsState extends State<PublicViewingReviews> {
  late Future<Map<String, dynamic>> _summary;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _summary =
        widget.summary ??
        widget.api.publicSummary(widget.propertyId, landlord: widget.landlord);
  }

  @override
  void didUpdateWidget(covariant PublicViewingReviews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId ||
        oldWidget.landlord != widget.landlord ||
        oldWidget.summary != widget.summary) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _summary,
    builder: (_, snapshot) {
      final data = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done ||
          snapshot.hasError ||
          data == null ||
          (data['reviewCount'] as int) == 0) {
        return const SizedBox.shrink();
      }
      return ViewingReviewSummaryContent(
        data: data,
        title: widget.landlord ? 'Landlord experience' : 'Viewing experience',
      );
    },
  );
}
