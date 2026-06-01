import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_invitations_cubit.dart';

class AdminInvitationsPage extends StatelessWidget {
  const AdminInvitationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminInvitationsCubit>(
      create: (_) =>
          AdminInvitationsCubit(getIt<AdminRepository>())..load(),
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
        const SnackBar(content: Text('Could not create invitation')),
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
        SnackBar(content: Text('Invitation emailed to ${created.email}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invitations')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _email,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.email_outlined),
                      hintText: 'Email to invite',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _role,
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('user')),
                    DropdownMenuItem(
                      value: 'superadmin',
                      child: Text('superadmin'),
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
                      : const Text('Invite'),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocBuilder<AdminInvitationsCubit, AdminInvitationsState>(
              builder: (context, state) => switch (state) {
                AdminInvitationsLoading() =>
                  const Center(child: CircularProgressIndicator()),
                AdminInvitationsFailed(:final failure) => Center(
                  child: Text('Failed: ${failure.debugLabel}'),
                ),
                AdminInvitationsLoaded(:final items) => items.isEmpty
                    ? const Center(child: Text('No pending invitations'))
                    : ListView.separated(
                        itemBuilder: (_, i) => ListTile(
                          title: Text(items[i].email),
                          subtitle: Text(
                            'role: ${items[i].role} · expires '
                            '${items[i].expiresAt.toLocal()}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Revoke',
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
    final link = _link(context);
    return AlertDialog(
      title: const Text('Invitation created'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Send this link to $email. They must register using exactly that '
            'email address for the token to be accepted.',
          ),
          const SizedBox(height: 12),
          SelectableText(link),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Link copied')),
            );
          },
          child: const Text('Copy link'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
