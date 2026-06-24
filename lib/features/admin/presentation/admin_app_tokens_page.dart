import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/admin/data/dtos/app_token_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_app_tokens_cubit.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Permissions a token may carry — the backend's 35 (the frontend `us.*` /
/// `task.*` are UI-only placeholders the API would reject).
final List<Permission> _tokenPermissions = Permission.values
    .where(
      (p) =>
          p.domain != PermissionDomain.userStories &&
          p.domain != PermissionDomain.tasks,
    )
    .toList();

class AdminAppTokensPage extends StatelessWidget {
  const AdminAppTokensPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminAppTokensCubit>(
      create: (_) {
        final c = AdminAppTokensCubit(
          getIt<AdminRepository>(),
          getIt<ProjectsRepository>(),
        );
        unawaited(c.load());
        return c;
      },
      child: const _View(),
    );
  }
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.adminAppTokensTitle)),
      floatingActionButton: BlocBuilder<AdminAppTokensCubit, AdminAppTokensState>(
        builder: (context, state) {
          if (state is! AdminAppTokensLoaded) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.appTokenNew),
            onPressed: () => _openCreate(context, state.projects),
          );
        },
      ),
      body: BlocBuilder<AdminAppTokensCubit, AdminAppTokensState>(
        builder: (context, state) {
          if (state is AdminAppTokensLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AdminAppTokensFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.appTokenLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<AdminAppTokensCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is! AdminAppTokensLoaded) return const SizedBox.shrink();
          if (state.tokens.isEmpty) {
            return EmptyState(
              icon: Icons.key_outlined,
              title: t.adminAppTokensTitle,
              body: t.appTokenEmpty,
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: state.tokens.length,
                itemBuilder: (context, i) =>
                    _TokenRow(token: state.tokens[i], state: state),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCreate(BuildContext context, List<Project> projects) async {
    final cubit = context.read<AdminAppTokensCubit>();
    final req = await showDialog<CreateAppTokenRequest>(
      context: context,
      builder: (_) => _TokenDialog(projects: projects),
    );
    if (req == null || !context.mounted) return;
    final result = await cubit.create(req);
    if (result != null && context.mounted) {
      await _showSecret(context, result);
    }
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({required this.token, required this.state});
  final AppTokenDto token;
  final AdminAppTokensLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = switch (token) {
      _ when token.isRevoked => (t.appTokenRevoked, theme.colorScheme.error),
      _ when token.isExpired => (t.appTokenExpired, Colors.orange),
      _ => (t.appTokenActive, Colors.green),
    };
    final projectNames =
        token.projectIds.map(state.projectName).toList()..sort();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.key_outlined),
        title: Row(
          children: [
            Expanded(child: Text(token.name)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusLabel,
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              token.masked,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 2),
            Text(t.appTokenPermsCount(token.permissions.length)),
            Text(
              projectNames.isEmpty ? '—' : projectNames.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        trailing: token.isRevoked
            ? null
            : PopupMenuButton<String>(
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(t.appTokenEdit)),
                  PopupMenuItem(value: 'revoke', child: Text(t.appTokenRevoke)),
                ],
                onSelected: (v) => _onMenu(context, v),
              ),
        isThreeLine: true,
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String v) async {
    final cubit = context.read<AdminAppTokensCubit>();
    final t = AppLocalizations.of(context);
    if (v == 'edit') {
      final patch = await showDialog<UpdateAppTokenRequest>(
        context: context,
        builder: (_) => _TokenDialog(projects: state.projects, existing: token),
      );
      if (patch != null) await cubit.update(token.id, patch);
    } else if (v == 'revoke') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.appTokenRevoke),
          content: Text(t.appTokenRevokeConfirm(token.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.actionCancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.appTokenRevoke),
            ),
          ],
        ),
      );
      if ((ok ?? false) && context.mounted) await cubit.revoke(token.id);
    }
  }
}

/// Shows the one-time raw secret with a copy button.
Future<void> _showSecret(BuildContext context, CreateAppTokenResult r) {
  final t = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(t.appTokenSecretTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.appTokenSecretWarning),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              r.secret,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text(t.appTokenCopy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: r.secret));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(t.appTokenCopied)),
              );
            }
          },
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(t.actionDone),
        ),
      ],
    ),
  );
}

/// Create/edit form. Returns a [CreateAppTokenRequest] (create mode) or an
/// [UpdateAppTokenRequest] (edit mode) via Navigator.pop.
class _TokenDialog extends StatefulWidget {
  const _TokenDialog({required this.projects, this.existing});
  final List<Project> projects;
  final AppTokenDto? existing;

  @override
  State<_TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<_TokenDialog> {
  late final TextEditingController _name;
  late Set<String> _projectIds;
  late Set<Permission> _permissions;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _projectIds = {...?e?.projectIds};
    _permissions = {...?e?.permissions};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (_isEdit) {
      Navigator.of(context).pop(
        UpdateAppTokenRequest(
          name: name,
          permissions: _permissions,
          projectIds: _projectIds.toList(),
        ),
      );
    } else {
      Navigator.of(context).pop(
        CreateAppTokenRequest(
          name: name,
          permissions: _permissions,
          projectIds: _projectIds.toList(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_isEdit ? t.appTokenEdit : t.appTokenNew),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: t.appTokenName,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Text(t.appTokenProjects,
                  style: Theme.of(context).textTheme.titleSmall),
              if (widget.projects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('—', style: Theme.of(context).textTheme.bodySmall),
                )
              else
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in widget.projects)
                      FilterChip(
                        label: Text(p.name),
                        selected: _projectIds.contains(p.id),
                        onSelected: (on) => setState(() {
                          if (on) {
                            _projectIds.add(p.id);
                          } else {
                            _projectIds.remove(p.id);
                          }
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Text(t.appTokenPermissions,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              _PermissionPicker(
                selected: _permissions,
                onChanged: (s) => setState(() => _permissions = s),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEdit ? t.appTokenSave : t.appTokenCreate),
        ),
      ],
    );
  }
}

/// Permission checkboxes grouped by domain (token-safe subset).
class _PermissionPicker extends StatelessWidget {
  const _PermissionPicker({required this.selected, required this.onChanged});
  final Set<Permission> selected;
  final ValueChanged<Set<Permission>> onChanged;

  void _toggle(Permission p, bool on) {
    final next = Set<Permission>.from(selected);
    if (on) {
      next.add(p);
    } else {
      next.remove(p);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final byDomain = <PermissionDomain, List<Permission>>{};
    for (final p in _tokenPermissions) {
      byDomain.putIfAbsent(p.domain, () => []).add(p);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => onChanged(
                  _tokenPermissions.where((p) => p.wire.endsWith('.view')).toSet(),
                ),
                child: Text(t.rolePresetReader),
              ),
              OutlinedButton(
                onPressed: () => onChanged(_tokenPermissions.toSet()),
                child: Text(t.rolePresetAdmin),
              ),
              OutlinedButton(
                onPressed: () => onChanged(const {}),
                child: Text(t.appTokenClear),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in byDomain.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _domainLabel(t, entry.key),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in entry.value)
                      SizedBox(
                        width: 220,
                        child: CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(p.wire),
                          value: selected.contains(p),
                          onChanged: (v) => _toggle(p, v ?? false),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _domainLabel(AppLocalizations t, PermissionDomain d) => switch (d) {
    PermissionDomain.project => t.permDomainProject,
    PermissionDomain.members => t.permDomainMembers,
    PermissionDomain.roles => t.permDomainRoles,
    PermissionDomain.epics => t.permDomainEpics,
    PermissionDomain.userStories => t.permDomainUserStories,
    PermissionDomain.tasks => t.permDomainTasks,
    PermissionDomain.issues => t.permDomainIssues,
    PermissionDomain.milestones => t.permDomainMilestones,
    PermissionDomain.wiki => t.permDomainWiki,
    PermissionDomain.commentsAndAttachments => t.permDomainCommentsAttachments,
    PermissionDomain.timeTracking => t.ttTimeTracking,
  };
}
