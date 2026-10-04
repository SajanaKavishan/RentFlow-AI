import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class ViewingRatingSummary extends StatelessWidget {
  const ViewingRatingSummary({
    super.key,
    required this.summary,
    this.onTap,
    this.compact = false,
  });
  final Future<Map<String, dynamic>> summary;
  final VoidCallback? onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: summary,
    builder: (_, snapshot) {
      final data = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done ||
          snapshot.hasError ||
          data == null ||
          (data['reviewCount'] as int) == 0) {
        return const SizedBox.shrink();
      }
      final average = (data['averageRating'] as num).toStringAsFixed(1),
          count = data['reviewCount'] as int;
      final label =
          '$average out of 5 from $count verified ${count == 1 ? 'viewing' : 'viewings'}';
      return Semantics(
        label: label,
        button: onTap != null,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 3,
                  children: [
                    const Icon(Icons.star, size: 16, color: AppPalette.olive),
                    Text(
                      average,
                      style: TextStyle(
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.darkOlive,
                      ),
                    ),
                    Text(
                      '$count verified ${count == 1 ? 'viewing' : 'viewings'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppPalette.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ViewingReviewSummaryContent extends StatelessWidget {
  const ViewingReviewSummaryContent({
    super.key,
    required this.data,
    required this.title,
  });
  final Map<String, dynamic> data;
  final String title;
  @override
  Widget build(BuildContext context) {
    final count = data['reviewCount'] as int;
    return Card(
      color: AppPalette.warmCream,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (count == 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No verified viewing feedback yet.',
                  style: TextStyle(fontSize: 14),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              Text(
                '${(data['averageRating'] as num).toStringAsFixed(1)} ★',
                semanticsLabel:
                    '${(data['averageRating'] as num).toStringAsFixed(1)} out of 5',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.darkOlive,
                ),
              ),
              Text(
                '$count verified ${count == 1 ? 'viewing' : 'viewings'}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.secondaryText,
                ),
              ),
              for (final value
                  in (data['reviews'] as List)
                      .where((r) => (r['comment'] as String).trim().isNotEmpty)
                      .take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppPalette.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${'★' * (value['rating'] as int)}${'☆' * (5 - (value['rating'] as int))}',
                          semanticsLabel: '${value['rating']} out of 5',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppPalette.darkOlive,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value['comment'] as String,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Verified viewing · ${_month(context, value['reviewMonth'] as String)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppPalette.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _month(BuildContext context, String value) {
    final date = DateTime.tryParse('$value-01');
    return date == null
        ? ''
        : MaterialLocalizations.of(context).formatMonthYear(date);
  }
}
