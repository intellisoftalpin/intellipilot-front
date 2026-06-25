import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/repositories_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/ssh_keys_cubit.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';

String failureText(AppFailure f) =>
    f.problem?.detail ?? f.problem?.title ?? 'Something went wrong';

/// Project-settings tab hosting the SSH credential vault and the project's
/// git repositories.
class RepositoriesTab extends StatelessWidget {
  const RepositoriesTab({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final repo = getIt<CatalogRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<SshKeysCubit>(
          create: (_) {
            final c = SshKeysCubit(repo: repo, projectId: projectId);
            unawaited(c.load());
            return c;
          },
        ),
        BlocProvider<RepositoriesCubit>(
          create: (_) {
            final c = RepositoriesCubit(repo: repo, projectId: projectId);
            unawaited(c.load());
            return c;
          },
        ),
      ],
      child: const _RepositoriesView(),
    );
  }
}

class _RepositoriesView extends StatelessWidget {
  const _RepositoriesView();

  @override
  Widget build(BuildContext context) {
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit =
        detail is ProjectDetailLoaded &&
        detail.hasAny(const [
          Permission.repositoryCreate,
          Permission.repositoryModify,
          Permission.repositoryDelete,
        ]);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SshKeysSection(canEdit: canEdit),
        const SizedBox(height: 24),
        _RepositoriesSection(canEdit: canEdit),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SSH keys
// ---------------------------------------------------------------------------

class _SshKeysSection extends StatelessWidget {
  const _SshKeysSection({required this.canEdit});
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshKeysCubit, SshKeysState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('SSH keys', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (canEdit)
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('New key'),
                    onPressed: () => _showKeyDialog(context, null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (state is SshKeysLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state is SshKeysLoadFailed)
              Text(failureText(state.failure))
            else if (state is SshKeysLoaded)
              if (state.keys.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No SSH keys yet. Generate one to access a repository.',
                  ),
                )
              else
                for (final key in state.keys)
                  _SshKeyCard(keyItem: key, canEdit: canEdit),
          ],
        );
      },
    );
  }
}

class _SshKeyCard extends StatelessWidget {
  const _SshKeyCard({required this.keyItem, required this.canEdit});
  final SshKey keyItem;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.vpn_key_outlined),
        title: Row(
          children: [
            Flexible(child: Text(keyItem.name)),
            const SizedBox(width: 8),
            Chip(
              label: Text(keyItem.readOnly ? 'read-only' : 'read/write'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        subtitle: Text(
          '${keyItem.fingerprint}\n'
          'Used by ${keyItem.usedByRepoCount} '
          '${keyItem.usedByRepoCount == 1 ? "repository" : "repositories"}',
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copy public key',
              onPressed: () => _copyPublicKey(context, keyItem),
            ),
            if (canEdit) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () => _showKeyDialog(context, keyItem),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _confirmDeleteKey(context, keyItem),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _copyPublicKey(BuildContext context, SshKey key) async {
  await Clipboard.setData(ClipboardData(text: key.publicKey));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Public key copied to clipboard')),
    );
  }
}

Future<void> _showKeyDialog(BuildContext context, SshKey? existing) async {
  final cubit = context.read<SshKeysCubit>();
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  var readOnly = existing?.readOnly ?? true;

  final created = await showDialog<SshKey?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'New SSH key' : 'Edit SSH key'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Read-only'),
                subtitle: const Text(
                  'Register as a read-only deploy key (recommended)',
                ),
                value: readOnly,
                onChanged: (v) => setState(() => readOnly = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              if (existing == null) {
                final key = await cubit.create(name: name, readOnly: readOnly);
                if (ctx.mounted) Navigator.of(ctx).pop(key);
              } else {
                await cubit.update(
                  existing.id,
                  name: name,
                  readOnly: readOnly,
                );
                if (ctx.mounted) Navigator.of(ctx).pop(null);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  // On generate, surface the public key so it can be registered on the host.
  if (created != null && context.mounted) {
    await _showKeyCreatedDialog(context, created);
  }
}

Future<void> _showKeyCreatedDialog(BuildContext context, SshKey key) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Deploy key generated'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add this public key as a deploy key on your git host. The '
              'private key never leaves the server.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              key.publicKey,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              key.fingerprint,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _copyPublicKey(ctx, key),
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

Future<void> _confirmDeleteKey(BuildContext context, SshKey key) async {
  final cubit = context.read<SshKeysCubit>();
  final inUse = key.usedByRepoCount > 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete SSH key'),
      content: Text(
        inUse
            ? 'This key is used by ${key.usedByRepoCount} repositories. '
                  'Deleting it will detach it from them — those repositories '
                  'will need a new key assigned before they can be reached.'
            : 'Delete the key "${key.name}"?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if ((ok ?? false) && context.mounted) {
    await cubit.delete(key.id);
  }
}

// ---------------------------------------------------------------------------
// Repositories
// ---------------------------------------------------------------------------

class _RepositoriesSection extends StatelessWidget {
  const _RepositoriesSection({required this.canEdit});
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RepositoriesCubit, RepositoriesState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Repositories',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (canEdit)
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add repository'),
                    onPressed: () => _showRepoDialog(context, null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (state is RepositoriesLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state is RepositoriesLoadFailed)
              Text(failureText(state.failure))
            else if (state is RepositoriesLoaded)
              if (state.repositories.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No repositories yet.'),
                )
              else
                for (final repo in state.repositories)
                  _RepositoryCard(repo: repo, canEdit: canEdit),
          ],
        );
      },
    );
  }
}

class _RepositoryCard extends StatelessWidget {
  const _RepositoryCard({required this.repo, required this.canEdit});
  final Repository repo;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final keyName = _keyNameFor(context, repo.sshKeyId);
    return Card(
      child: ListTile(
        leading: Icon(
          repo.hasKey ? Icons.cloud_outlined : Icons.cloud_off_outlined,
          color: repo.hasKey ? null : Theme.of(context).colorScheme.error,
        ),
        title: Text(repo.name),
        subtitle: Text(
          [
            repo.sshUrl,
            if (repo.hasKey) 'Key: $keyName' else '⚠ No key assigned',
            if (repo.defaultBranch != null) 'Default: ${repo.defaultBranch}',
            if (repo.hostFingerprint != null) 'Host: ${repo.hostFingerprint}',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: canEdit
            ? Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                    onPressed: () => _showRepoDialog(context, repo),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDeleteRepo(context, repo),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

String _keyNameFor(BuildContext context, String? keyId) {
  if (keyId == null) return '';
  final s = context.read<SshKeysCubit>().state;
  if (s is SshKeysLoaded) {
    for (final k in s.keys) {
      if (k.id == keyId) return k.name;
    }
  }
  return keyId;
}

Future<void> _confirmDeleteRepo(BuildContext context, Repository repo) async {
  final cubit = context.read<RepositoriesCubit>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete repository'),
      content: Text(
        'Delete "${repo.name}"? It will be unlinked from any components.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if ((ok ?? false) && context.mounted) {
    await cubit.delete(repo.id);
  }
}

/// Create/edit a repository. Supports picking an existing key or creating a
/// new one inline, plus fetching branches to choose the default branch.
Future<void> _showRepoDialog(BuildContext context, Repository? existing) async {
  final repoCubit = context.read<RepositoriesCubit>();
  final keysState = context.read<SshKeysCubit>().state;
  final keys = keysState is SshKeysLoaded ? keysState.keys : <SshKey>[];

  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final urlCtrl = TextEditingController(text: existing?.sshUrl ?? '');
  final branchCtrl = TextEditingController(text: existing?.defaultBranch ?? '');
  final newKeyNameCtrl = TextEditingController();

  // Key selection: an existing key id, or the sentinel '__new__'.
  const newKeySentinel = '__new__';
  var selectedKey = existing?.sshKeyId;
  var newKeyReadOnly = true;
  var fetchedBranches = <String>[];
  var fetching = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final creatingNewKey = selectedKey == newKeySentinel;
        return AlertDialog(
          title: Text(existing == null ? 'Add repository' : 'Edit repository'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SSH URL',
                      hintText: 'git@github.com:org/repo.git',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedKey,
                    decoration: const InputDecoration(labelText: 'SSH key'),
                    items: [
                      const DropdownMenuItem<String?>(
                        child: Text('— No key —'),
                      ),
                      for (final k in keys)
                        DropdownMenuItem<String?>(
                          value: k.id,
                          child: Text(
                            '${k.name} (${k.readOnly ? "ro" : "rw"})',
                          ),
                        ),
                      const DropdownMenuItem<String?>(
                        value: newKeySentinel,
                        child: Text('+ Create new key…'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      selectedKey = v;
                      fetchedBranches = [];
                    }),
                  ),
                  if (creatingNewKey) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: newKeyNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'New key name',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Read-only'),
                      value: newKeyReadOnly,
                      onChanged: (v) => setState(() => newKeyReadOnly = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: branchCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Default branch',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Branch fetch needs an EXISTING key already registered.
                      TextButton(
                        onPressed:
                            (fetching ||
                                selectedKey == null ||
                                creatingNewKey ||
                                urlCtrl.text.trim().isEmpty)
                            ? null
                            : () async {
                                setState(() => fetching = true);
                                final res = await repoCubit.previewBranches(
                                  urlCtrl.text.trim(),
                                  selectedKey!,
                                );
                                if (!ctx.mounted) return;
                                res.when(
                                  ok: (b) => setState(() {
                                    fetchedBranches = b.branches;
                                    fetching = false;
                                    if (branchCtrl.text.isEmpty &&
                                        b.defaultBranch != null) {
                                      branchCtrl.text = b.defaultBranch!;
                                    }
                                  }),
                                  err: (f) {
                                    setState(() => fetching = false);
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text(failureText(f))),
                                    );
                                  },
                                );
                              },
                        child: fetching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Fetch branches'),
                      ),
                    ],
                  ),
                  if (fetchedBranches.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final b in fetchedBranches)
                          ActionChip(
                            label: Text(b),
                            onPressed: () =>
                                setState(() => branchCtrl.text = b),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final url = urlCtrl.text.trim();
                if (name.isEmpty || url.isEmpty) return;
                final branch = branchCtrl.text.trim();
                final ok = existing == null
                    ? await repoCubit.create(
                        CreateRepositoryRequest(
                          name: name,
                          sshUrl: url,
                          sshKeyId: creatingNewKey ? null : selectedKey,
                          newKey: creatingNewKey
                              ? CreateSshKeyRequest(
                                  name: newKeyNameCtrl.text.trim().isEmpty
                                      ? '$name-key'
                                      : newKeyNameCtrl.text.trim(),
                                  readOnly: newKeyReadOnly,
                                )
                              : null,
                          defaultBranch: branch.isEmpty ? null : branch,
                        ),
                      )
                    : await repoCubit.update(
                        existing.id,
                        UpdateRepositoryRequest(
                          name: name,
                          sshUrl: url,
                          sshKeyId: creatingNewKey
                              ? existing.sshKeyId
                              : selectedKey,
                          defaultBranch: branch.isEmpty ? null : branch,
                        ),
                      );
                if (!ctx.mounted) return;
                if (ok) {
                  // Refresh keys too (an inline key may have been created).
                  await context.read<SshKeysCubit>().load();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  final s = repoCubit.state;
                  if (s is RepositoriesLoaded && s.lastError != null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(failureText(s.lastError!))),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
