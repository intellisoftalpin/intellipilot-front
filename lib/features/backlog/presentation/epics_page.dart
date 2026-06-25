import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/core/widgets/members_scope.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_sheet.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/epics_cubit.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/epic_board_settings_dialog.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/epic_edit_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Project Epics: a flat list with full CRUD. Epics are a separate entity
/// from issues; this page is the dedicated place to create, edit and delete
/// them (the backlog now only filters by epic).
class EpicsPage extends StatelessWidget {
  const EpicsPage({required this.projectId, super.key});
  final String projectId;

  Future<(UserProfile?, Map<String, UserRef>)> _loadContext() async {
    final p = await getIt<ProfileRepository>().getProfile();
    final m = await getIt<ProjectsRepository>().listMembers(projectId);
    final map = {
      for (final mem in (m.valueOrNull ?? const <Membership>[]))
        mem.userId: mem.toRef(),
    };
    return (p.valueOrNull, map);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(UserProfile?, Map<String, UserRef>)>(
      future: _loadContext(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final (profile, members) =
            snap.data ?? (null, const <String, UserRef>{});
        if (profile == null) {
          return Scaffold(
            body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
          );
        }
        return MembersScope(
          membersById: members,
          child: MultiBlocProvider(
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
              BlocProvider<EpicsCubit>(
                create: (_) {
                  final c = EpicsCubit(
                    repo: getIt<BacklogRepository>(),
                    catalog: getIt<CatalogRepository>(),
                    milestones: getIt<MilestonesRepository>(),
                    projectId: projectId,
                  );
                  unawaited(c.load());
                  return c;
                },
              ),
            ],
            child: _EpicsView(projectId: projectId),
          ),
        );
      },
    );
  }
}

class _EpicsView extends StatelessWidget {
  const _EpicsView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: ProjectSectionBreadcrumb(
                projectId: projectId,
                currentLabel: t.railEpics,
              ),
            ),
            const SizedBox(width: 8),
            BlocBuilder<EpicsCubit, EpicsState>(
              builder: (context, state) => state is EpicsLoaded
                  ? _CountBadge(count: state.visibleEpics.length)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [_BoardSettingsAction(projectId: projectId)],
      ),
      floatingActionButton: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, detail) {
          if (detail is! ProjectDetailLoaded ||
              !detail.has(Permission.epicCreate)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewEpic),
            onPressed: () => _create(context),
          );
        },
      ),
      body: BlocBuilder<EpicsCubit, EpicsState>(
        builder: (context, state) {
          if (state is EpicsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is EpicsFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.epicsLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<EpicsCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is! EpicsLoaded) return const SizedBox.shrink();
          return _Loaded(state: state);
        },
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<EpicsCubit>();
    final result = await showEpicEditDialog(context);
    if (result == null) return;
    final created = await cubit.createEpic(result);
    if (created == null || !context.mounted) return;
    // Drop the user straight into the sidebar to fill in the rest.
    await showEntityDetailSheet(
      context,
      projectId: created.projectId,
      kind: EntityKind.epic,
      entityId: created.id,
    );
    await cubit.load();
  }
}

/// Gear in the app bar (project-modify only) that opens the board column →
/// status mapping and persists it on the project.
class _BoardSettingsAction extends StatelessWidget {
  const _BoardSettingsAction({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    if (detail is! ProjectDetailLoaded ||
        !detail.has(Permission.projectModify)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.tune),
      tooltip: t.epicBoardSettingsTooltip,
      onPressed: () => _open(context, detail),
    );
  }

  Future<void> _open(BuildContext context, ProjectDetailLoaded detail) async {
    final epicsCubit = context.read<EpicsCubit>();
    final projectCubit = context.read<ProjectDetailCubit>();
    final s = epicsCubit.state;
    if (s is! EpicsLoaded) return;
    final result = await showEpicBoardSettingsDialog(
      context,
      statuses: s.statuses,
      inProgressIds: detail.project.epicBoard.inProgressStatusIds,
    );
    if (result == null) return;
    final res = await getIt<ProjectsRepository>().updateProject(
      projectId,
      UpdateProjectRequest(
        epicBoard: EpicBoardSettings(inProgressStatusIds: result),
      ),
    );
    if (res.isOk) {
      await projectCubit.load();
      await epicsCubit.load();
    }
  }
}

/// Split the visible epics into the three board columns. "Done" = any closed
/// status; "In Progress" = a status mapped in the board settings; "All" = the
/// remainder (no status, or one in neither bucket). Each column keeps `order`.
({List<Epic> all, List<Epic> inProgress, List<Epic> done}) _bucketEpics(
  List<Epic> epics,
  List<TaxonomyItem> statuses,
  Set<String> inProgressIds,
) {
  final closedIds = <String>{
    for (final s in statuses)
      if (s.isClosed ?? false) s.id,
  };
  final all = <Epic>[];
  final inProgress = <Epic>[];
  final done = <Epic>[];
  for (final e in epics) {
    final sid = e.statusId;
    if (sid != null && closedIds.contains(sid)) {
      done.add(e);
    } else if (sid != null && inProgressIds.contains(sid)) {
      inProgress.add(e);
    } else {
      all.add(e);
    }
  }
  for (final list in [all, inProgress, done]) {
    list.sort((a, b) => a.order.compareTo(b.order));
  }
  return (all: all, inProgress: inProgress, done: done);
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});
  final EpicsLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final loaded = detail is ProjectDetailLoaded ? detail : null;
    final canDrag = loaded?.has(Permission.epicModify) ?? false;
    final inProgressIds =
        loaded?.project.epicBoard.inProgressStatusIds.toSet() ??
        const <String>{};

    if (state.epics.isEmpty) {
      return EmptyState(
        icon: Icons.bookmarks_outlined,
        title: t.railEpics,
        body: t.epicsEmpty,
      );
    }

    final buckets = _bucketEpics(
      state.visibleEpics,
      state.statuses,
      inProgressIds,
    );
    // The status a card takes when dropped into each column. "All" clears the
    // status; "In Progress" uses the first mapped status; "Done" uses the first
    // closed status.
    final inProgressTarget = state.statuses
        .where((s) => inProgressIds.contains(s.id) && !(s.isClosed ?? false))
        .map((s) => s.id)
        .firstOrNull;
    final doneTarget = state.statuses
        .where((s) => s.isClosed ?? false)
        .map((s) => s.id)
        .firstOrNull;
    final columns = <({String title, List<Epic> epics, Object? target})>[
      (title: t.epicsColAll, epics: buckets.all, target: null),
      (
        title: t.epicsColInProgress,
        epics: buckets.inProgress,
        target: inProgressTarget,
      ),
      (title: t.epicsColDone, epics: buckets.done, target: doneTarget),
    ];

    return Column(
      children: [
        if (state.milestones.isNotEmpty)
          _MilestoneFilter(
            milestones: state.milestones,
            selected: state.milestoneFilter,
            onChanged: (id) =>
                context.read<EpicsCubit>().setMilestoneFilter(id),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final col in columns)
                  Expanded(
                    child: _EpicColumn(
                      title: col.title,
                      epics: col.epics,
                      statuses: state.statuses,
                      targetStatusId: col.target,
                      canDrag: canDrag,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Apply a board drop: figure out the dragged epic's new position within the
/// target column (insert before [beforeCardId], or append when null) and hand
/// the resulting neighbours + target status to the cubit.
void _handleEpicDrop(
  BuildContext context, {
  required String draggedId,
  required List<Epic> columnEpics,
  required String? beforeCardId,
  required Object? targetStatusId,
}) {
  if (draggedId == beforeCardId) return;
  final cubit = context.read<EpicsCubit>();
  final s = cubit.state;
  if (s is! EpicsLoaded) return;
  final epic = s.epics.where((e) => e.id == draggedId).firstOrNull;
  if (epic == null) return;
  final list = List.of(columnEpics)..removeWhere((e) => e.id == draggedId);
  final idx = beforeCardId == null
      ? list.length
      : () {
          final p = list.indexWhere((e) => e.id == beforeCardId);
          return p < 0 ? list.length : p;
        }();
  list.insert(idx, epic);
  String? beforeId;
  String? afterId;
  if (idx > 0) afterId = list[idx - 1].id;
  if (idx < list.length - 1) beforeId = list[idx + 1].id;
  unawaited(
    cubit.dropEpic(
      epic: epic,
      newStatusId: targetStatusId,
      beforeId: beforeId,
      afterId: afterId,
    ),
  );
}

class _MilestoneFilter extends StatelessWidget {
  const _MilestoneFilter({
    required this.milestones,
    required this.selected,
    required this.onChanged,
  });
  final List<Milestone> milestones;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            DropdownButton<String?>(
              value: selected,
              hint: Text(t.epicsFilterMilestoneLabel),
              items: [
                DropdownMenuItem<String?>(
                  child: Text(t.epicsFilterAllMilestones),
                ),
                for (final m in milestones)
                  DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
              ],
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: AppLocalizations.of(context).epicsCountTooltip(count),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$count',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EpicColumn extends StatelessWidget {
  const _EpicColumn({
    required this.title,
    required this.epics,
    required this.statuses,
    required this.targetStatusId,
    required this.canDrag,
  });
  final String title;
  final List<Epic> epics;
  final List<TaxonomyItem> statuses;

  /// Status a card adopts when dropped here (null = clear, for "All").
  final Object? targetStatusId;
  final bool canDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget box(bool highlighted) => Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: highlighted
            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(width: 6),
                Text(
                  '${epics.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 12),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [for (final e in epics) _card(context, e)],
            ),
          ),
        ],
      ),
    );
    if (!canDrag) return box(false);
    // Column-level target: dropping in empty space appends to the end.
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _handleEpicDrop(
        context,
        draggedId: d.data,
        columnEpics: epics,
        beforeCardId: null,
        targetStatusId: targetStatusId,
      ),
      builder: (context, cand, rej) => box(cand.isNotEmpty),
    );
  }

  Widget _card(BuildContext context, Epic e) {
    final card = _EpicCard(epic: e, statuses: statuses);
    if (!canDrag) return card;
    final theme = Theme.of(context);
    // Per-card target: dropping onto a card inserts the dragged epic before it.
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != e.id,
      onAcceptWithDetails: (d) => _handleEpicDrop(
        context,
        draggedId: d.data,
        columnEpics: epics,
        beforeCardId: e.id,
        targetStatusId: targetStatusId,
      ),
      builder: (context, cand, rej) => Container(
        decoration: cand.isEmpty
            ? null
            : BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.primary, width: 2),
                ),
              ),
        child: Draggable<String>(
          data: e.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: card,
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: card),
          child: card,
        ),
      ),
    );
  }
}

class _EpicCard extends StatelessWidget {
  const _EpicCard({required this.epic, required this.statuses});
  final Epic epic;
  final List<TaxonomyItem> statuses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = statuses
        .where((s) => s.id == epic.statusId)
        .cast<TaxonomyItem?>()
        .firstOrNull;
    final assignee = MembersScope.user(context, epic.assignedTo);
    final progress = epic.taskTotal == 0
        ? 0.0
        : epic.taskClosed / epic.taskTotal;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (epic.hasCover) _EpicCover(epic: epic),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!epic.hasCover) ...[
                        HexColorDot(hex: epic.color, size: 12),
                        const SizedBox(width: 6),
                      ],
                      IssueKeyChip(text: 'EPIC-${epic.reference}'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    epic.subject,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (status != null)
                        Flexible(
                          child: StatusPill(
                            label: status.name,
                            colorHex: status.color,
                            dense: true,
                          ),
                        ),
                      const Spacer(),
                      _TaskCountChip(total: epic.taskTotal),
                      if (assignee != null) ...[
                        const SizedBox(width: 6),
                        UserAvatar(user: assignee, size: 22),
                      ],
                    ],
                  ),
                  if (epic.taskTotal > 0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${epic.taskClosed}/${epic.taskTotal}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    final cubit = context.read<EpicsCubit>();
    await showEntityDetailSheet(
      context,
      projectId: epic.projectId,
      kind: EntityKind.epic,
      entityId: epic.id,
    );
    await cubit.load();
  }
}

class _TaskCountChip extends StatelessWidget {
  const _TaskCountChip({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.format_list_bulleted,
          size: 14,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: 3),
        Text(
          '$total',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

/// Authenticated cover image served from the backend (mirrors [UserAvatar]).
class _EpicCover extends StatelessWidget {
  const _EpicCover({required this.epic});
  final Epic epic;

  @override
  Widget build(BuildContext context) {
    final base = getIt<ApiConfig>().baseUrl;
    final token = getIt<SessionBloc>().currentAccessToken;
    final v = Uri.encodeQueryComponent(epic.coverImageUpdatedAt ?? '');
    final url =
        '$base/api/v1/projects/${epic.projectId}/epics/${epic.id}/cover-image?v=$v';
    return Image.network(
      url,
      height: 96,
      width: double.infinity,
      fit: BoxFit.cover,
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
