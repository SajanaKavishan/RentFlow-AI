import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../services/viewing_review_api_service.dart';

class PublicViewingReviews extends StatefulWidget {
  const PublicViewingReviews({
    super.key,
    required this.propertyId,
    required this.api,
    this.landlord = false,
  });
  final String propertyId;
  final ViewingReviewApiService api;
  final bool landlord;
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
    _summary = widget.api.publicSummary(
      widget.propertyId,
      landlord: widget.landlord,
    );
  }

  @override
  void didUpdateWidget(covariant PublicViewingReviews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId ||
        oldWidget.landlord != widget.landlord) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _summary,
    builder: (_, snapshot) {
      final data = snapshot.data;
      if (snapshot.hasError ||
          data == null ||
          (data['reviewCount'] as int) == 0) {
        return const SizedBox.shrink();
      }
      final count = data['reviewCount'] as int;
      return Card(
        color: AppPalette.warmCream,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.landlord ? 'Landlord experience' : 'Viewing experience',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(data['averageRating'] as num).toStringAsFixed(1)} ★ · $count verified ${count == 1 ? 'viewing' : 'viewings'}',
                style: const TextStyle(
                  fontSize: 18,
                  color: AppPalette.darkOlive,
                ),
              ),
              for (final value in data['reviews'] as List) ...[
                const Divider(),
                Text(
                  '${'★' * (value['rating'] as int)}${'☆' * (5 - (value['rating'] as int))}',
                  semanticsLabel: '${value['rating']} out of 5',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppPalette.darkOlive,
                  ),
                ),
                Text(
                  value['comment'] as String,
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  'Verified viewing · ${_month(context, value['reviewMonth'] as String)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  String _month(BuildContext context, String value) {
    final date = DateTime.tryParse('$value-01');
    return date == null
        ? ''
        : MaterialLocalizations.of(context).formatMonthYear(date);
  }
}
