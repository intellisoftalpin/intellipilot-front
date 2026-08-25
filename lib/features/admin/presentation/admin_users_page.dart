import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/security_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_users_cubit.dart';
import 'package:intellipilot/features/admin/presentation/widgets/user_security_widgets.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminUsersCubit>(
      create: (_) {
        final c = AdminUsersCubit(getIt<AdminRepository>());
        unawaited(c.load());
        return c;
      },
      child: const _UsersView(),
    );
  }
}

class _UsersView extends StatefulWidget {
  const _UsersView();
  @override
  State<_UsersView> createState() => _UsersViewState();
}

class _UsersViewState extends State<_UsersView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<AdminUsersCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminUsersTitle),
        actions: [
          IconButton(
            onPressed: _openInviteDialog,
            icon: const Icon(Icons.mail_outline),
            tooltip: l10n.adminInviteTitle,
          ),
          IconButton(
            onPressed: () => _openCreateDialog(cubit),
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: l10n.adminUsersCreateTooltip,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.adminUsersSearchHint,
              ),
              onSubmitted: (v) => cubit.load(q: v.trim()),
            ),
          ),
          BlocBuilder<AdminUsersCubit, AdminUsersState>(
            builder: (context, state) => _FilterChips(
              active: state is AdminUsersLoaded ? state.statusFilter : null,
              onSelect: (v) => v == null
                  ? cubit.load(clearStatus: true)
                  : cubit.load(status: v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BlocBuilder<AdminUsersCubit, AdminUsersState>(
              builder: (context, state) => switch (state) {
                AdminUsersLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
                AdminUsersFailed(:final failure) => Center(
                  child: Text(l10n.adminUsersLoadFailed(failure.debugLabel)),
                ),
                AdminUsersLoaded(
                  :final items,
                  :final total,
                  :final lastError,
                ) =>
                  _UsersList(
                    items: items,
                    total: total,
                    lastError: lastError,
                    onPatch: (u, patch) => cubit.patch(u.id, patch),
                    onDelete: (u) => _confirmDelete(u, cubit),
                    onResetPassword: (u) => _resetPasswordFlow(u, cubit),
                    onResetTwoFactor: (u) => _resetTwoFactorFlow(u, cubit),
                    onBan: (u) => _banFlow(u, cubit),
                    onUnban: (u) => _unbanFlow(u, cubit),
                    onShowSessions: (u) => _showSessions(u, cubit),
                    onRevokeSessions: (u) => _revokeSessionsFlow(u, cubit),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateDialog(AdminUsersCubit cubit) async {
    final result = await showDialog<CreateUserResponse>(
      context: context,
      builder: (_) => _CreateUserDialog(cubit: cubit),
    );
    if (!mounted) return;
    if (result != null && result.generatedPassword != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => _TempCredentialDialog(
          email: result.user.email,
          password: result.generatedPassword!,
        ),
      );
    }
  }

  Future<void> _openInviteDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
  }

  /// Clears every second factor after an explicit, itemised confirmation.
  Future<void> _resetTwoFactorFlow(
    AdminUserRow u,
    AdminUsersCubit cubit,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ResetTwoFactorDialog(row: u),
    );
    if (!(confirmed ?? false) || !mounted) return;

    final result = await cubit.resetTwoFactor(u.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (result == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminUsersReset2faFailed)),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.clearedNothing
              ? l10n.adminUsersReset2faNothing(u.email)
              : l10n.adminUsersReset2faDone(u.email),
        ),
      ),
    );
  }

  Future<void> _banFlow(AdminUserRow u, AdminUsersCubit cubit) async {
    final l10n = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _BanUserDialog(row: u),
    );
    if (reason == null || !mounted) return;

    final ok = await cubit.ban(u.id, reason: reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? l10n.adminUsersBanDone(u.email) : l10n.adminUsersBanFailed,
        ),
      ),
    );
  }

  Future<void> _unbanFlow(AdminUserRow u, AdminUsersCubit cubit) async {
    final l10n = AppLocalizations.of(context);
    final ok = await cubit.unban(u.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? l10n.adminUsersUnbanDone(u.email) : l10n.adminUsersBanFailed,
        ),
      ),
    );
  }

  Future<void> _showSessions(AdminUserRow u, AdminUsersCubit cubit) async {
    final sessions = await cubit.sessionsFor(u.id);
    if (!mounted) return;
    if (sessions == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).adminUsersSessionsFailed),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => UserSessionsSheet(email: u.email, sessions: sessions),
    );
  }

  Future<void> _revokeSessionsFlow(
    AdminUserRow u,
    AdminUsersCubit cubit,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.adminUsersSignOutAllTitle),
        content: Text(l10n.adminUsersSignOutAllBody(u.email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.adminUsersCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.adminUsersSignOutAllConfirm),
          ),
        ],
      ),
    );
    if (!(confirm ?? false) || !mounted) return;

    final n = await cubit.revokeSessions(u.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == null
              ? l10n.adminUsersSessionsFailed
              : l10n.adminUsersSignOutAllDone(n),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(AdminUserRow u, AdminUsersCubit cubit) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.adminUsersDeleteTitle),
        content: Text(l10n.adminUsersDeleteBody(u.email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.adminUsersCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.adminUsersDelete),
          ),
        ],
      ),
    );
    if (confirm ?? false) {
      await cubit.remove(u.id);
    }
  }

  Future<void> _resetPasswordFlow(AdminUserRow u, AdminUsersCubit cubit) async {
    final l10n = AppLocalizations.of(context);
    final issued = await cubit.resetPasswordFor(u.id);
    if (!mounted) return;
    if (issued == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminUsersResetError)),
      );
      return;
    }
    if (issued.resetToken != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => _OneTimeTokenDialog(
          title: l10n.adminUsersResetTokenTitle,
          subtitle: l10n.adminUsersResetTokenSubtitle(
            u.email,
            issued.expiresAt.toLocal().toString(),
          ),
          token: issued.resetToken!,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminUsersResetEmailSent(u.email))),
      );
    }
  }
}

/// Status filter chips. Null value means "all".
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.active, required this.onSelect});

  final String? active;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(String?, String)>[
      (null, l10n.adminUsersFilterAll),
      ('active', l10n.adminUsersStatusActive),
      ('banned', l10n.adminUsersStatusBanned),
      ('inactive', l10n.adminUsersStatusInactive),
      ('no_2fa', l10n.adminUsersFilterNo2fa),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final (value, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: active == value,
                onSelected: (_) => onSelect(value),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _UsersList extends StatelessWidget {
  const _UsersList({
    required this.items,
    required this.total,
    required this.onPatch,
    required this.onDelete,
    required this.onResetPassword,
    required this.onResetTwoFactor,
    required this.onBan,
    required this.onUnban,
    required this.onShowSessions,
    required this.onRevokeSessions,
    this.lastError,
  });

  final List<AdminUserRow> items;
  final int total;
  final Object? lastError;
  final Future<UserProfile?> Function(AdminUserRow, UpdateUserRequest) onPatch;
  final void Function(AdminUserRow) onDelete;
  final void Function(AdminUserRow) onResetPassword;
  final void Function(AdminUserRow) onResetTwoFactor;
  final void Function(AdminUserRow) onBan;
  final void Function(AdminUserRow) onUnban;
  final void Function(AdminUserRow) onShowSessions;
  final void Function(AdminUserRow) onRevokeSessions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        if (lastError != null)
          Container(
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.adminUsersLastActionFailed,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(l10n.adminUsersCount(total)),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemBuilder: (_, i) => _UserRow(
              row: items[i],
              onToggleActive: (v) =>
                  onPatch(items[i], UpdateUserRequest(isActive: v)),
              onToggleSuperadmin: (v) =>
                  onPatch(items[i], UpdateUserRequest(isSuperadmin: v)),
              onToggleTimeReports: (v) => onPatch(
                items[i],
                UpdateUserRequest(excludeFromTimeReports: v),
              ),
              onDelete: () => onDelete(items[i]),
              onResetPassword: () => onResetPassword(items[i]),
              onResetTwoFactor: () => onResetTwoFactor(items[i]),
              onBan: () => onBan(items[i]),
              onUnban: () => onUnban(items[i]),
              onShowSessions: () => onShowSessions(items[i]),
              onRevokeSessions: () => onRevokeSessions(items[i]),
            ),
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemCount: items.length,
          ),
        ),
      ],
    );
  }
}

/// One account, with its security posture readable at a glance.
///
/// Laid out responsively: on a wide window the security columns sit on the
/// same line as the identity; on a narrow one they wrap underneath rather than
/// overflowing.
class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.row,
    required this.onToggleActive,
    required this.onToggleSuperadmin,
    required this.onToggleTimeReports,
    required this.onDelete,
    required this.onResetPassword,
    required this.onResetTwoFactor,
    required this.onBan,
    required this.onUnban,
    required this.onShowSessions,
    required this.onRevokeSessions,
  });

  final AdminUserRow row;
  final ValueChanged<bool> onToggleActive;
  final ValueChanged<bool> onToggleSuperadmin;

  /// Sets/clears the timesheet-report exclusion.
  final ValueChanged<bool> onToggleTimeReports;
  final VoidCallback onDelete;
  final VoidCallback onResetPassword;
  final VoidCallback onResetTwoFactor;
  final VoidCallback onBan;
  final VoidCallback onUnban;
  final VoidCallback onShowSessions;
  final VoidCallback onRevokeSessions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final user = row.user;

    final security = <Widget>[
      TwoFactorBadge(status: row.twoFactor),
      SessionChip(count: row.activeSessions, onTap: onShowSessions),
      SessionLocation(session: row.lastSession),
      TimestampCell(
        label: l10n.adminUsersLastActive,
        value: row.lastSeenAt,
        icon: Icons.bolt_outlined,
      ),
      TimestampCell(
        label: l10n.adminUsersLastLogin,
        value: row.lastLoginAt,
        icon: Icons.login,
      ),
    ];

    return Opacity(
      // A banned account is still listed but visibly out of play.
      opacity: row.isBanned ? 0.75 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(user: user.toRef(), size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ActivityDot(lastSeenAt: row.lastSeenAt),
                      Flexible(
                        child: Text(
                          user.email,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            decoration: row.isBanned
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(row: row),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${user.username} · ${user.fullName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _AuthSourceTag(user: user),
                      if (user.isSuperadmin)
                        _MiniTag(
                          icon: Icons.admin_panel_settings_outlined,
                          label: l10n.adminUsersChipSuperadmin,
                        ),
                      if (user.mustChangePassword)
                        _MiniTag(
                          icon: Icons.key_outlined,
                          label: l10n.adminUsersChipTempPw,
                        ),
                      if (user.excludeFromTimeReports)
                        _MiniTag(
                          icon: Icons.visibility_off_outlined,
                          label: l10n.adminUsersExcludedBadge,
                        ),
                      ...security,
                    ],
                  ),
                ],
              ),
            ),
            _RowMenu(
              row: row,
              onToggleActive: onToggleActive,
              onToggleSuperadmin: onToggleSuperadmin,
              onToggleTimeReports: onToggleTimeReports,
              onDelete: onDelete,
              onResetPassword: onResetPassword,
              onResetTwoFactor: onResetTwoFactor,
              onBan: onBan,
              onUnban: onUnban,
              onRevokeSessions: onRevokeSessions,
            ),
          ],
        ),
      ),
    );
  }
}

/// LDAP vs local — the distinction that decides whether a password reset is
/// even possible, and why deactivation alone cannot hold an LDAP account out.
class _AuthSourceTag extends StatelessWidget {
  const _AuthSourceTag({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    return _MiniTag(
      icon: user.isLdap ? Icons.dns_outlined : Icons.password_outlined,
      label: user.isLdap ? 'LDAP' : 'Local',
      color: user.isLdap ? Theme.of(context).colorScheme.tertiary : null,
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
      ],
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.row,
    required this.onToggleActive,
    required this.onToggleSuperadmin,
    required this.onToggleTimeReports,
    required this.onDelete,
    required this.onResetPassword,
    required this.onResetTwoFactor,
    required this.onBan,
    required this.onUnban,
    required this.onRevokeSessions,
  });

  final AdminUserRow row;
  final ValueChanged<bool> onToggleActive;
  final ValueChanged<bool> onToggleSuperadmin;
  final ValueChanged<bool> onToggleTimeReports;
  final VoidCallback onDelete;
  final VoidCallback onResetPassword;
  final VoidCallback onResetTwoFactor;
  final VoidCallback onBan;
  final VoidCallback onUnban;
  final VoidCallback onRevokeSessions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      onSelected: (key) {
        switch (key) {
          case 'reset_2fa':
            onResetTwoFactor();
          case 'revoke_sessions':
            onRevokeSessions();
          case 'ban':
            onBan();
          case 'unban':
            onUnban();
          case 'toggle_active':
            onToggleActive(!row.user.isActive);
          case 'toggle_superadmin':
            onToggleSuperadmin(!row.user.isSuperadmin);
          case 'toggle_time_reports':
            onToggleTimeReports(!row.user.excludeFromTimeReports);
          case 'reset':
            onResetPassword();
          case 'time':
            unawaited(context.push(Routes.adminUserTimeFor(row.id)));
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (_) => [
        // Recovery first: this is the item an admin reaches for when a user
        // has locked themselves out, which is the common emergency.
        PopupMenuItem(
          value: 'reset_2fa',
          enabled: row.twoFactor.enabled,
          child: Row(
            children: [
              const Icon(Icons.lock_reset, size: 18),
              const SizedBox(width: 10),
              Text(l10n.adminUsersReset2fa),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'revoke_sessions',
          enabled: row.activeSessions > 0,
          child: Row(
            children: [
              const Icon(Icons.logout, size: 18),
              const SizedBox(width: 10),
              Text(l10n.adminUsersSignOutAll),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (row.isBanned)
          PopupMenuItem(
            value: 'unban',
            child: Row(
              children: [
                const Icon(Icons.lock_open, size: 18),
                const SizedBox(width: 10),
                Text(l10n.adminUsersUnban),
              ],
            ),
          )
        else
          PopupMenuItem(
            value: 'ban',
            child: Row(
              children: [
                Icon(Icons.block, size: 18, color: scheme.error),
                const SizedBox(width: 10),
                Text(
                  l10n.adminUsersBan,
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'toggle_active',
          child: Text(
            row.user.isActive
                ? l10n.adminUsersDeactivate
                : l10n.adminUsersReactivate,
          ),
        ),
        PopupMenuItem(
          value: 'toggle_superadmin',
          child: Text(
            row.user.isSuperadmin
                ? l10n.adminUsersRevokeSuperadmin
                : l10n.adminUsersPromoteSuperadmin,
          ),
        ),
        PopupMenuItem(
          value: 'toggle_time_reports',
          child: Text(
            row.user.excludeFromTimeReports
                ? l10n.adminUsersIncludeTimeReports
                : l10n.adminUsersExcludeTimeReports,
          ),
        ),
        PopupMenuItem(
          value: 'reset',
          child: Text(l10n.adminUsersIssueReset),
        ),
        PopupMenuItem(value: 'time', child: Text(l10n.ttAdminTimeMenu)),
        PopupMenuItem(
          value: 'delete',
          child: Text(l10n.adminUsersDeleteMenu),
        ),
      ],
    );
  }
}

/// Confirmation for the 2FA reset, spelling out exactly what is removed.
///
/// This is destructive and cannot be undone by the admin — the user has to
/// re-enrol — so the dialog itemises the factors instead of asking a vague
/// "are you sure?".
class _ResetTwoFactorDialog extends StatelessWidget {
  const _ResetTwoFactorDialog({required this.row});

  final AdminUserRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tf = row.twoFactor;

    return AlertDialog(
      icon: const Icon(Icons.lock_reset),
      title: Text(l10n.adminUsersReset2faTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.adminUsersReset2faBody(row.email)),
          const SizedBox(height: 12),
          if (tf.totp)
            _BulletLine(icon: Icons.smartphone, text: l10n.adminUsers2faTotp),
          if (tf.passkeys > 0)
            _BulletLine(
              icon: Icons.key,
              text: l10n.adminUsers2faPasskeys(tf.passkeys),
            ),
          if (tf.recoveryCodesLeft > 0)
            _BulletLine(
              icon: Icons.confirmation_number_outlined,
              text: l10n.adminUsers2faRecoveryCodes(tf.recoveryCodesLeft),
            ),
          _BulletLine(
            icon: Icons.logout,
            text: l10n.adminUsersReset2faSignsOut,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.adminUsersReset2faWarning,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.adminUsersCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.adminUsersReset2faConfirm),
        ),
      ],
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Ban confirmation with an optional reason.
class _BanUserDialog extends StatefulWidget {
  const _BanUserDialog({required this.row});

  final AdminUserRow row;

  @override
  State<_BanUserDialog> createState() => _BanUserDialogState();
}

class _BanUserDialogState extends State<_BanUserDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.block, color: scheme.error),
      title: Text(l10n.adminUsersBanTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.adminUsersBanBody(widget.row.email)),
          const SizedBox(height: 8),
          // Worth stating: this is precisely what deactivation cannot do.
          Text(
            widget.row.user.isLdap
                ? l10n.adminUsersBanLdapNote
                : l10n.adminUsersBanNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: l10n.adminUsersBanReasonLabel,
              helperText: l10n.adminUsersBanReasonHelper,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminUsersCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(l10n.adminUsersBanConfirm),
        ),
      ],
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.cubit});
  final AdminUsersCubit cubit;
  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();
  bool _isSuperadmin = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _fullName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await widget.cubit.create(
      CreateUserRequest(
        email: _email.text.trim(),
        username: _username.text.trim(),
        fullName: _fullName.text.trim(),
        password: _password.text.isEmpty ? null : _password.text,
        isSuperadmin: _isSuperadmin,
      ),
    );
    if (!mounted) return;
    if (res == null) {
      final st = widget.cubit.state;
      final failure = st is AdminUsersLoaded ? st.lastError : null;
      setState(() {
        _busy = false;
        _error = _failureMessage(l10n, failure);
      });
      return;
    }
    Navigator.of(context).pop(res);
  }

  /// Turn a backend failure into a human-readable message. Validation failures
  /// surface the exact per-field reasons returned by the API instead of a
  /// generic catch-all line.
  String _failureMessage(AppLocalizations l10n, AppFailure? failure) {
    switch (failure) {
      case ValidationFailure(:final fieldErrors) when fieldErrors.isNotEmpty:
        return fieldErrors
            .map(
              (e) => '${_fieldLabel(l10n, e.field)}: ${e.message ?? 'invalid'}',
            )
            .join('\n');
      case ConflictFailure():
        return l10n.adminUsersErrConflict;
      case ForbiddenFailure():
        return l10n.adminUsersErrForbidden;
      case NetworkFailure():
        return l10n.adminUsersErrNetwork;
      case _:
        return l10n.adminUsersErrGeneric;
    }
  }

  String _fieldLabel(AppLocalizations l10n, String field) => switch (field) {
    'email' => l10n.adminUsersEmail,
    'username' => l10n.adminUsersUsername,
    'full_name' => l10n.adminUsersFullName,
    'password' => l10n.adminUsersPasswordField,
    _ => field,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminUsersCreateTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              decoration: InputDecoration(labelText: l10n.adminUsersEmail),
            ),
            TextField(
              controller: _username,
              decoration: InputDecoration(labelText: l10n.adminUsersUsername),
            ),
            TextField(
              controller: _fullName,
              decoration: InputDecoration(labelText: l10n.adminUsersFullName),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.adminUsersPasswordHint,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(l10n.adminUsersSuperadmin),
              value: _isSuperadmin,
              onChanged: (v) => setState(() => _isSuperadmin = v),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.adminUsersCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.adminUsersCreate),
        ),
      ],
    );
  }
}

class _TempCredentialDialog extends StatelessWidget {
  const _TempCredentialDialog({required this.email, required this.password});
  final String email;
  final String password;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminUsersTempPwTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.adminUsersTempPwBody(email)),
          const SizedBox(height: 12),
          SelectableText(l10n.adminUsersTempEmailLine(email)),
          SelectableText(l10n.adminUsersTempPasswordLine(password)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: password)));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.adminUsersPasswordCopied)),
            );
          },
          child: Text(l10n.adminUsersCopyPassword),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminUsersDone),
        ),
      ],
    );
  }
}

class _OneTimeTokenDialog extends StatelessWidget {
  const _OneTimeTokenDialog({
    required this.title,
    required this.subtitle,
    required this.token,
  });
  final String title;
  final String subtitle;
  final String token;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(subtitle),
          const SizedBox(height: 12),
          SelectableText(token),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: token)));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.adminUsersTokenCopied)),
            );
          },
          child: Text(l10n.adminUsersCopy),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminUsersDone),
        ),
      ],
    );
  }
}

/// Invite a new user by email (moved here from the former standalone admin
/// invitations page).
class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _email = TextEditingController();
  String _role = 'user';
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() => _busy = true);
    final res = await getIt<AdminRepository>().createInvitation(
      CreateInvitationRequest(email: email, role: _role),
    );
    if (!mounted) return;
    final created = res.valueOrNull;
    if (created == null) {
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminInviteCreateError)),
      );
      return;
    }
    navigator.pop();
    if (created.inviteToken != null) {
      await showDialog<void>(
        context: navigator.context,
        builder: (_) => _InviteLinkDialog(
          email: created.email,
          token: created.inviteToken!,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminInviteEmailedSnack(created.email))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminInviteTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.email_outlined),
                labelText: l10n.adminInviteEmailHint,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                DropdownMenuItem(
                  value: 'user',
                  child: Text(l10n.adminInviteRoleUser),
                ),
                DropdownMenuItem(
                  value: 'superadmin',
                  child: Text(l10n.adminInviteRoleSuperadmin),
                ),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'user'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.adminInviteButton),
        ),
      ],
    );
  }
}

class _InviteLinkDialog extends StatelessWidget {
  const _InviteLinkDialog({required this.email, required this.token});
  final String email;
  final String token;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final link = '${Uri.base.origin}/register?token=$token';
    return AlertDialog(
      title: Text(l10n.adminInviteCreatedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.adminInviteLinkInstructions(email)),
          const SizedBox(height: 12),
          SelectableText(link),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: link)));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.adminInviteLinkCopied)),
            );
          },
          child: Text(l10n.adminInviteCopyLink),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminInviteDone),
        ),
      ],
    );
  }
}
