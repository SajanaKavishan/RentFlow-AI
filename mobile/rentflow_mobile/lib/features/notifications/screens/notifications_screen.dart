import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/notification.dart';
import '../services/notification_api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.notificationApiService});

  final NotificationApiService notificationApiService;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _scrollController = ScrollController();
  final _items = <AppNotification>[];
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNextPage = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage({bool refreshing = false}) async {
    if (!refreshing && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.notificationApiService.getNotifications();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = page.pagination.page;
        _hasNextPage = page.pagination.hasNextPage;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 240 ||
        _loadingMore ||
        !_hasNextPage) {
      return;
    }
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    setState(() => _loadingMore = true);
    try {
      final page = await widget.notificationApiService.getNotifications(
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _page = page.pagination.page;
        _hasNextPage = page.pagination.hasNextPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _markAsRead(int index) async {
    final item = _items[index];
    if (item.isRead) return;
    try {
      final confirmed = await widget.notificationApiService.markAsRead(item.id);
      if (!mounted) return;
      setState(() => _items[index] = confirmed);
    } catch (error) {
      if (!mounted) return;
      AppSnackbars.show(context, message: _messageFor(error));
    }
  }

  String _messageFor(Object error) => error is NotificationApiException
      ? error.message
      : 'The notifications could not be updated. Please try again.';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    ),
    body: _buildBody(),
  );

  Widget _buildBody() {
    if (_loading) return const LoadingState(title: 'Loading notifications…');
    if (_error != null && _items.isEmpty) {
      return ErrorState(message: _messageFor(_error!), onRetry: _loadFirstPage);
    }
    if (_items.isEmpty) {
      return const EmptyState(
        title: 'No notifications yet',
        message: 'New activity will appear here when it is available.',
      );
    }
    return RefreshIndicator(
      color: AppPalette.olive,
      onRefresh: () => _loadFirstPage(refreshing: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.base),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _NotificationTile(
            notification: _items[index],
            onTap: () => _markAsRead(index),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return AppCard(
      color: unread ? AppPalette.sage : AppPalette.white,
      onTap: unread ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            unread
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
            color: unread ? AppPalette.darkOlive : AppPalette.secondaryText,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                      ),
                    ),
                    if (unread)
                      const Padding(
                        padding: EdgeInsets.only(left: AppSpacing.sm, top: 5),
                        child: SizedBox.square(
                          dimension: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppPalette.olive,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(notification.message),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _formatTimestamp(notification.createdAt),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppPalette.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
