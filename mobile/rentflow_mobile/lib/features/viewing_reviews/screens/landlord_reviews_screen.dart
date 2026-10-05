import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/profile/profile_page.dart';
import '../services/viewing_review_api_service.dart';
import '../widgets/viewing_rating_summary.dart';

class LandlordReviewsScreen extends StatefulWidget {
  const LandlordReviewsScreen({super.key, this.apiService});
  final ViewingReviewApiService? apiService;
  @override
  State<LandlordReviewsScreen> createState() => _LandlordReviewsScreenState();
}

class _LandlordReviewsScreenState extends State<LandlordReviewsScreen> {
  ApiClient? _ownedClient;
  late final ViewingReviewApiService _api;
  late Future<Map<String, dynamic>> _summary;
  @override
  void initState() {
    super.initState();
    _api =
        widget.apiService ??
        ViewingReviewApiService(_ownedClient = ApiClient());
    _load();
  }

  @override
  void dispose() {
    _ownedClient?.close();
    super.dispose();
  }

  void _load() {
    _summary = _api.landlordSummary();
    // A fast failed retry can finish before the next frame attaches its builder.
    _summary.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  void _retry() => setState(_load);
  @override
  Widget build(BuildContext context) => ProfileSurface(
    child: Scaffold(
      appBar: profilePageAppBar(context, title: 'Reviews', backLabel: 'Back'),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _summary,
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load viewing feedback.'),
                  TextButton(onPressed: _retry, child: const Text('Try again')),
                ],
              ),
            );
          }
          final data = snapshot.data!,
              landlord = data['landlord'] as Map<String, dynamic>,
              properties = data['properties'] as List;
          final empty =
              landlord['reviewCount'] == 0 &&
              properties.every((p) => p['reviewCount'] == 0);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'LANDLORD',
                  style: TextStyle(fontSize: 12, color: AppPalette.neutral),
                ),
                const SizedBox(height: 12),
                if (empty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No viewing feedback yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Verified feedback will appear here after tenants complete viewings and leave a review.',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  )
                else
                  ViewingReviewSummaryContent(
                    data: landlord,
                    title: 'Your landlord experience',
                    metadataColor: AppPalette.neutral,
                  ),
                if (properties.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Property feedback',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  for (final property in properties)
                    ViewingReviewSummaryContent(
                      data: {
                        ...property as Map<String, dynamic>,
                        'reviews': property['recentReviews'],
                      },
                      title: property['title'] as String,
                      metadataColor: AppPalette.neutral,
                    ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}
