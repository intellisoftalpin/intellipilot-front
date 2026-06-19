import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/backlog_cubit.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/bulk_paste_dialog.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/epic_edit_dialog.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/user_story_edit_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/size_badge.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class BacklogPage extends StatelessWidget {
  const BacklogPage({required this.projectId, super.key});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: getIt<ProfileRepository>().getProfile().then(
        (r) => r.valueOrNull,
      ),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) {
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).errUnknown),
            ),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider<ProjectDetailCubit>(
              create: (_) {
                final c = ProjectDetailCubit(
                  repo: getIt<ProjectsRepository>(),
                  projectId: projectId,
                  currentUserId: profile.id,
                );
                unawaited(c.load());
                return c;
              },
            ),
            BlocProvider<BacklogCubit>(
              create: (_) {
                final c = BacklogCubit(
                  repo: getIt<BacklogRepository>(),
                  catalog: getIt<CatalogRepository>(),
                  projectId: projectId,
                );
                unawaited(c.load());
                return c;
              },
            ),
          ],
          child: _BacklogView(projectId: projectId),
        );
      },
    );
  }
}

class _BacklogView extends StatelessWidget {
  const _BacklogView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: projectId,
          currentLabel: t.backlogTitle,
        ),
      ),
      floatingActionButton:
          BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, detail) {
          if (detail is! ProjectDetailLoaded ||
              !detail.has(Permission.usCreate)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewUserStory),
            onPressed: () => _newUserStory(context),
          );
        },
      ),
      body: BlocBuilder<BacklogCubit, BacklogState>(
        builder: (context, state) {
          if (state is BacklogLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is BacklogLoadFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.backlogLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () =>
                        context.read<BacklogCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is BacklogLoaded) {
            return _Loaded(state: state, projectId: projectId);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _newUserStory(BuildContext context) async {
    final cubit = context.read<BacklogCubit>();
    final s = cubit.state;
    if (s is! BacklogLoaded) return;
    final result = await showBacklogIssueDialog(
      context,
      epics: s.epics,
      statuses: s.statuses,
      types: s.types,
      points: s.points,
    );
    if (result == null) return;
    await cubit.createIssue(result);
  }
}

class _Loaded extends StatefulWidget {
  const _Loaded({required this.state, required this.projectId});
  final BacklogLoaded state;
  final String projectId;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.state.search;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEditUs =
        detail is ProjectDetailLoaded && detail.has(Permission.usModify);
    final canEditEpic =
        detail is ProjectDetailLoaded && detail.has(Permission.epicModify);
    final canCreateEpic =
        detail is ProjectDetailLoaded && detail.has(Permission.epicCreate);
    final canCreateUs =
        detail is ProjectDetailLoaded && detail.has(Permission.usCreate);

    final groups = widget.state.grouped;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          children: [
            if (widget.state.staleData)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t.backlogStaleNotice)),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: t.backlogSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    context.read<BacklogCubit>().setSearch(v),
              ),
            ),
            SizedBox(
              height: 44,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(t.filterAllStatuses),
                      selected: widget.state.statusFilter == null,
                      onSelected: (_) =>
                          context.read<BacklogCubit>().setStatusFilter(null),
                    ),
                    const SizedBox(width: 8),
                    for (final s in widget.state.statuses) ...[
                      FilterChip(
                        avatar: HexColorDot(hex: s.color, size: 12),
                        label: Text(s.name),
                        selected: widget.state.statusFilter == s.id,
                        onSelected: (_) => context
                            .read<BacklogCubit>()
                            .setStatusFilter(s.id),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const SizedBox(width: 8),
                    if (canCreateEpic)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        onPressed: () => _newEpic(context),
                        label: Text(t.actionNewEpic),
                      ),
                    const SizedBox(width: 8),
                    if (canCreateUs)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => _bulkAdd(context),
                        label: Text(t.actionBulkAdd),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final epic in widget.state.epics)
                    _EpicSection(
                      epic: epic,
                      stories: groups[epic.id] ?? const [],
                      statuses: widget.state.statuses,
                      points: widget.state.points,
                      canEditUs: canEditUs,
                      canEditEpic: canEditEpic,
                      canCreateUs: canCreateUs,
                    ),
                  if ((groups[null] ?? const []).isNotEmpty)
                    _EpicSection(
                      epic: null,
                      stories: groups[null]!,
                      statuses: widget.state.statuses,
                      points: widget.state.points,
                      canEditUs: canEditUs,
                      canEditEpic: false,
                      canCreateUs: canCreateUs,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newEpic(BuildContext context) async {
    final cubit = context.read<BacklogCubit>();
    final s = cubit.state;
    if (s is! BacklogLoaded) return;
    final result = await showEpicEditDialog(context);
    if (result == null) return;
    await cubit.createEpic(result);
  }

  Future<void> _bulkAdd(BuildContext context) async {
    final cubit = context.read<BacklogCubit>();
    final s = cubit.state;
    if (s is! BacklogLoaded) return;
    final picked = await showBulkPasteDialog(context, epics: s.epics);
    if (picked == null || picked.subjects.isEmpty) return;
    await cubit.bulkCreateIssues(
      picked.subjects,
      epicId: picked.epicId,
    );
  }
}

class _EpicSection extends StatelessWidget {
  const _EpicSection({
    required this.epic,
    required this.stories,
    required this.statuses,
    required this.points,
    required this.canEditUs,
    required this.canEditEpic,
    required this.canCreateUs,
  });

  final Epic? epic;
  final List<Issue> stories;
  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> points;
  final bool canEditUs;
  final bool canEditEpic;
  final bool canCreateUs;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DragTarget<String>(
      // Reject drags whose source is already in this epic — `moveToEpic` is
      // a no-op then, but suppressing the highlight is the honest signal.
      onWillAcceptWithDetails: (details) {
        if (!canEditUs) return false;
        final cubit = context.read<BacklogCubit>();
        final s = cubit.state;
        if (s is! BacklogLoaded) return false;
        final src = s.issues
            .where((u) => u.id == details.data)
            .cast<Issue?>()
            .firstOrNull;
        return src != null && src.epicId != epic?.id;
      },
      onAcceptWithDetails: (details) {
        unawaited(
          context.read<BacklogCubit>().moveIssueToEpic(
            details.data,
            epic?.id,
          ),
        );
      },
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
            color: highlighted
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : null,
          ),
          child: _buildCard(context, t),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, AppLocalizations t) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: epic == null
            ? const Icon(Icons.folder_open_outlined)
            : HexColorDot(hex: epic!.color, size: 18),
        title: epic == null
            ? Text(t.backlogNoEpicGroup)
            : Row(
                children: [
                  IssueKeyChip(text: 'EPIC-${epic!.reference}'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(epic!.subject, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
        subtitle: Text(
          '${stories.length} ${t.backlogStoryCountSuffix}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        trailing: canEditEpic && epic != null
            ? PopupMenuButton<String>(
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'open', child: Text(t.actionOpenDetail)),
                  PopupMenuItem(value: 'edit', child: Text(t.actionEdit)),
                  PopupMenuItem(value: 'delete', child: Text(t.actionDelete)),
                ],
                onSelected: (v) async {
                  if (v == 'open') {
                    context.go(
                      Routes.entityDetailFor(
                        epic!.projectId,
                        EntityKind.epic,
                        epic!.id,
                      ),
                    );
                  } else if (v == 'edit') {
                    final updated =
                        await showEpicEditDialog(context, existing: epic);
                    if (updated == null || !context.mounted) return;
                    await context.read<BacklogCubit>().updateEpic(
                      epic!.id,
                      UpdateEpicRequest(
                        subject: updated.subject,
                        description: updated.description,
                        color: updated.color,
                      ),
                    );
                  } else if (v == 'delete') {
                    final ok = await _confirm(
                      context,
                      title: t.backlogDeleteEpicTitle,
                      body: t.backlogDeleteEpicConfirm(epic!.subject),
                    );
                    if ((ok ?? false) && context.mounted) {
                      await context.read<BacklogCubit>().deleteEpic(epic!.id);
                    }
                  }
                },
              )
            : null,
        children: [
          for (final us in stories)
            _UserStoryRow(
              story: us,
              statuses: statuses,
              points: points,
              canEdit: canEditUs,
            ),
        ],
      ),
    );
  }
}

class _UserStoryRow extends StatelessWidget {
  const _UserStoryRow({
    required this.story,
    required this.statuses,
    required this.points,
    required this.canEdit,
  });
  final Issue story;
  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> points;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status =
        statuses.where((s) => s.id == story.statusId).cast<TaxonomyItem?>().firstOrNull;
    final p = points
        .where((p) => p.id == story.sizeId)
        .cast<TaxonomyItem?>()
        .firstOrNull;
    final tile = ListTile(
      leading: IssueKeyChip(text: 'US-${story.reference}'),
      title: Text(story.subject),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (status != null)
            StatusPill(
              label: status.name,
              colorHex: status.color,
              dense: true,
            ),
          if (p != null) SizeBadge(item: p),
        ],
      ),
      onTap: () => context.go(
        Routes.entityDetailFor(
          story.projectId,
          EntityKind.issue,
          story.id,
        ),
      ),
      trailing: canEdit
          ? Wrap(
              spacing: 4,
              children: [
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  tooltip: t.actionOpenDetail,
                  onPressed: () => context.go(
                    Routes.entityDetailFor(
                      story.projectId,
                      EntityKind.issue,
                      story.id,
                    ),
                  ),
                ),
                _StatusMenu(story: story, statuses: statuses),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: t.actionEdit,
                  onPressed: () async {
                    final cubit = context.read<BacklogCubit>();
                    final s = cubit.state;
                    if (s is! BacklogLoaded) return;
                    final updated = await showBacklogIssueDialog(
                      context,
                      epics: s.epics,
                      statuses: s.statuses,
                      types: s.types,
                      points: s.points,
                      existing: story,
                    );
                    if (updated == null || !context.mounted) return;
                    await cubit.updateIssue(
                      story.id,
                      UpdateIssueRequest(
                        subject: updated.subject,
                        description: updated.description,
                        statusId: updated.statusId,
                        epicId: updated.epicId,
                        sizeId: updated.sizeId,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: t.actionDelete,
                  onPressed: () async {
                    final ok = await _confirm(
                      context,
                      title: t.backlogDeleteUsTitle,
                      body: t.backlogDeleteUsConfirm(story.subject),
                    );
                    if ((ok ?? false) && context.mounted) {
                      await context
                          .read<BacklogCubit>()
                          .deleteIssue(story.id);
                    }
                  },
                ),
              ],
            )
          : null,
    );
    if (!canEdit) return tile;
    final feedback = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IssueKeyChip(text: 'US-${story.reference}'),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  story.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Draggable<String>(
      data: story.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.story, required this.statuses});
  final Issue story;
  final List<TaxonomyItem> statuses;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PopupMenuButton<String?>(
      tooltip: t.backlogChangeStatus,
      icon: const Icon(Icons.flag_outlined),
      itemBuilder: (_) => [
        PopupMenuItem<String?>(
          value: null,
          child: Text(t.backlogClearStatus),
        ),
        ...statuses.map(
          (s) => PopupMenuItem<String?>(
            value: s.id,
            child: Row(
              children: [
                HexColorDot(hex: s.color, size: 10),
                const SizedBox(width: 8),
                Text(s.name),
              ],
            ),
          ),
        ),
      ],
      onSelected: (v) =>
          context.read<BacklogCubit>().setIssueStatus(story.id, v),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final t = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
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
}
