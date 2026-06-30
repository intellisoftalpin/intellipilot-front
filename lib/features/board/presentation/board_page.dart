import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/core/widgets/members_scope.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/core/work_items/work_item_filter_bar.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_sheet.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/domain/board_config.dart';
import 'package:intellipilot/features/board/presentation/boards_nav_refresh.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_settings_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// A first-class kanban board, driven by its `config` (visible columns/order,
/// swimlane group, locked filters, column limit). Per-column counts + capped
/// cards come from `fetchBoardData`; "Load more" pages a single column.
class BoardPage extends StatelessWidget {
  const BoardPage({required this.projectId, required this.boardId, super.key});
  final String projectId;
  final String boardId;

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
            key: ValueKey(boardId),
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
              BlocProvider<TaskBoardCubit>(
                create: (_) {
                  final c = TaskBoardCubit(
                    repo: getIt<BacklogRepository>(),
                    catalog: getIt<CatalogRepository>(),
                    milestones: getIt<MilestonesRepository>(),
                    projectId: projectId,
                    boardId: boardId,
                  );
                  unawaited(c.load());
                  return c;
                },
              ),
            ],
            child: _BoardView(projectId: projectId, currentUserId: profile.id),
          ),
        );
      },
    );
  }
}

class _BoardView extends StatefulWidget {
  const _BoardView({required this.projectId, required this.currentUserId});
  final String projectId;
  final String currentUserId;

  @override
  State<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<_BoardView> {
  String? _selectedId;

  Future<void> _select(String id) async {
    setState(() => _selectedId = id);
    final cubit = context.read<TaskBoardCubit>();
    await showEntityDetailSheet(
      context,
      projectId: widget.projectId,
      kind: EntityKind.issue,
      entityId: id,
    );
    if (!mounted) return;
    setState(() => _selectedId = null);
    await cubit.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<TaskBoardCubit, TaskBoardState>(
          builder: (context, state) {
            final label = state is TaskBoardLoaded
                ? state.board.name
                : t.boardTitle;
            return ProjectSectionBreadcrumb(
              projectId: widget.projectId,
              currentLabel: label,
            );
          },
        ),
        actions: [
          const _BoardSearchField(),
          _BoardActionsMenu(
            projectId: widget.projectId,
            currentUserId: widget.currentUserId,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _TaskBoardBody(
        projectId: widget.projectId,
        selectedId: _selectedId,
        onSelect: _select,
      ),
    );
  }
}

/// Ad-hoc search box bound to the board's session-only filter.
class _BoardSearchField extends StatelessWidget {
  const _BoardSearchField();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<TaskBoardCubit, TaskBoardState>(
      builder: (context, state) {
        if (state is! TaskBoardLoaded) return const SizedBox.shrink();
        final cubit = context.read<TaskBoardCubit>();
        return SizedBox(
          width: 220,
          child: TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: t.issuesSearchHint,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
            ),
            onChanged: (v) =>
                cubit.setAdhocFilter(state.adhocFilter.copyWith(search: v)),
          ),
        );
      },
    );
  }
}

/// Edit / delete affordances, gated on shared-board permissions or personal
/// board ownership.
class _BoardActionsMenu extends StatelessWidget {
  const _BoardActionsMenu({
    required this.projectId,
    required this.currentUserId,
  });
  final String projectId;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<TaskBoardCubit, TaskBoardState>(
      builder: (context, state) {
        if (state is! TaskBoardLoaded) return const SizedBox.shrink();
        final detail = context.watch<ProjectDetailCubit>().state;
        final board = state.board;
        final isOwner = board.ownerId == currentUserId;
        bool can(Permission p) =>
            detail is ProjectDetailLoaded && detail.has(p);
        final canEdit = board.isShared
            ? can(Permission.boardSharedModify)
            : isOwner;
        final canDelete = board.isShared
            ? can(Permission.boardSharedDelete)
            : isOwner;
        if (!canEdit && !canDelete) return const SizedBox.shrink();
        return PopupMenuButton<String>(
          tooltip: t.boardActionsTooltip,
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            final cubit = context.read<TaskBoardCubit>();
            if (value == 'edit') {
              final updated = await showBoardSettingsDialog(
                context,
                projectId: projectId,
                board: board,
              );
              if (updated != null) {
                bumpBoardsNav();
                await cubit.load();
              }
            } else if (value == 'delete') {
              await _confirmDelete(context, board);
            }
          },
          itemBuilder: (ctx) => [
            if (canEdit)
              PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(t.boardEditTitle),
                ),
              ),
            if (canDelete)
              PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: Text(t.actionDelete),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Board board) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.boardDeleteTitle),
        content: Text(t.boardDeleteConfirm(board.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final res = await getIt<CatalogRepository>().deleteBoard(
      projectId,
      board.id,
    );
    if (!context.mounted) return;
    if (res.isErr) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.errUnknown)));
      return;
    }
    bumpBoardsNav();
    context.go(Routes.projectBoardFor(projectId));
  }
}

class _TaskBoardBody extends StatelessWidget {
  const _TaskBoardBody({
    required this.projectId,
    required this.selectedId,
    required this.onSelect,
  });
  final String projectId;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<TaskBoardCubit, TaskBoardState>(
      builder: (context, state) {
        if (state is TaskBoardLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is TaskBoardFailed) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.taskBoardLoadFailed),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => context.read<TaskBoardCubit>().load(),
                  child: Text(t.actionRetry),
                ),
              ],
            ),
          );
        }
        if (state is! TaskBoardLoaded) return const SizedBox.shrink();
        if (state.statuses.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt,
            title: t.taskBoardTitle,
            body: t.taskBoardNoStatuses,
          );
        }
        return _TasksLoaded(
          state: state,
          projectId: projectId,
          selectedId: selectedId,
          onSelect: onSelect,
        );
      },
    );
  }
}

class _TasksLoaded extends StatelessWidget {
  const _TasksLoaded({
    required this.state,
    required this.projectId,
    required this.selectedId,
    required this.onSelect,
  });
  final TaskBoardLoaded state;
  final String projectId;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final keyPrefix = detail is ProjectDetailLoaded
        ? detail.project.issuePrefix
        : '';
    final cubit = context.read<TaskBoardCubit>();
    return Column(
      children: [
        if (state.staleData)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.backlogStaleNotice)),
                ],
              ),
            ),
          ),
        WorkItemFilterBar(
          filter: state.effectiveFilter,
          onChanged: cubit.setAdhocFilter,
          statuses: state.statuses,
          types: state.types,
          priorities: state.priorities,
          sizes: state.sizes,
          epics: state.epics,
          milestones: state.milestones,
          labels: state.labels,
          components: state.components,
          showStatus: false,
          lockedDimensions: state.config.lockedDimensions,
          hiddenDimensions: {?state.group?.filterKey},
        ),
        Expanded(
          child: state.group == null
              ? _FlatBoard(
                  state: state,
                  projectId: projectId,
                  keyPrefix: keyPrefix,
                  selectedId: selectedId,
                  onSelect: onSelect,
                )
              : _Swimlanes(
                  state: state,
                  projectId: projectId,
                  keyPrefix: keyPrefix,
                  selectedId: selectedId,
                  onSelect: onSelect,
                ),
        ),
      ],
    );
  }
}

/// The flat single-board layout (no grouping).
class _FlatBoard extends StatelessWidget {
  const _FlatBoard({
    required this.state,
    required this.projectId,
    required this.keyPrefix,
    required this.selectedId,
    required this.onSelect,
  });
  final TaskBoardLoaded state;
  final String projectId;
  final String keyPrefix;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final s in state.statuses) s.id: s};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final col in state.flatColumns)
            _TaskColumn(
              state: state,
              column: col,
              status: col.statusId == null ? null : byId[col.statusId],
              laneKey: null,
              projectId: projectId,
              keyPrefix: keyPrefix,
              selectedId: selectedId,
              onSelect: onSelect,
            ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// The grouped (swimlane) layout: one horizontal board per lane.
class _Swimlanes extends StatelessWidget {
  const _Swimlanes({
    required this.state,
    required this.projectId,
    required this.keyPrefix,
    required this.selectedId,
    required this.onSelect,
  });
  final TaskBoardLoaded state;
  final String projectId;
  final String keyPrefix;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  String _resolveLane(BuildContext context, String key) {
    final group = state.group!;
    if (key == 'none') {
      final t = AppLocalizations.of(context);
      return switch (group) {
        BoardGroupBy.component => t.boardLaneNoComponent,
        BoardGroupBy.assignee => t.dashKpiUnassigned,
        BoardGroupBy.epic => t.backlogNoEpic,
        BoardGroupBy.priority => t.boardLaneNoPriority,
      };
    }
    switch (group) {
      case BoardGroupBy.component:
        return state.components.where((e) => e.id == key).firstOrNull?.name ??
            key;
      case BoardGroupBy.assignee:
        return MembersScope.user(context, key)?.displayName ?? key;
      case BoardGroupBy.epic:
        final e = state.epics.where((x) => x.id == key).firstOrNull;
        return e == null
            ? key
            : '${epicKeyLabel(keyPrefix, e.reference)} ${e.subject}';
      case BoardGroupBy.priority:
        return state.priorities.where((x) => x.id == key).firstOrNull?.name ??
            key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byId = {for (final s in state.statuses) s.id: s};
    if (state.lanes.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).boardEmptyColumn,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final lane in state.lanes) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  _resolveLane(context, lane.key).toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${lane.total}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 460,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final col in lane.columns)
                    _TaskColumn(
                      state: state,
                      column: col,
                      status: col.statusId == null ? null : byId[col.statusId],
                      laneKey: lane.key,
                      projectId: projectId,
                      keyPrefix: keyPrefix,
                      selectedId: selectedId,
                      onSelect: onSelect,
                    ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.state,
    required this.column,
    required this.status,
    required this.laneKey,
    required this.projectId,
    required this.keyPrefix,
    required this.selectedId,
    required this.onSelect,
  });

  final TaskBoardLoaded state;
  final BoardColumnData column;

  /// Null for the trailing "no status" column.
  final TaxonomyItem? status;
  final String? laneKey;
  final String projectId;
  final String keyPrefix;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        unawaited(
          context.read<TaskBoardCubit>().moveTask(
            taskId: details.data,
            targetStatusId: status?.id,
          ),
        );
      },
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Container(
          width: 280,
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: highlighted
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ColumnHeader(
                statusColor: status?.color ?? '',
                title: status?.name ?? t.boardColumnNoStatus,
                count: column.total,
              ),
              const Divider(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final card in column.cards)
                      _TaskCard(
                        state: state,
                        task: card,
                        projectId: projectId,
                        keyPrefix: keyPrefix,
                        selected: card.id == selectedId,
                        onTap: () => onSelect(card.id),
                      ),
                    if (column.cards.isEmpty)
                      _EmptyColumnNote(label: t.boardEmptyColumn),
                    if (column.hasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: TextButton.icon(
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: Text(
                            t.boardLoadMore(column.total - column.cards.length),
                          ),
                          onPressed: () =>
                              context.read<TaskBoardCubit>().loadMoreColumn(
                                laneKey: laneKey,
                                statusId: column.statusId,
                                offset: column.cards.length,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.state,
    required this.task,
    required this.projectId,
    required this.keyPrefix,
    required this.selected,
    required this.onTap,
  });
  final TaskBoardLoaded state;
  final Issue task;
  final String projectId;
  final String keyPrefix;
  final bool selected;
  final VoidCallback onTap;

  List<String> get _fields => state.config.cardFields ?? const ['assignee'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showAssignee = _fields.contains('assignee');
    final cardWidget = Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IssueKeyChip(text: issueKeyLabel(keyPrefix, task.reference)),
                  const Spacer(),
                  if (showAssignee &&
                      MembersScope.user(context, task.assignedTo) != null)
                    UserAvatar(
                      user: MembersScope.user(context, task.assignedTo)!,
                      size: 22,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                task.subject,
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              ..._buildMeta(context, theme),
            ],
          ),
        ),
      ),
    );
    return Draggable<String>(
      data: task.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: cardWidget,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: cardWidget),
      child: cardWidget,
    );
  }

  List<Widget> _buildMeta(BuildContext context, ThemeData theme) {
    final chips = <Widget>[];
    if (_fields.contains('priority') && task.priorityId != null) {
      final p = state.priorities
          .where((x) => x.id == task.priorityId)
          .firstOrNull;
      if (p != null) {
        chips.add(
          _MetaChip(
            color: p.color,
            label: p.emoji.isEmpty ? p.name : '${p.emoji} ${p.name}',
          ),
        );
      }
    }
    if (_fields.contains('size') && task.sizeId != null) {
      final s = state.sizes.where((x) => x.id == task.sizeId).firstOrNull;
      if (s != null) chips.add(_MetaChip(color: s.color, label: s.name));
    }
    if (_fields.contains('labels')) {
      for (final id in task.labels) {
        final l = state.labels.where((x) => x.id == id).firstOrNull;
        if (l != null) chips.add(_MetaChip(color: l.color, label: l.name));
      }
    }
    if (_fields.contains('due') && task.dueDate != null) {
      chips.add(
        _MetaChip(color: '', label: task.dueDate!, icon: Icons.event_outlined),
      );
    }

    final reporter = MembersScope.user(context, task.ownerId);
    return [
      if (chips.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
      if (reporter != null) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            const Spacer(),
            Tooltip(
              message:
                  '${AppLocalizations.of(context).detailFieldReporter}: '
                  '${reporter.displayName}',
              child: UserAvatar(user: reporter, size: 18),
            ),
          ],
        ),
      ],
    ];
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.color, required this.label, this.icon});
  final String color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ] else if (color.isNotEmpty) ...[
            HexColorDot(hex: color, size: 8),
            const SizedBox(width: 4),
          ],
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.statusColor,
    required this.title,
    required this.count,
  });

  final String statusColor;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        HexColorDot(hex: statusColor, size: 10),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyColumnNote extends StatelessWidget {
  const _EmptyColumnNote({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
