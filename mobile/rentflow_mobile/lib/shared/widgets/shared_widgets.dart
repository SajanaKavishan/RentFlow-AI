import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AuthenticatedPage extends StatelessWidget {
  const AuthenticatedPage({
    super.key,
    required this.child,
    this.padding = AppSpacing.page,
    this.maxWidth = 680,
    this.physics,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      physics: physics,
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    ),
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(
          eyebrow!.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.olive,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ],
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
      if (trailing != null) ...[
        const SizedBox(width: AppSpacing.md),
        trailing!,
      ],
    ],
  );
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.card,
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

enum StatusTone { neutral, pending, progress, success, warning, danger }

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (tone) {
      StatusTone.neutral => (AppPalette.neutral, AppPalette.softCream),
      StatusTone.pending ||
      StatusTone.warning => (AppPalette.warning, AppPalette.pending),
      StatusTone.progress => (AppPalette.darkOlive, AppPalette.progress),
      StatusTone.success => (AppPalette.success, AppPalette.sage),
      StatusTone.danger => (AppPalette.danger, const Color(0xFFF5DDDC)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SharedState extends StatelessWidget {
  const SharedState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.loading = false,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          const SizedBox.square(
            dimension: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        else if (icon != null)
          Container(
            width: compact ? 48 : 60,
            height: compact ? 48 : 60,
            decoration: const BoxDecoration(
              color: AppPalette.sage,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: compact ? 24 : 30,
              color: AppPalette.darkOlive,
            ),
          ),
        const SizedBox(height: AppSpacing.base),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: AppSpacing.base),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(actionLabel!),
          ),
        ],
      ],
    );

    if (compact) return content;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: content,
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    this.title = 'Loading',
    this.message,
    this.compact = false,
  });

  final String title;
  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) => SharedState(
    title: title,
    message: message,
    loading: true,
    compact: compact,
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.compact = false,
  });

  final String title;
  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) => SharedState(
    title: title,
    message: message,
    icon: Icons.inbox_outlined,
    compact: compact,
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) => SharedState(
    title: 'Something went wrong',
    message: message,
    icon: Icons.error_outline,
    actionLabel: 'Try again',
    onAction: onRetry,
    compact: compact,
  );
}

class IntegrationPendingState extends StatelessWidget {
  const IntegrationPendingState({
    super.key,
    required this.title,
    required this.message,
    this.compact = false,
  });

  final String title;
  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const StatusChip(
        label: 'Integration pending',
        tone: StatusTone.warning,
        icon: Icons.schedule_outlined,
      ),
      const SizedBox(height: AppSpacing.md),
      SharedState(
        title: title,
        message: message,
        icon: Icons.construction_outlined,
        compact: compact,
      ),
    ],
  );
}

class UnauthorizedState extends StatelessWidget {
  const UnauthorizedState({super.key});

  @override
  Widget build(BuildContext context) => const SharedState(
    title: 'Not accessible',
    message: 'Your account does not have access to this area.',
    icon: Icons.lock_outline,
  );
}

class ModuleUnavailableState extends StatelessWidget {
  const ModuleUnavailableState({
    super.key,
    required this.title,
    required this.explanation,
    this.owner,
    this.status = 'Integration pending',
  });

  final String title;
  final String explanation;
  final String? owner;
  final String status;

  @override
  Widget build(BuildContext context) => AuthenticatedPage(
    maxWidth: 520,
    child: AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(
            label: status,
            tone: StatusTone.warning,
            icon: Icons.schedule_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          const Icon(
            Icons.construction_outlined,
            size: 44,
            color: AppPalette.olive,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            explanation,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (owner != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Owning area: $owner',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppPalette.olive,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class WebWorkspaceState extends StatelessWidget {
  const WebWorkspaceState({
    super.key,
    required this.title,
    required this.explanation,
  });

  final String title;
  final String explanation;

  @override
  Widget build(BuildContext context) => AuthenticatedPage(
    maxWidth: 520,
    child: AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          SharedState(
            title: title,
            message: explanation,
            icon: Icons.devices_outlined,
            compact: true,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Full management tools are available on the RentFlow web workspace.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppPalette.olive,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class UnavailableState extends ModuleUnavailableState {
  const UnavailableState({super.key, required String module})
    : super(
        title: module,
        explanation:
            'This module has not been integrated into RentFlow yet. No workflow is available here.',
      );
}

enum SnackTone { neutral, success, error }

abstract final class AppSnackbars {
  static void show(
    BuildContext context, {
    required String message,
    SnackTone tone = SnackTone.neutral,
  }) {
    final background = switch (tone) {
      SnackTone.neutral => AppPalette.darkOlive,
      SnackTone.success => AppPalette.success,
      SnackTone.error => AppPalette.danger,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: background,
          showCloseIcon: true,
          closeIconColor: AppPalette.white,
        ),
      );
  }
}
