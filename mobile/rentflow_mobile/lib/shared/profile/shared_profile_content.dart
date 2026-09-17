import 'package:flutter/material.dart';

import '../../features/auth/models/current_user.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';

class SharedProfileContent extends StatelessWidget {
  const SharedProfileContent({
    super.key,
    required this.user,
    this.onOpenApplications,
  });

  final CurrentUser user;
  final VoidCallback? onOpenApplications;

  @override
  Widget build(BuildContext context) => AuthenticatedPage(
    maxWidth: 580,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          eyebrow: 'Profile',
          title: user.fullName.trim().isEmpty ? 'Your account' : user.fullName,
          subtitle:
              'Authenticated account details and shared RentFlow settings.',
          trailing: _ProfileAvatar(name: user.fullName),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ProfileSection(
          title: 'Account',
          children: [
            _ProfileValueTile(
              icon: Icons.badge_outlined,
              label: 'Full name',
              value: _availableValue(user.fullName),
            ),
            _ProfileValueTile(
              icon: Icons.alternate_email,
              label: 'Email',
              value: _availableValue(user.email),
            ),
            _ProfileValueTile(
              icon: Icons.phone_outlined,
              label: 'Phone number',
              value: _availableValue(user.phoneNumber),
            ),
            _ProfileValueTile(
              icon: Icons.person_outline,
              label: 'Role',
              value: user.role.value,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ProfileSection(
          title: 'Security',
          children: [
            _PendingProfileTile(
              icon: Icons.lock_outline,
              title: 'Password & security',
              message: 'Security settings are not available in the mobile app.',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ProfileSection(
          title: 'Preferences',
          children: [
            _PendingProfileTile(
              icon: Icons.tune_outlined,
              title: 'App preferences',
              message: 'Preference controls have not been integrated yet.',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _ProfileSection(
          title: 'Documents',
          children: [
            _ProfileActionTile(
              icon: Icons.folder_outlined,
              title: 'Application documents',
              message: onOpenApplications == null
                  ? 'Document access is not available for this mobile workspace.'
                  : 'Documents are managed within each rental application.',
              status: onOpenApplications == null
                  ? const StatusChip(
                      label: 'Integration pending',
                      tone: StatusTone.warning,
                    )
                  : null,
              actionLabel: onOpenApplications == null
                  ? null
                  : 'Open applications',
              onAction: onOpenApplications,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ProfileSection(
          title: 'Support',
          children: [
            _PendingProfileTile(
              icon: Icons.help_outline,
              title: 'Help & support',
              message: 'In-app support is not connected yet.',
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppPalette.darkOlive,
      shape: BoxShape.circle,
    ),
    child: Text(
      _initials(name),
      style: const TextStyle(
        color: AppPalette.white,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(title: title),
      const SizedBox(height: AppSpacing.md),
      AppCard(
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    ],
  );
}

class _ProfileValueTile extends StatelessWidget {
  const _ProfileValueTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: AppPalette.olive),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppPalette.secondaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PendingProfileTile extends StatelessWidget {
  const _PendingProfileTile({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => _ProfileActionTile(
    icon: icon,
    title: title,
    message: message,
    status: const StatusChip(
      label: 'Integration pending',
      tone: StatusTone.warning,
    ),
  );
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.message,
    this.status,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? status;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: AppPalette.olive),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
              if (status != null) ...[
                const SizedBox(height: AppSpacing.sm),
                status!,
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

String _availableValue(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Not provided' : trimmed;
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (words.isEmpty) return 'RF';
  return words.map((word) => word[0].toUpperCase()).join();
}
