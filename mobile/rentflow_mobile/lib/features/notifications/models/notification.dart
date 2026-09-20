class AppNotification {
  const AppNotification({
    required this.id,
    required this.eventType,
    required this.relatedResourceType,
    required this.relatedResourceId,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.readAt,
    required this.isRead,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (createdAt == null) throw const FormatException();
    return AppNotification(
      id: json['id'] as String? ?? '',
      eventType: json['eventType'] as String? ?? '',
      relatedResourceType: json['relatedResourceType'] as String? ?? '',
      relatedResourceId: json['relatedResourceId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      createdAt: createdAt,
      readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
      isRead:
          json['isRead'] as bool? ??
          DateTime.tryParse(json['readAt'] as String? ?? '') != null,
    );
  }

  final String id;
  final String eventType;
  final String relatedResourceType;
  final String relatedResourceId;
  final String title;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;
  final bool isRead;

  AppNotification copyWith({DateTime? readAt, bool? isRead}) => AppNotification(
    id: id,
    eventType: eventType,
    relatedResourceType: relatedResourceType,
    relatedResourceId: relatedResourceId,
    title: title,
    message: message,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
    isRead: isRead ?? this.isRead,
  );
}

class NotificationPage {
  const NotificationPage({required this.items, required this.pagination});

  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawPagination = json['pagination'];
    if (rawItems is! List || rawPagination is! Map<String, dynamic>) {
      throw const FormatException();
    }
    return NotificationPage(
      items: rawItems
          .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      pagination: NotificationPagination.fromJson(rawPagination),
    );
  }

  final List<AppNotification> items;
  final NotificationPagination pagination;
}

class NotificationPagination {
  const NotificationPagination({
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
    required this.hasNextPage,
    required this.hasPreviousPage,
  });

  factory NotificationPagination.fromJson(Map<String, dynamic> json) =>
      NotificationPagination(
        page: json['page'] as int? ?? 1,
        pageSize: json['pageSize'] as int? ?? 20,
        totalCount: json['totalCount'] as int? ?? 0,
        totalPages: json['totalPages'] as int? ?? 0,
        hasNextPage: json['hasNextPage'] as bool? ?? false,
        hasPreviousPage: json['hasPreviousPage'] as bool? ?? false,
      );

  final int page;
  final int pageSize;
  final int totalCount;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPreviousPage;
}
