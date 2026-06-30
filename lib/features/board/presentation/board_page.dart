import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/core/widgets/members_scope.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/core/work_items/work_item_filter_bar.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_sheet.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_columns_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Project-wide Kanban: every issue grouped into columns by `issue_status`.
/// The board needs no milestone to render — sprints are an optional filter.
class BoardPage extends StatelessWidget {
  const BoardPage({required this.projectId, super.key});
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
              BlocProvider<TaskBoardCubit>(
                create: (_) {
                  final c = TaskBoardCubit(
                    repo: getIt<BacklogRepository>(),
                    catalog: getIt<CatalogRepository>(),
                    milestones: getIt<MilestonesRepository>(),
                    filterStore: WorkItemFilterStore(
                      getIt<KeyValueStorage>(instanceName: HiveBoxes.ui),
                    ),
                    projectId: projectId,
                  );
                  unawaited(c.load());
                  return c;
                },
              ),
            ],
            child: _BoardView(projectId: projectId),
          ),
        );
      },
    );
  }
}

class _BoardView extends StatefulWidget {
  const _BoardView({required this.projectId});
  final String projectId;

  @override
  State<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<_BoardView> {
  /// The card a user clicked on. When non-null the right-side details panel
  /// shows the entity; the card itself renders with a primary outline.
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
    await cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: widget.projectId,
          currentLabel: t.boardTitle,
        ),
        actions: const [
          _BoardToolbar(),
          SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: _TaskBoardBody(
              projectId: widget.projectId,
              selectedId: _selectedId,
              onSelect: _select,
            ),
          ),
        ],
      ),
    );
  }
}

/// App-bar controls: search box, swimlane grouping, saved-views menu, and the
/// column-settings button. All other filters live in the shared
/// [WorkItemFilterBar] below the bar (identical to the Issues list).
class _BoardToolbar extends StatelessWidget {
  const _BoardToolbar();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<TaskBoardCubit, TaskBoardState>(
      builder: (context, state) {
        if (state is! TaskBoardLoaded) return const SizedBox.shrink();
        final cubit = context.read<TaskBoardCubit>();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
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
                    cubit.setFilter(state.filter.copyWith(search: v)),
              ),
            ),
            const SizedBox(width: 8),
            _GroupByMenu(groupBy: state.groupBy, cubit: cubit),
            const SizedBox(width: 4),
            _SavedViewsMenu(state: state, cubit: cubit),
            IconButton(
              tooltip: 'Board columns',
              icon: const Icon(Icons.view_column_outlined),
              onPressed: () async {
                final res = await showBoardColumnsDialog(
                  context,
                  statuses: state.statuses,
                  order: state.columnOrder,
                  hidden: state.hiddenColumnIds,
                );
                if (res != null) {
                  cubit.setColumns(order: res.order, hidden: res.hidden);
                }
              },
            ),
          ],
        );
      },
    );
  }
}

/// Swimlane grouping dropdown.
class _GroupByMenu extends StatelessWidget {
  const _GroupByMenu({required this.groupBy, required this.cubit});
  final BoardGroupBy? groupBy;
  final TaskBoardCubit cubit;

  String _label(BoardGroupBy? g) => switch (g) {
    null => 'No grouping',
    BoardGroupBy.component => 'Component',
    BoardGroupBy.assignee => 'Assignee',
    BoardGroupBy.epic => 'Epic',
    BoardGroupBy.priority => 'Priority',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Group by',
      onSelected: (wire) => cubit.setGrouping(
        wire == 'none' ? null : BoardGroupBy.fromWire(wire),
      ),
      itemBuilder: (ctx) => [
        for (final g in <BoardGroupBy?>[null, ...BoardGroupBy.values])
          CheckedPopupMenuItem<String>(
            value: g?.wire ?? 'none',
            checked: g == groupBy,
            child: Text(_label(g)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.splitscreen, size: 18),
            const SizedBox(width: 6),
            Text(_label(groupBy)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Saved-views menu: apply / delete saved board views and save the current one.
class _SavedViewsMenu extends StatelessWidget {
  const _SavedViewsMenu({required this.state, required this.cubit});
  final TaskBoardLoaded state;
  final TaskBoardCubit cubit;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Saved boards',
      icon: const Icon(Icons.bookmark_border),
      onSelected: (value) async {
        if (value == '__save__') {
          final name = await _promptName(context);
          if (name != null && name.trim().isNotEmpty) {
            await cubit.saveView(name.trim());
          }
          return;
        }
        final view = state.savedViews.firstWhere((v) => v.id == value);
        cubit.applyView(view);
      },
      itemBuilder: (ctx) => [
        for (final v in state.savedViews)
          PopupMenuItem<String>(
            value: v.id,
            child: Row(
              children: [
                Expanded(child: Text(v.name)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete',
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    unawaited(cubit.deleteView(v.id));
                  },
                ),
              ],
            ),
          ),
        if (state.savedViews.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__save__',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add),
            title: Text('Save current board…'),
          ),
        ),
      ],
    );
  }

  Future<String?> _promptName(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save board'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
          filter: state.filter,
          onChanged: (f) => context.read<TaskBoardCubit>().setFilter(f),
          statuses: state.statuses,
          types: state.types,
          priorities: state.priorities,
          sizes: state.sizes,
          epics: state.epics,
          milestones: state.milestones,
          labels: state.labels,
          components: state.components,
          showStatus: false,
        ),
        Expanded(
          child: state.groupBy == null
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
    final buckets = state.bucketed;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final status in state.orderedVisibleStatuses)
            _TaskColumn(
              status: status,
              tasks: buckets[status.id] ?? const [],
              projectId: projectId,
              keyPrefix: keyPrefix,
              selectedId: selectedId,
              onSelect: onSelect,
            ),
          _TaskColumn(
            status: null,
            tasks: buckets[null] ?? const [],
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

/// A single swimlane group: a display name plus the issues belonging to it.
class _Group {
  const _Group({required this.title, required this.issues});
  final String title;
  final List<Issue> issues;
}

/// The grouped (swimlane) layout: one horizontal board per distinct group
/// value, stacked vertically with a sub-header per row.
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

  List<_Group> _buildGroups(BuildContext context) {
    final issues = state.visibleIssues;
    final groupBy = state.groupBy!;
    // Bucket issues by their (possibly multi-valued) group key.
    final byKey = <String?, List<Issue>>{};
    void add(String? key, Issue i) => byKey.putIfAbsent(key, () => []).add(i);
    for (final i in issues) {
      switch (groupBy) {
        case BoardGroupBy.component:
          if (i.components.isEmpty) {
            add(null, i);
          } else {
            for (final c in i.components) {
              add(c, i);
            }
          }
        case BoardGroupBy.assignee:
          add(i.assignedTo, i);
        case BoardGroupBy.epic:
          add(i.epicId, i);
        case BoardGroupBy.priority:
          add(i.priorityId, i);
      }
    }

    String resolve(String? key) {
      if (key == null) {
        return switch (groupBy) {
          BoardGroupBy.component => 'No component',
          BoardGroupBy.assignee => 'Unassigned',
          BoardGroupBy.epic => 'No epic',
          BoardGroupBy.priority => 'No priority',
        };
      }
      switch (groupBy) {
        case BoardGroupBy.component:
          final c = state.components.where((e) => e.id == key).firstOrNull;
          return c?.name ?? key;
        case BoardGroupBy.assignee:
          return MembersScope.user(context, key)?.displayName ?? key;
        case BoardGroupBy.epic:
          final e = state.epics.where((x) => x.id == key).firstOrNull;
          return e == null
              ? key
              : '${epicKeyLabel(keyPrefix, e.reference)} ${e.subject}';
        case BoardGroupBy.priority:
          final p = state.priorities.where((x) => x.id == key).firstOrNull;
          return p?.name ?? key;
      }
    }

    // Sort keys: priority by taxonomy order, others by display name; the
    // "none" group always last.
    final keys = byKey.keys.toList();
    int orderOf(String? k) {
      if (k == null) return 1 << 30;
      if (groupBy == BoardGroupBy.priority) {
        final p = state.priorities.where((x) => x.id == k).firstOrNull;
        return p == null ? (1 << 29) : p.order.round();
      }
      return 0;
    }

    keys.sort((a, b) {
      final ra = orderOf(a);
      final rb = orderOf(b);
      if (ra != rb) return ra.compareTo(rb);
      if (a == null) return 1;
      if (b == null) return -1;
      return resolve(a).toLowerCase().compareTo(resolve(b).toLowerCase());
    });

    return [
      for (final k in keys) _Group(title: resolve(k), issues: byKey[k]!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _buildGroups(context);
    if (groups.isEmpty) {
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
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  g.title.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${g.issues.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 460,
            child: _SwimlaneColumns(
              state: state,
              issues: g.issues,
              projectId: projectId,
              keyPrefix: keyPrefix,
              selectedId: selectedId,
              onSelect: onSelect,
            ),
          ),
        ],
      ],
    );
  }
}

/// The horizontal column row for a single swimlane group.
class _SwimlaneColumns extends StatelessWidget {
  const _SwimlaneColumns({
    required this.state,
    required this.issues,
    required this.projectId,
    required this.keyPrefix,
    required this.selectedId,
    required this.onSelect,
  });
  final TaskBoardLoaded state;
  final List<Issue> issues;
  final String projectId;
  final String keyPrefix;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final buckets = state.bucketFor(issues);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final status in state.orderedVisibleStatuses)
            _TaskColumn(
              status: status,
              tasks: buckets[status.id] ?? const [],
              projectId: projectId,
              keyPrefix: keyPrefix,
              selectedId: selectedId,
              onSelect: onSelect,
            ),
          _TaskColumn(
            status: null,
            tasks: buckets[null] ?? const [],
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

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.status,
    required this.tasks,
    required this.projectId,
    required this.keyPrefix,
    required this.selectedId,
    required this.onSelect,
  });

  /// Null for the trailing "no status" column.
  final TaxonomyItem? status;
  final List<Issue> tasks;
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
                count: tasks.length,
              ),
              const Divider(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final task in tasks)
                      _TaskCard(
                        task: task,
                        projectId: projectId,
                        keyPrefix: keyPrefix,
                        selected: task.id == selectedId,
                        onTap: () => onSelect(task.id),
                      ),
                    if (tasks.isEmpty)
                      _EmptyColumnNote(label: t.boardEmptyColumn),
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
    required this.task,
    required this.projectId,
    required this.keyPrefix,
    required this.selected,
    required this.onTap,
  });
  final Issue task;
  final String projectId;
  final String keyPrefix;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  if (MembersScope.user(context, task.assignedTo) != null)
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
              if (MembersScope.user(context, task.ownerId) != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    Tooltip(
                      message:
                          '${AppLocalizations.of(context).detailFieldReporter}: '
                          '${MembersScope.user(context, task.ownerId)!.displayName}',
                      child: UserAvatar(
                        user: MembersScope.user(context, task.ownerId)!,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ],
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
