import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
  });
  final String title;
  final String? subtitle;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(
          eyebrow!,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: AppPalette.text,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle!,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppPalette.muted),
        ),
      ],
    ],
  );
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: child,
    ),
  );
}

enum StatusTone { neutral, pending, progress, success, warning, danger }

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });
  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (foreground, background) = switch (tone) {
      StatusTone.neutral => (AppPalette.neutral, const Color(0xFFE9E7E2)),
      StatusTone.pending ||
      StatusTone.warning => (AppPalette.warning, AppPalette.pending),
      StatusTone.progress => (const Color(0xFF43556A), AppPalette.progress),
      StatusTone.success => (AppPalette.success, const Color(0xFFDDECDD)),
      StatusTone.danger => (AppPalette.danger, const Color(0xFFF5DDDC)),
    };
    return Chip(
      label: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
      ),
      backgroundColor: background,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
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
  });
  final String title;
  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const CircularProgressIndicator()
          else if (icon != null)
            Icon(icon, size: 48, color: AppPalette.primary),
          const SizedBox(height: AppSpacing.base),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(message!, textAlign: TextAlign.center),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.base),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.title = 'Loading'});
  final String title;
  @override
  Widget build(BuildContext context) =>
      SharedState(title: title, loading: true);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message});
  final String title;
  final String? message;
  @override
  Widget build(BuildContext context) =>
      SharedState(title: title, message: message, icon: Icons.inbox_outlined);
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => SharedState(
    title: 'Something went wrong',
    message: message,
    icon: Icons.error_outline,
    actionLabel: 'Try again',
    onAction: onRetry,
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
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.construction_outlined,
                size: 46,
                color: AppPalette.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              StatusChip(label: status, tone: StatusTone.warning),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(explanation, textAlign: TextAlign.center),
              if (owner != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Owning area: $owner',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
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
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.devices_outlined,
                size: 46,
                color: AppPalette.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(explanation, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Full management tools are available on the RentFlow web workspace.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppPalette.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
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
