import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_invitations_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class AdminInvitationsPage extends StatelessWidget {
  const AdminInvitationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminInvitationsCubit>(
      create: (_) {
        final c = AdminInvitationsCubit(getIt<AdminRepository>());
        unawaited(c.load());
        return c;
      },
      child: const _InvitationsView(),
    );
  }
}

class _InvitationsView extends StatefulWidget {
  const _InvitationsView();
  @override
  State<_InvitationsView> createState() => _InvitationsViewState();
}

class _InvitationsViewState extends State<_InvitationsView> {
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
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() => _busy = true);
    final created = await context.read<AdminInvitationsCubit>().create(
      email,
      _role,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminInviteCreateError)),
      );
      return;
    }
    _email.clear();
    if (created.inviteToken != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => _InviteLinkDialog(
          email: created.email,
          token: created.inviteToken!,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminInviteEmailedSnack(created.email))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminInviteTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _email,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.email_outlined),
                      hintText: l10n.adminInviteEmailHint,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _role,
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
                const SizedBox(width: 12),
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
            ),
          ),
          Expanded(
            child: BlocBuilder<AdminInvitationsCubit, AdminInvitationsState>(
              builder: (context, state) => switch (state) {
                AdminInvitationsLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
                AdminInvitationsFailed(:final failure) => Center(
                  child: Text(l10n.adminInviteLoadFailed(failure.debugLabel)),
                ),
                AdminInvitationsLoaded(:final items) => items.isEmpty
                    ? Center(child: Text(l10n.adminInviteEmpty))
                    : ListView.separated(
                        itemBuilder: (_, i) => ListTile(
                          title: Text(items[i].email),
                          subtitle: Text(
                            l10n.adminInviteRoleExpires(
                              items[i].role,
                              items[i].expiresAt.toLocal().toString(),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: l10n.adminInviteRevoke,
                            onPressed: () => context
                                .read<AdminInvitationsCubit>()
                                .revoke(items[i].id),
                          ),
                        ),
                        separatorBuilder: (_, _) => const Divider(height: 0),
                        itemCount: items.length,
                      ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteLinkDialog extends StatelessWidget {
  const _InviteLinkDialog({required this.email, required this.token});
  final String email;
  final String token;

  String _link(BuildContext context) {
    final origin = Uri.base.origin;
    return '$origin/register?token=$token';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final link = _link(context);
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
