import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/component_releases_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/component_repositories_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/components_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/repositories_tab.dart'
    show failureText;
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class ComponentsTab extends StatelessWidget {
  const ComponentsTab({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ComponentsCubit>(
      create: (_) {
        final c = ComponentsCubit(
          repo: getIt<CatalogRepository>(),
          projectId: projectId,
        );
        unawaited(c.load());
        return c;
      },
      child: const _ComponentsView(),
    );
  }
}

class _ComponentsView extends StatelessWidget {
  const _ComponentsView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit =
        detail is ProjectDetailLoaded &&
        detail.hasAny(const [
          Permission.componentCreate,
          Permission.componentModify,
          Permission.componentDelete,
        ]);

    return BlocBuilder<ComponentsCubit, ComponentsState>(
      builder: (context, state) {
        if (state is ComponentsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ComponentsLoadFailed) {
          return Center(child: Text(t.componentsLoadFailed));
        }
        if (state is! ComponentsLoaded) return const SizedBox.shrink();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canEdit)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showEditDialog(context, null),
                  label: Text(t.actionNewComponent),
                ),
              ),
            const SizedBox(height: 8),
            if (state.components.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t.componentsEmpty, textAlign: TextAlign.center),
              )
            else
              for (final component in state.components)
                Card(
                  child: ListTile(
                    leading: HexColorDot(hex: component.color, size: 18),
                    title: Text(component.name),
                    subtitle: Text(component.color),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.account_tree_outlined),
                          tooltip: 'Linked repositories & releases',
                          onPressed: () => _showLinksDialog(
                            context,
                            component,
                            canEdit: canEdit,
                          ),
                        ),
                        if (canEdit) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: t.actionEdit,
                            onPressed: () =>
                                _showEditDialog(context, component),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: t.actionDelete,
                            onPressed: () => _confirmDelete(context, component),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    Component? existing,
  ) async {
    final t = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var color = (existing?.color.isNotEmpty ?? false)
        ? existing!.color
        : ColorPalette.swatches.first;
    final cubit = context.read<ComponentsCubit>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null ? t.actionNewComponent : t.actionEditComponent,
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(labelText: t.fieldName),
                ),
                const SizedBox(height: 12),
                Text(t.fieldColor),
                const SizedBox(height: 4),
                ColorSwatchPicker(
                  selectedHex: color,
                  onChanged: (h) => setState(() => color = h),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.actionCancel),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                if (existing == null) {
                  await cubit.create(name: name, color: color);
                } else {
                  await cubit.update(existing.id, name: name, color: color);
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(t.actionSave),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Component component) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.componentDeleteTitle),
        content: Text(t.componentDeleteConfirm(component.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if ((ok ?? false) && context.mounted) {
      await context.read<ComponentsCubit>().delete(component.id);
    }
  }

  Future<void> _showLinksDialog(
    BuildContext context,
    Component component, {
    required bool canEdit,
  }) async {
    final projectId = context.read<ComponentsCubit>().projectId;
    await showDialog<void>(
      context: context,
      builder: (_) => _ComponentLinksDialog(
        projectId: projectId,
        component: component,
        canEdit: canEdit,
      ),
    );
  }
}

/// Dialog managing the repositories linked to a single component.
class _ComponentLinksDialog extends StatelessWidget {
  const _ComponentLinksDialog({
    required this.projectId,
    required this.component,
    required this.canEdit,
  });

  final String projectId;
  final Component component;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final repo = getIt<CatalogRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<ComponentReposCubit>(
          create: (_) {
            final c = ComponentReposCubit(
              repo: repo,
              projectId: projectId,
              componentId: component.id,
            );
            unawaited(c.load());
            return c;
          },
        ),
        BlocProvider<ComponentReleasesCubit>(
          create: (_) {
            final c = ComponentReleasesCubit(
              repo: repo,
              projectId: projectId,
              componentId: component.id,
            );
            unawaited(c.load());
            return c;
          },
        ),
      ],
      child: _ComponentLinksView(
        projectId: projectId,
        component: component,
        canEdit: canEdit,
      ),
    );
  }
}

class _ComponentLinksView extends StatefulWidget {
  const _ComponentLinksView({
    required this.projectId,
    required this.component,
    required this.canEdit,
  });

  final String projectId;
  final Component component;
  final bool canEdit;

  @override
  State<_ComponentLinksView> createState() => _ComponentLinksViewState();
}

class _ComponentLinksViewState extends State<_ComponentLinksView> {
  late Future<List<Repository>> _repos;

  @override
  void initState() {
    super.initState();
    _repos = getIt<CatalogRepository>()
        .listRepositories(widget.projectId)
        .then((r) => r.valueOrNull ?? <Repository>[]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Links — ${widget.component.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Repositories', style: theme.textTheme.titleSmall),
              BlocBuilder<ComponentReposCubit, ComponentReposState>(
                builder: (context, state) {
                  if (state is ComponentReposLoading) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (state is ComponentReposLoadFailed) {
                    return Text(failureText(state.failure));
                  }
                  if (state is! ComponentReposLoaded) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.links.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('No repositories linked yet.'),
                        )
                      else
                        for (final link in state.links)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.commit_outlined),
                            title: Text(link.repositoryName),
                            subtitle: Text(
                              '${link.sshUrl}\nBranch: ${link.branch}',
                            ),
                            isThreeLine: true,
                            trailing: widget.canEdit
                                ? Wrap(
                                    spacing: 4,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: 'Change branch',
                                        onPressed: () =>
                                            _editBranch(context, link),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.link_off),
                                        tooltip: 'Unlink',
                                        onPressed: () => context
                                            .read<ComponentReposCubit>()
                                            .unlink(link.repositoryId),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                      if (state.lastError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            failureText(state.lastError!),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      if (widget.canEdit)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add_link, size: 18),
                            label: const Text('Link repository'),
                            onPressed: () => _addLink(context),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Divider(height: 24),
              Text('Releases', style: theme.textTheme.titleSmall),
              BlocBuilder<ComponentReleasesCubit, ComponentReleasesState>(
                builder: (context, state) {
                  if (state is ComponentReleasesLoading) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (state is ComponentReleasesLoadFailed) {
                    return Text(failureText(state.failure));
                  }
                  if (state is! ComponentReleasesLoaded) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.links.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('No releases linked yet.'),
                        )
                      else
                        for (final link in state.links)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.rocket_launch_outlined),
                            title: Text(link.releaseName),
                            trailing: widget.canEdit
                                ? IconButton(
                                    icon: const Icon(Icons.link_off),
                                    tooltip: 'Unlink',
                                    onPressed: () => context
                                        .read<ComponentReleasesCubit>()
                                        .unlink(link.releaseId),
                                  )
                                : null,
                          ),
                      if (state.lastError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            failureText(state.lastError!),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      if (widget.canEdit)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add_link, size: 18),
                            label: const Text('Link release'),
                            onPressed: () => _addRelease(context),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _addRelease(BuildContext context) async {
    final cubit = context.read<ComponentReleasesCubit>();
    final releases =
        (await getIt<CatalogRepository>().listReleases(
          widget.projectId,
        )).valueOrNull ??
        const [];
    if (!context.mounted) return;
    final linkedIds = (cubit.state is ComponentReleasesLoaded)
        ? (cubit.state as ComponentReleasesLoaded).links
              .map((l) => l.releaseId)
              .toSet()
        : <String>{};
    final available = releases.where((r) => !linkedIds.contains(r.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more releases to link.')),
      );
      return;
    }
    var releaseId = available.first.id;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Link release'),
          content: SizedBox(
            width: 420,
            child: DropdownButtonFormField<String>(
              initialValue: releaseId,
              decoration: const InputDecoration(labelText: 'Release'),
              items: [
                for (final r in available)
                  DropdownMenuItem<String>(value: r.id, child: Text(r.name)),
              ],
              onChanged: (v) => setState(() => releaseId = v ?? releaseId),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(releaseId),
              child: const Text('Link'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) await cubit.link(picked);
  }

  Future<void> _editBranch(
    BuildContext context,
    ComponentRepositoryLink link,
  ) async {
    final cubit = context.read<ComponentReposCubit>();
    final ctrl = TextEditingController(text: link.branch);
    final branch = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change branch'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Branch'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (branch != null && branch.isNotEmpty) {
      await cubit.updateBranch(link.repositoryId, branch);
    }
  }

  Future<void> _addLink(BuildContext context) async {
    final cubit = context.read<ComponentReposCubit>();
    final repos = await _repos;
    if (!context.mounted) return;
    final linkedIds = (cubit.state is ComponentReposLoaded)
        ? (cubit.state as ComponentReposLoaded).links
              .map((l) => l.repositoryId)
              .toSet()
        : <String>{};
    final available = repos.where((r) => !linkedIds.contains(r.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more repositories to link.')),
      );
      return;
    }

    String? repoId = available.first.id;
    final branchCtrl = TextEditingController();
    var fetched = <String>[];
    var fetching = false;

    final result = await showDialog<({String repoId, String branch})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final selected = available.firstWhere((r) => r.id == repoId);
          return AlertDialog(
            title: const Text('Link repository'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: repoId,
                    decoration: const InputDecoration(labelText: 'Repository'),
                    items: [
                      for (final r in available)
                        DropdownMenuItem<String>(
                          value: r.id,
                          child: Text(r.name),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      repoId = v;
                      fetched = [];
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: branchCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Branch',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: (fetching || !selected.hasKey)
                            ? null
                            : () async {
                                setState(() => fetching = true);
                                final res = await getIt<CatalogRepository>()
                                    .repositoryBranches(
                                      widget.projectId,
                                      selected.id,
                                    );
                                if (!ctx.mounted) return;
                                res.when(
                                  ok: (b) => setState(() {
                                    fetched = b.branches;
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
                  if (fetched.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final b in fetched)
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
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final branch = branchCtrl.text.trim();
                  if (repoId == null || branch.isEmpty) return;
                  Navigator.of(ctx).pop((repoId: repoId!, branch: branch));
                },
                child: const Text('Link'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      await cubit.link(result.repoId, result.branch);
    }
  }
}
