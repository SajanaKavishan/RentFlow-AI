import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/rental_application.dart';

final applicationPageTitle = AppTypography.display.copyWith(
  fontWeight: FontWeight.w600,
  color: AppPalette.darkOlive,
);
final applicationSectionTitle = AppTypography.sectionTitle.copyWith(
  fontWeight: FontWeight.w600,
  color: AppPalette.darkOlive,
);
final applicationMetadata = AppTypography.label.copyWith(
  fontSize: 12,
  fontWeight: FontWeight.w400,
  color: AppPalette.secondaryText,
  height: 1.4,
);

String applicationDate(BuildContext context, DateTime timestamp) =>
    MaterialLocalizations.of(context).formatShortMonthDay(timestamp.toLocal());

String applicationStatusLabel(RentalApplicationStatus status) =>
    switch (status) {
      RentalApplicationStatus.draft => 'Draft',
      RentalApplicationStatus.submitted => 'Submitted',
      RentalApplicationStatus.underReview => 'Under review',
      RentalApplicationStatus.changesRequested => 'Action required',
      RentalApplicationStatus.approved => 'Approved',
      RentalApplicationStatus.rejected => 'Rejected',
      RentalApplicationStatus.withdrawn => 'Withdrawn',
    };

String applicationStatusSummary(RentalApplicationStatus status) =>
    switch (status) {
      RentalApplicationStatus.draft => 'Ready when you are',
      RentalApplicationStatus.submitted => 'Awaiting landlord review',
      RentalApplicationStatus.underReview =>
        'The landlord is reviewing your application',
      RentalApplicationStatus.changesRequested =>
        'Updates requested by the landlord',
      RentalApplicationStatus.approved => 'Application approved',
      RentalApplicationStatus.rejected => 'Application declined',
      RentalApplicationStatus.withdrawn => 'Application withdrawn',
    };

class TenantApplicationStatusChip extends StatelessWidget {
  const TenantApplicationStatusChip({super.key, required this.status});
  final RentalApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      RentalApplicationStatus.changesRequested => (
        const Color(0xFFFBE1D8),
        const Color(0xFF963E2F),
      ),
      RentalApplicationStatus.submitted ||
      RentalApplicationStatus.underReview => (
        const Color(0xFFE5EDF8),
        const Color(0xFF365B87),
      ),
      RentalApplicationStatus.approved => (
        AppPalette.sage,
        AppPalette.darkOlive,
      ),
      RentalApplicationStatus.rejected => (
        const Color(0xFFF5DDDC),
        AppPalette.danger,
      ),
      RentalApplicationStatus.draft || RentalApplicationStatus.withdrawn => (
        AppPalette.softCream,
        AppPalette.neutral,
      ),
    };
    final label = applicationStatusLabel(status);
    return Semantics(
      label: status == RentalApplicationStatus.changesRequested
          ? 'Application status: Changes requested. Action required.'
          : 'Application status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTypography.label.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

class TenantApplicationHeader extends StatelessWidget {
  const TenantApplicationHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.onBack,
    this.onNew,
    this.titleStyle,
  });
  final String eyebrow;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onNew;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (onBack != null) ...[
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          style: IconButton.styleFrom(
            foregroundColor: AppPalette.darkOlive,
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
            elevation: 0,
            minimumSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.arrow_back, size: 24),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: AppTypography.eyebrow.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppPalette.olive,
              ),
            ),
            const SizedBox(height: 4),
            Text(title, style: titleStyle ?? applicationPageTitle),
          ],
        ),
      ),
      if (onNew != null) ...[
        const SizedBox(width: 12),
        OutlinedButton(
          key: const ValueKey('new-rental-application'),
          onPressed: onNew,
          style: OutlinedButton.styleFrom(
            backgroundColor: AppPalette.white,
            foregroundColor: AppPalette.darkOlive,
            minimumSize: const Size(64, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            textStyle: AppTypography.label.copyWith(
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('+ New'),
        ),
      ],
    ],
  );
}

class TenantApplicationCard extends StatelessWidget {
  const TenantApplicationCard({
    super.key,
    required this.child,
    this.actionRequired = false,
    this.onTap,
  });
  final Widget child;
  final bool actionRequired;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: actionRequired ? const Color(0xFFFFF8F4) : AppPalette.white,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(
        color: actionRequired ? const Color(0xFFEAB2A2) : AppPalette.outline,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
}

class ApplicationJourneyActionRow extends StatelessWidget {
  const ApplicationJourneyActionRow({
    super.key,
    required this.summary,
    required this.label,
    required this.onPressed,
    this.actionKey,
  });
  final Widget summary;
  final String label;
  final VoidCallback? onPressed;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final action = TextButton.icon(
        key: actionKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.darkOlive,
          textStyle: AppTypography.button.copyWith(fontWeight: FontWeight.w600),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        ),
        icon: const Icon(Icons.chevron_right, size: 18),
        iconAlignment: IconAlignment.end,
        label: Text(label),
      );
      if (constraints.maxWidth < 260 ||
          MediaQuery.textScalerOf(context).scale(14) > 21) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            summary,
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: summary),
          const SizedBox(width: 8),
          action,
        ],
      );
    },
  );
}
