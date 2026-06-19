import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_users_cubit.dart';
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
          Expanded(
            child: BlocBuilder<AdminUsersCubit, AdminUsersState>(
              builder: (context, state) => switch (state) {
                AdminUsersLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
                AdminUsersFailed(:final failure) => Center(
                  child: Text(l10n.adminUsersLoadFailed(failure.debugLabel)),
                ),
                AdminUsersLoaded(:final items, :final total, :final lastError) =>
                  _UsersList(
                    items: items,
                    total: total,
                    lastError: lastError,
                    onPatch: (u, patch) => cubit.patch(u.id, patch),
                    onDelete: (u) => _confirmDelete(u, cubit),
                    onResetPassword: (u) => _resetPasswordFlow(u, cubit),
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

  Future<void> _confirmDelete(UserProfile u, AdminUsersCubit cubit) async {
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

  Future<void> _resetPasswordFlow(UserProfile u, AdminUsersCubit cubit) async {
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

class _UsersList extends StatelessWidget {
  const _UsersList({
    required this.items,
    required this.total,
    required this.onPatch,
    required this.onDelete,
    required this.onResetPassword,
    this.lastError,
  });

  final List<UserProfile> items;
  final int total;
  final Object? lastError;
  final Future<UserProfile?> Function(UserProfile, UpdateUserRequest) onPatch;
  final void Function(UserProfile) onDelete;
  final void Function(UserProfile) onResetPassword;

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
            itemBuilder: (_, i) => _UserTile(
              user: items[i],
              onToggleActive: (v) =>
                  onPatch(items[i], UpdateUserRequest(isActive: v)),
              onToggleSuperadmin: (v) =>
                  onPatch(items[i], UpdateUserRequest(isSuperadmin: v)),
              onDelete: () => onDelete(items[i]),
              onResetPassword: () => onResetPassword(items[i]),
            ),
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemCount: items.length,
          ),
        ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.onToggleActive,
    required this.onToggleSuperadmin,
    required this.onDelete,
    required this.onResetPassword,
  });

  final UserProfile user;
  final ValueChanged<bool> onToggleActive;
  final ValueChanged<bool> onToggleSuperadmin;
  final VoidCallback onDelete;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(user.email)),
          if (user.isSuperadmin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Chip(label: Text(l10n.adminUsersChipSuperadmin)),
            ),
          if (!user.isActive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Chip(label: Text(l10n.adminUsersChipInactive)),
            ),
          if (user.mustChangePassword)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Chip(label: Text(l10n.adminUsersChipTempPw)),
            ),
        ],
      ),
      subtitle: Text('${user.username} · ${user.fullName}'),
      trailing: PopupMenuButton<String>(
        onSelected: (key) {
          switch (key) {
            case 'toggle_active':
              onToggleActive(!user.isActive);
            case 'toggle_superadmin':
              onToggleSuperadmin(!user.isSuperadmin);
            case 'reset':
              onResetPassword();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'toggle_active',
            child: Text(
              user.isActive
                  ? l10n.adminUsersDeactivate
                  : l10n.adminUsersReactivate,
            ),
          ),
          PopupMenuItem(
            value: 'toggle_superadmin',
            child: Text(
              user.isSuperadmin
                  ? l10n.adminUsersRevokeSuperadmin
                  : l10n.adminUsersPromoteSuperadmin,
            ),
          ),
          PopupMenuItem(
            value: 'reset',
            child: Text(l10n.adminUsersIssueReset),
          ),
          PopupMenuItem(value: 'delete', child: Text(l10n.adminUsersDeleteMenu)),
        ],
      ),
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
              (e) =>
                  '${_fieldLabel(l10n, e.field)}: ${e.message ?? 'invalid'}',
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
