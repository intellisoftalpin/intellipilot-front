import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/releases_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/repositories_tab.dart'
    show failureText;
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';

const _statusOptions = <String>['planned', 'in_progress', 'released'];

/// Project-settings tab managing releases and their versions. Each version
/// carries an optional repository + git tag.
class ReleasesTab extends StatelessWidget {
  const ReleasesTab({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReleasesCubit>(
      create: (_) {
        final c = ReleasesCubit(
          repo: getIt<CatalogRepository>(),
          projectId: projectId,
        );
        unawaited(c.load());
        return c;
      },
      child: _ReleasesView(projectId: projectId),
    );
  }
}

class _ReleasesView extends StatelessWidget {
  const _ReleasesView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit =
        detail is ProjectDetailLoaded && detail.has(Permission.projectModify);
    return BlocBuilder<ReleasesCubit, ReleasesState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text(
                  'Releases',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (canEdit)
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('New release'),
                    onPressed: () => _showReleaseDialog(context, null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (state is ReleasesLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state is ReleasesLoadFailed)
              Text(failureText(state.failure))
            else if (state is ReleasesLoaded)
              if (state.releases.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No releases yet.'),
                )
              else
                for (final r in state.releases)
                  _ReleaseCard(
                    release: r,
                    projectId: projectId,
                    canEdit: canEdit,
                    versions: state.versionsByRelease[r.id],
                  ),
          ],
        );
      },
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.projectId,
    required this.canEdit,
    required this.versions,
  });
  final Release release;
  final String projectId;
  final bool canEdit;
  final List<ReleaseVersion>? versions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.rocket_launch_outlined),
        title: Text(release.name),
        subtitle:
            (release.description != null && release.description!.isNotEmpty)
            ? Text(release.description!)
            : null,
        onExpansionChanged: (open) {
          if (open) {
            unawaited(context.read<ReleasesCubit>().loadVersions(release.id));
          }
        },
        children: [
          if (canEdit)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit release'),
                    onPressed: () => _showReleaseDialog(context, release),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    onPressed: () => _confirmDeleteRelease(context, release),
                  ),
                ],
              ),
            ),
          if (versions == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            if (versions!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No versions yet.'),
              )
            else
              for (final v in versions!)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.label_outline),
                  title: Text(v.version),
                  subtitle: Text(
                    [
                      'Status: ${v.status}',
                      if (v.gitTag != null && v.gitTag!.isNotEmpty)
                        'Tag: ${v.gitTag}',
                      if (v.targetDate != null) 'Target: ${v.targetDate}',
                    ].join(' · '),
                  ),
                  trailing: canEdit
                      ? Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit version',
                              onPressed: () => _showVersionDialog(
                                context,
                                release.id,
                                v,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete version',
                              onPressed: () => context
                                  .read<ReleasesCubit>()
                                  .deleteVersion(release.id, v.id),
                            ),
                          ],
                        )
                      : null,
                ),
            if (canEdit)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add version'),
                    onPressed: () =>
                        _showVersionDialog(context, release.id, null),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

Future<void> _confirmDeleteRelease(
  BuildContext context,
  Release release,
) async {
  final cubit = context.read<ReleasesCubit>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete release'),
      content: Text(
        'Delete "${release.name}"? All its versions and component links are '
        'removed.',
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
    await cubit.delete(release.id);
  }
}

Future<void> _showReleaseDialog(BuildContext context, Release? existing) async {
  final cubit = context.read<ReleasesCubit>();
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final descCtrl = TextEditingController(text: existing?.description ?? '');

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'New release' : 'Edit release'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. PSBP',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
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
            if (name.isEmpty) return;
            final desc = descCtrl.text.trim();
            final ok = existing == null
                ? await cubit.create(
                    CreateReleaseRequest(
                      name: name,
                      description: desc.isEmpty ? null : desc,
                    ),
                  )
                : await cubit.update(
                    existing.id,
                    UpdateReleaseRequest(name: name, description: desc),
                  );
            if (!ctx.mounted) return;
            if (ok) {
              Navigator.of(ctx).pop();
            } else {
              final s = cubit.state;
              if (s is ReleasesLoaded && s.lastError != null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(failureText(s.lastError!))),
                );
              }
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<void> _showVersionDialog(
  BuildContext context,
  String releaseId,
  ReleaseVersion? existing,
) async {
  final cubit = context.read<ReleasesCubit>();
  final projectId = cubit.projectId;
  final versionCtrl = TextEditingController(text: existing?.version ?? '');
  final tagCtrl = TextEditingController(text: existing?.gitTag ?? '');
  final notesCtrl = TextEditingController(text: existing?.notes ?? '');
  final targetCtrl = TextEditingController(text: existing?.targetDate ?? '');
  var status = existing?.status ?? 'planned';
  var repoId = existing?.repositoryId;

  // Repositories for the optional per-version link.
  final repos =
      (await getIt<CatalogRepository>().listRepositories(
        projectId,
      )).valueOrNull ??
      const [];
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'New version' : 'Edit version'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: versionCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Version',
                    hintText: 'e.g. 1.0',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in _statusOptions)
                      DropdownMenuItem<String>(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() => status = v ?? status),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: targetCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target date',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: repoId,
                  decoration: const InputDecoration(labelText: 'Repository'),
                  items: [
                    const DropdownMenuItem<String?>(
                      child: Text('— None —'),
                    ),
                    for (final r in repos)
                      DropdownMenuItem<String?>(
                        value: r.id,
                        child: Text(r.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => repoId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagCtrl,
                  decoration: const InputDecoration(labelText: 'Git tag'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
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
              final version = versionCtrl.text.trim();
              if (version.isEmpty) return;
              final tag = tagCtrl.text.trim();
              final target = targetCtrl.text.trim();
              final notes = notesCtrl.text.trim();
              final ok = existing == null
                  ? await cubit.createVersion(
                      releaseId,
                      CreateReleaseVersionRequest(
                        version: version,
                        status: status,
                        targetDate: target.isEmpty ? null : target,
                        notes: notes.isEmpty ? null : notes,
                        repositoryId: repoId,
                        gitTag: tag.isEmpty ? null : tag,
                      ),
                    )
                  : await cubit.updateVersion(
                      releaseId,
                      existing.id,
                      UpdateReleaseVersionRequest(
                        version: version,
                        status: status,
                        targetDate: target.isEmpty ? null : target,
                        notes: notes,
                        repositoryId: repoId,
                        gitTag: tag.isEmpty ? null : tag,
                      ),
                    );
              if (!ctx.mounted) return;
              if (ok) {
                Navigator.of(ctx).pop();
              } else {
                final s = cubit.state;
                if (s is ReleasesLoaded && s.lastError != null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(failureText(s.lastError!))),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
