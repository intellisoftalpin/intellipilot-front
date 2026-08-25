import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
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
import 'package:intellipilot/features/board/data/board_snapshot_cache.dart';
import 'package:intellipilot/features/board/domain/board_config.dart';
import 'package:intellipilot/features/board/domain/board_source.dart';
import 'package:intellipilot/features/board/domain/my_issues_lanes.dart';
import 'package:intellipilot/features/board/presentation/boards_nav_refresh.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
import 'package:intellipilot/features/board/presentation/my_issues_labels.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_columns_dialog.dart';
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
  const BoardPage({
    required this.projectId,
    required this.boardId,
    this.sourceBuilder,
    this.titleOverride,
    super.key,
  });
  final String projectId;
  final String boardId;

  /// Supplies the board definition. Null means the server-backed board named
  /// by [boardId]; the My Issues page passes a synthetic source instead. It is
  /// a builder because a synthetic board is scoped to the signed-in user, who
  /// is only known once the profile has loaded.
  final BoardSource Function(UserProfile profile)? sourceBuilder;

  /// Replaces the board name in the app bar (and suppresses the board
  /// switcher) for boards that are not one of several.
  final String? titleOverride;

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
                    cache: getIt<BoardSnapshotCache>(),
                    events: getIt<ProjectEventsService>(),
                    currentUserId: profile.id,
                    currentUsername: profile.username,
                    source: sourceBuilder?.call(profile),
                  );
                  unawaited(c.load());
                  return c;
                },
              ),
            ],
            child: _BoardView(
              projectId: projectId,
              currentUserId: profile.id,
              titleOverride: titleOverride,
            ),
          ),
        );
      },
    );
  }
}

class _BoardView extends StatefulWidget {
  const _BoardView({
    required this.projectId,
    required this.currentUserId,
    this.titleOverride,
  });
  final String projectId;
  final String currentUserId;

  /// Set for a board that isn't one of several: shows this label and drops the
  /// board switcher and the board-settings dialog.
  final String? titleOverride;

  @override
  State<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<_BoardView> {
  String? _selectedId;

  Future<void> _select(String id) async {
    setState(() => _selectedId = id);
    final cubit = context.read<TaskBoardCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);
    final detail = context.read<ProjectDetailCubit>().state;
    final keyPrefix = detail is ProjectDetailLoaded
        ? detail.project.issuePrefix
        : '';
    final versionBefore = cubit.findIssue(id)?.version;
    await showEntityDetailSheet(
      context,
      projectId: widget.projectId,
      kind: EntityKind.issue,
      entityId: id,
    );
    if (!mounted) return;
    setState(() => _selectedId = null);
    // Cheap delta catch-up (not a board reload) picks up any sheet edits.
    await cubit.refresh();
    final after = cubit.findIssue(id);
    if (versionBefore != null &&
        after != null &&
        after.version > versionBefore) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            t.boardToastUpdated(
              '${issueKeyLabel(keyPrefix, after.reference)} · ${after.subject}',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<TaskBoardCubit, TaskBoardState>(
          builder: (context, state) {
            final board = state is TaskBoardLoaded ? state.board : null;
            final fixed = widget.titleOverride;
            final label = fixed ?? board?.name ?? t.boardTitle;
            return ProjectSectionBreadcrumb(
              projectId: widget.projectId,
              currentLabel: label,
              activeWidget: board == null || fixed != null
                  ? null
                  : _BoardSwitcher(
                      projectId: widget.projectId,
                      currentBoardId: board.id,
                      currentLabel: label,
                    ),
            );
          },
        ),
        actions: [
          const _BoardSearchField(),
          IconButton(
            tooltip: t.boardReloadTooltip,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                unawaited(context.read<TaskBoardCubit>().fullReload()),
          ),
          if (widget.titleOverride == null)
            _BoardSettingsButton(
              projectId: widget.projectId,
              currentUserId: widget.currentUserId,
            )
          else
            // A synthetic board has no name, colour or locked filters to edit
            // — only its columns.
            const _BoardColumnsButton(),
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

/// The breadcrumb's active segment on the board screen: a dropdown listing the
/// project's boards. With a single board it renders as plain (active) text.
class _BoardSwitcher extends StatefulWidget {
  const _BoardSwitcher({
    required this.projectId,
    required this.currentBoardId,
    required this.currentLabel,
  });
  final String projectId;
  final String currentBoardId;
  final String currentLabel;

  @override
  State<_BoardSwitcher> createState() => _BoardSwitcherState();
}

class _BoardSwitcherState extends State<_BoardSwitcher> {
  List<Board> _boards = const [];

  @override
  void initState() {
    super.initState();
    boardsNavRevision.addListener(_fetch);
    unawaited(_fetch());
  }

  @override
  void dispose() {
    boardsNavRevision.removeListener(_fetch);
    super.dispose();
  }

  Future<void> _fetch() async {
    final res = await getIt<CatalogRepository>().listBoards(widget.projectId);
    if (!mounted) return;
    setState(() => _boards = res.valueOrNull ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );

    // A single board: plain active text, matching a normal breadcrumb leaf.
    if (_boards.length <= 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(widget.currentLabel, style: style),
      );
    }

    return PopupMenuButton<String>(
      offset: const Offset(0, 36),
      tooltip: '',
      onSelected: (id) {
        if (id != widget.currentBoardId) {
          context.go(Routes.projectBoardFor(widget.projectId, id));
        }
      },
      itemBuilder: (_) => [
        for (final b in _boards)
          PopupMenuItem<String>(
            value: b.id,
            child: Row(
              children: [
                Expanded(
                  child: Text(b.name, overflow: TextOverflow.ellipsis),
                ),
                if (b.isShared) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.group_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.currentLabel,
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Single settings entry-point, gated on shared-board permissions or personal
/// board ownership. Greyed out (disabled) when the user may not modify the
/// board. Delete lives inside the dialog's danger zone.
class _BoardSettingsButton extends StatelessWidget {
  const _BoardSettingsButton({
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
        return IconButton(
          tooltip: t.boardSettingsTooltip,
          icon: const Icon(Icons.settings),
          onPressed: canEdit
              ? () async {
                  final cubit = context.read<TaskBoardCubit>();
                  final updated = await showBoardSettingsDialog(
                    context,
                    projectId: projectId,
                    board: board,
                    canDelete: canDelete,
                  );
                  if (updated != null) {
                    bumpBoardsNav();
                    await cubit.load();
                  }
                }
              : null,
        );
      },
    );
  }
}

/// Column show/hide/reorder for a board with no server-side definition — the
/// only part of a synthetic board that is the user's to configure.
class _BoardColumnsButton extends StatelessWidget {
  const _BoardColumnsButton();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<TaskBoardCubit, TaskBoardState>(
      builder: (context, state) {
        if (state is! TaskBoardLoaded) return const SizedBox.shrink();
        return IconButton(
          tooltip: t.myIssuesColumnsTooltip,
          icon: const Icon(Icons.view_column_outlined),
          onPressed: () async {
            final cubit = context.read<TaskBoardCubit>();
            final cfg = state.config;
            final order = cfg.columnOrder.isEmpty
                ? BoardConfig.defaultColumnOrder(state.statuses)
                : cfg.columnOrder;
            final res = await showBoardColumnsDialog(
              context,
              statuses: state.statuses,
              order: order,
              hidden: cfg.hiddenColumnIds,
            );
            if (res == null) return;
            await cubit.saveColumns(
              order: res.order,
              visible: [
                for (final id in res.order)
                  if (!res.hidden.contains(id)) id,
              ],
            );
          },
        );
      },
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
        Align(
          alignment: Alignment.centerLeft,
          child: WorkItemFilterBar(
            projectId: cubit.projectId,
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
            // The board hides the issue-type filter (board-only decision) and
            // the active swimlane dimension. On the My Issues board the person
            // filters duplicate the lanes, so they go too.
            hiddenDimensions: {
              'type',
              ?state.group?.filterKey,
              if (state.group == BoardGroupBy.myRole) ...[
                'assignee',
                'qa_assignee',
                'involved',
              ],
            },
          ),
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

/// The flat single-board layout (no grouping): a horizontal strip of columns
/// that each scroll vertically on their own (Trello-style), with a single
/// always-visible horizontal scrollbar. The board pane owns the scroll — there
/// is no outer page scroll.
class _FlatBoard extends StatefulWidget {
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
  State<_FlatBoard> createState() => _FlatBoardState();
}

class _FlatBoardState extends State<_FlatBoard> {
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final byId = {for (final s in state.statuses) s.id: s};
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontal,
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
                projectId: widget.projectId,
                keyPrefix: widget.keyPrefix,
                selectedId: widget.selectedId,
                onSelect: widget.onSelect,
                scrollable: true,
              ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// The grouped (swimlane) layout: a single outer vertical scroll (owned by the
/// board pane) through the stacked lanes, with sticky lane sub-headers. Each
/// lane's columns grow to content height (cards are capped + "Load more"), so
/// no inner vertical scroll is ever nested. Lanes are collapsible; the
/// collapsed set is persisted per board in local Hive.
class _Swimlanes extends StatefulWidget {
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

  @override
  State<_Swimlanes> createState() => _SwimlanesState();
}

class _SwimlanesState extends State<_Swimlanes> {
  final ScrollController _vertical = ScrollController();
  late final KeyValueStorage _storage = getIt<KeyValueStorage>(
    instanceName: HiveBoxes.ui,
  );
  late Set<String> _collapsed;

  String get _prefsKey => 'board_collapsed:${widget.state.board.id}';

  @override
  void initState() {
    super.initState();
    final saved = _storage.get<List<dynamic>>(_prefsKey) ?? const [];
    _collapsed = {for (final e in saved) e.toString()};
  }

  @override
  void dispose() {
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _toggle(String key) async {
    setState(() {
      if (_collapsed.contains(key)) {
        _collapsed.remove(key);
      } else {
        _collapsed.add(key);
      }
    });
    await _storage.set<List<String>>(_prefsKey, _collapsed.toList());
  }

  String _resolveLane(BuildContext context, String key) {
    final state = widget.state;
    final group = state.group!;
    if (key == 'none') {
      final t = AppLocalizations.of(context);
      return switch (group) {
        BoardGroupBy.component => t.boardLaneNoComponent,
        BoardGroupBy.assignee => t.dashKpiUnassigned,
        BoardGroupBy.epic => t.backlogNoEpic,
        BoardGroupBy.priority => t.boardLaneNoPriority,
        // Role lanes have no "unset" bucket: an issue with no role for the
        // caller is simply not on the board.
        BoardGroupBy.myRole => key,
      };
    }
    switch (group) {
      case BoardGroupBy.myRole:
        return myIssuesLaneLabel(context, key);
      case BoardGroupBy.component:
        return state.components.where((e) => e.id == key).firstOrNull?.name ??
            key;
      case BoardGroupBy.assignee:
        return MembersScope.user(context, key)?.displayName ?? key;
      case BoardGroupBy.epic:
        final e = state.epics.where((x) => x.id == key).firstOrNull;
        return e == null
            ? key
            : '${epicKeyLabel(widget.keyPrefix, e.reference)} ${e.subject}';
      case BoardGroupBy.priority:
        return state.priorities.where((x) => x.id == key).firstOrNull?.name ??
            key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
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
    return Scrollbar(
      controller: _vertical,
      thumbVisibility: true,
      child: CustomScrollView(
        controller: _vertical,
        slivers: [
          for (final lane in state.lanes) ...[
            // Non-pinned: multiple pinned headers in one CustomScrollView
            // accumulate `SliverConstraints.overlap`, which the box-adapter
            // strips below don't consume — producing a gap that grows with each
            // successive lane and wasting vertical space with many lanes. Plain
            // scrolling headers keep every lane compact.
            SliverPersistentHeader(
              pinned: false,
              delegate: _LaneHeaderDelegate(
                title: _resolveLane(context, lane.key),
                total: lane.total,
                collapsed: _collapsed.contains(lane.key),
                background: theme.colorScheme.surface,
                onToggle: () => _toggle(lane.key),
              ),
            ),
            if (!_collapsed.contains(lane.key))
              SliverToBoxAdapter(
                child: _SwimlaneStrip(
                  lane: lane,
                  byId: byId,
                  state: state,
                  projectId: widget.projectId,
                  keyPrefix: widget.keyPrefix,
                  selectedId: widget.selectedId,
                  onSelect: widget.onSelect,
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }
}

/// Sticky lane sub-header: an expand/collapse toggle, the lane label and the
/// lane's total. Opaque background so it covers content when pinned.
class _LaneHeaderDelegate extends SliverPersistentHeaderDelegate {
  _LaneHeaderDelegate({
    required this.title,
    required this.total,
    required this.collapsed,
    required this.background,
    required this.onToggle,
  });

  final String title;
  final int total;
  final bool collapsed;
  final Color background;
  final VoidCallback onToggle;

  static const double _height = 44;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return Material(
      color: background,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          child: Row(
            children: [
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$total',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LaneHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.total != total ||
      oldDelegate.collapsed != collapsed ||
      oldDelegate.background != background;
}

/// A single lane's horizontal strip of columns. The columns grow to their
/// content height (no inner vertical scroll); the strip scrolls horizontally
/// with an always-visible scrollbar.
class _SwimlaneStrip extends StatefulWidget {
  const _SwimlaneStrip({
    required this.lane,
    required this.byId,
    required this.state,
    required this.projectId,
    required this.keyPrefix,
    required this.selectedId,
    required this.onSelect,
  });

  final BoardLaneData lane;
  final Map<String, TaxonomyItem> byId;
  final TaskBoardLoaded state;
  final String projectId;
  final String keyPrefix;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<_SwimlaneStrip> createState() => _SwimlaneStripState();
}

class _SwimlaneStripState extends State<_SwimlaneStrip> {
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lane = widget.lane;
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final col in lane.columns)
              _TaskColumn(
                state: widget.state,
                column: col,
                status: col.statusId == null ? null : widget.byId[col.statusId],
                laneKey: lane.key,
                projectId: widget.projectId,
                keyPrefix: widget.keyPrefix,
                selectedId: widget.selectedId,
                onSelect: widget.onSelect,
                scrollable: false,
              ),
            const SizedBox(width: 16),
          ],
        ),
      ),
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
    required this.scrollable,
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

  /// When true (flat board) the card list scrolls vertically inside a bounded
  /// column (Expanded + ListView). When false (swimlanes) the column grows to
  /// its content height — the cap + "Load more" keeps it bounded.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canCreate =
        detail is ProjectDetailLoaded &&
        detail.has(Permission.issueCreate) &&
        status != null &&
        // You cannot create an issue that mentions you: a card created here
        // could not land in this lane, so don't offer it.
        !(state.group == BoardGroupBy.myRole &&
            laneKey == MyIssuesLane.mentioned.wire);
    return DragTarget<BoardDragData>(
      // A drop is only ever a status change. On a board whose lanes are a
      // dimension the card cannot be moved along by dragging (the caller's
      // role on the issue), a cross-lane drop would silently patch the status
      // and leave the card in a visibly wrong lane — so refuse it outright
      // rather than half-apply it.
      onWillAcceptWithDetails: (details) => boardAcceptsDrop(
        drag: details.data,
        laneKey: laneKey,
        lanesAreFixed: state.lanesAreFixed,
      ),
      onAcceptWithDetails: (details) {
        final cubit = context.read<TaskBoardCubit>();
        final messenger = ScaffoldMessenger.of(context);
        unawaited(() async {
          final moved = await cubit.moveTask(
            taskId: details.data.issueId,
            targetStatusId: status?.id,
          );
          if (moved == null) return;
          messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 4),
              content: Text(
                t.boardToastUpdated(
                  '${issueKeyLabel(keyPrefix, moved.reference)} · '
                  '${moved.subject}',
                ),
              ),
            ),
          );
        }());
      },
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        final cards = <Widget>[
          for (final card in column.cards)
            _TaskCard(
              state: state,
              task: card,
              projectId: projectId,
              keyPrefix: keyPrefix,
              laneKey: laneKey,
              selected: card.id == selectedId,
              highlighted: state.highlightedIds.contains(card.id),
              onTap: () => onSelect(card.id),
            ),
          if (column.cards.isEmpty) _EmptyColumnNote(label: t.boardEmptyColumn),
          if (column.hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(
                  t.boardLoadMore(column.total - column.cards.length),
                ),
                onPressed: () => context.read<TaskBoardCubit>().loadMoreColumn(
                  laneKey: laneKey,
                  statusId: column.statusId,
                  offset: column.cards.length,
                ),
              ),
            ),
        ];
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
            mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
            children: [
              _ColumnHeader(
                statusColor: status?.color ?? '',
                title: status?.name ?? t.boardColumnNoStatus,
                count: column.total,
                onCreate: canCreate ? () => _createInColumn(context) : null,
              ),
              const Divider(height: 12),
              if (scrollable)
                Expanded(
                  child: ListView(padding: EdgeInsets.zero, children: cards),
                )
              else
                ...cards,
            ],
          ),
        );
      },
    );
  }

  /// Subject + type prompt, then create with this column's status (and the
  /// swimlane value on a grouped board) preset. On success the new issue's
  /// detail sheet opens right away (parity with the Issues page), so the
  /// user gets immediate feedback even when an active board filter hides
  /// the fresh card.
  Future<void> _createInColumn(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<TaskBoardCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final input = await showDialog<_ColumnCreateInput>(
      context: context,
      builder: (_) => _ColumnCreateDialog(types: state.types),
    );
    if (input == null) return;
    final created = await cubit.createIssueInColumn(
      subject: input.subject,
      statusId: status?.id,
      typeId: input.typeId,
      laneKey: laneKey,
    );
    if (created == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.ttActionFailed)));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          t.boardToastCreated(
            '${issueKeyLabel(keyPrefix, created.reference)} · '
            '${created.subject}',
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    await showEntityDetailSheet(
      context,
      projectId: projectId,
      kind: EntityKind.issue,
      entityId: created.id,
    );
    // Reflect whatever was edited in the sheet on the board.
    await cubit.refresh();
  }
}

/// Result of the per-column create prompt.
class _ColumnCreateInput {
  const _ColumnCreateInput({required this.subject, this.typeId});
  final String subject;
  final String? typeId;
}

/// Minimal per-column issue prompt (subject + type). Owns its text
/// controller so disposal happens with the dialog route, never while the
/// closing animation still has the field mounted.
class _ColumnCreateDialog extends StatefulWidget {
  const _ColumnCreateDialog({required this.types});
  final List<TaxonomyItem> types;

  @override
  State<_ColumnCreateDialog> createState() => _ColumnCreateDialogState();
}

class _ColumnCreateDialogState extends State<_ColumnCreateDialog> {
  final _subject = TextEditingController();
  String? _typeId;

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  void _submit() {
    final subject = _subject.text.trim();
    if (subject.isEmpty) return;
    Navigator.of(context).pop(
      _ColumnCreateInput(subject: subject, typeId: _typeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.actionNewIssue),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _subject,
              autofocus: true,
              decoration: InputDecoration(labelText: t.backlogFieldSubject),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _typeId,
              isExpanded: true,
              decoration: InputDecoration(labelText: t.issueFieldType),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('—'),
                ),
                for (final item in widget.types)
                  DropdownMenuItem<String?>(
                    value: item.id,
                    child: Text(
                      item.emoji.isEmpty
                          ? item.name
                          : '${item.emoji} ${item.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _typeId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(t.actionSave)),
      ],
    );
  }
}

/// Whether [drag] may be dropped on a column in [laneKey].
///
/// A drop only ever changes the status. When the lanes are a dimension the card
/// cannot be moved along by dragging — the caller's role on the issue, on the
/// My Issues board — a cross-lane drop would patch the status and leave the
/// card in a visibly wrong lane, so it is refused outright instead of being
/// half-applied. Flat and ordinarily-grouped boards accept every drop.
bool boardAcceptsDrop({
  required BoardDragData drag,
  required String? laneKey,
  required bool lanesAreFixed,
}) => !lanesAreFixed || drag.laneKey == laneKey;

/// What a dragged card carries: the issue, plus the lane it started in so a
/// drop target can refuse a cross-lane move.
@immutable
class BoardDragData {
  const BoardDragData({required this.issueId, this.laneKey});
  final String issueId;

  /// Null on a flat (ungrouped) board.
  final String? laneKey;

  @override
  bool operator ==(Object other) =>
      other is BoardDragData &&
      other.issueId == issueId &&
      other.laneKey == laneKey;

  @override
  int get hashCode => Object.hash(issueId, laneKey);
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.state,
    required this.task,
    required this.projectId,
    required this.keyPrefix,
    required this.selected,
    required this.onTap,
    this.laneKey,
    this.highlighted = false,
  });
  final TaskBoardLoaded state;
  final Issue task;
  final String projectId;
  final String keyPrefix;

  /// The lane this card is rendered in; travels with the drag payload.
  final String? laneKey;
  final bool selected;

  /// Recently changed by another user — rendered with a selection-like glow
  /// that fades after a few seconds.
  final bool highlighted;
  final VoidCallback onTap;

  List<String> get _fields => state.config.cardFields ?? const ['assignee'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showAssignee = _fields.contains('assignee');
    final cardWidget = Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: highlighted
          ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35)
          : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : highlighted
              ? theme.colorScheme.tertiary
              : theme.colorScheme.outlineVariant,
          width: selected || highlighted ? 2 : 1,
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
                  if (showAssignee)
                    ?_roleAvatar(
                      context,
                      '🔨',
                      AppLocalizations.of(context).detailFieldAssignee,
                      task.assignedTo,
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
    return Draggable<BoardDragData>(
      data: BoardDragData(issueId: task.id, laneKey: laneKey),
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
    if (_fields.contains('release')) {
      chips.addAll(_versionChips(task, state));
    }

    final t = AppLocalizations.of(context);
    // QA + Reviewer (when assigned) and the reporter share one people row.
    final qa = _roleAvatar(
      context,
      '🐞',
      t.detailFieldQaAssignee,
      task.qaAssigneeId,
    );
    final reviewer = _roleAvatar(
      context,
      '👀',
      t.detailFieldReviewer,
      task.reviewerId,
    );
    final reporter = _roleAvatar(
      context,
      '📝',
      t.detailFieldReporter,
      task.ownerId,
    );
    final people = [qa, reviewer, reporter].whereType<Widget>().toList();
    return [
      if (chips.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
      if (people.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 6,
          children: people,
        ),
      ],
    ];
  }

  /// Version pills for a card.
  ///
  /// Since per-component fix versions landed, one issue can ship in several
  /// versions at once. Showing only `releaseVersionId` would report just the
  /// lowest-ordered one, which is a mirror the server maintains for filters
  /// and exports rather than the whole truth.
  ///
  /// Pills are deduplicated by version — two components shipping in the same
  /// version is one fact, not two — and capped so a card with many components
  /// does not grow without bound. The overflow pill carries the full
  /// component-to-version breakdown.
  List<Widget> _versionChips(Issue task, TaskBoardLoaded state) {
    ReleaseVersionRef? refFor(String id) =>
        state.releaseVersions.where((x) => x.id == id).firstOrNull;

    // Fall back to the mirror for an issue that carries a version but no
    // components — nothing to break down, so the old single pill is right.
    if (task.componentVersions.isEmpty) {
      final id = task.releaseVersionId;
      if (id == null) return const [];
      final v = refFor(id);
      return v == null
          ? const []
          : [
              StatusPill(
                label: v.version,
                colorHex: v.releaseColor,
                dense: true,
              ),
            ];
    }

    final seen = <String>{};
    final versions = <ReleaseVersionRef>[];
    for (final cv in task.componentVersions) {
      if (!seen.add(cv.releaseVersionId)) continue;
      final v = refFor(cv.releaseVersionId);
      if (v != null) versions.add(v);
    }
    if (versions.isEmpty) return const [];
    // `state.releaseVersions` arrives in the server's release/version order,
    // so sorting by position in it keeps pills in the same order the rest of
    // the app shows versions.
    versions.sort(
      (a, b) => state.releaseVersions
          .indexWhere((x) => x.id == a.id)
          .compareTo(state.releaseVersions.indexWhere((x) => x.id == b.id)),
    );

    const maxPills = 3;
    final shown = versions.take(maxPills).toList();
    final chips = <Widget>[
      for (final v in shown)
        StatusPill(label: v.version, colorHex: v.releaseColor, dense: true),
    ];
    if (versions.length > maxPills) {
      chips.add(
        _VersionOverflowPill(
          hiddenCount: versions.length - maxPills,
          rows: [
            for (final cv in task.componentVersions)
              (
                component:
                    state.components
                        .where((c) => c.id == cv.componentId)
                        .firstOrNull
                        ?.name ??
                    cv.componentId,
                version: refFor(cv.releaseVersionId)?.version ?? '—',
              ),
          ]..sort((a, b) => a.component.compareTo(b.component)),
        ),
      );
    }
    return chips;
  }

  /// A compact `emoji + avatar` badge for a person role on the card, with a
  /// tooltip naming the role and person. Returns null when the id does not
  /// resolve to a known member (e.g. unassigned).
  Widget? _roleAvatar(
    BuildContext context,
    String emoji,
    String label,
    String? userId, {
    double size = 18,
  }) {
    final u = MembersScope.user(context, userId);
    if (u == null) return null;
    return Tooltip(
      message: '$label: ${u.displayName}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: TextStyle(fontSize: size * 0.6)),
          const SizedBox(width: 3),
          UserAvatar(user: u, size: size),
        ],
      ),
    );
  }
}

/// The `+N` pill that stands in for versions the card has no room to show.
///
/// Hovering reveals the full component-to-version breakdown and moving away
/// hides it again. Clicking *pins* the popup open — it then stays until the
/// close button, Escape, or a tap outside dismisses it. Pinning is what makes
/// this usable on touch, where there is no hover at all.
class _VersionOverflowPill extends StatefulWidget {
  const _VersionOverflowPill({required this.hiddenCount, required this.rows});

  final int hiddenCount;
  final List<({String component, String version})> rows;

  @override
  State<_VersionOverflowPill> createState() => _VersionOverflowPillState();
}

class _VersionOverflowPillState extends State<_VersionOverflowPill> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  bool _pinned = false;

  void _show() {
    if (!_portal.isShowing) _portal.show();
  }

  void _hoverOut() {
    // A pinned popup survives the pointer leaving; that is the whole point.
    if (!_pinned && _portal.isShowing) _portal.hide();
  }

  void _close() {
    _pinned = false;
    if (_portal.isShowing) _portal.hide();
    if (mounted) setState(() {});
  }

  void _togglePin() {
    setState(() => _pinned = !_pinned);
    if (_pinned) {
      _show();
    } else {
      _portal.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Positioned.fill(
          child: Stack(
            children: [
              // Only a pinned popup takes the screen: an unpinned one must not
              // swallow clicks meant for the board underneath.
              if (_pinned)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _close,
                  ),
                ),
              CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _popup(theme, t),
                ),
              ),
            ],
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _hoverOut(),
          child: GestureDetector(
            onTap: _togglePin,
            child: _MetaChip(color: '', label: '+${widget.hiddenCount}'),
          ),
        ),
      ),
    );
  }

  Widget _popup(ThemeData theme, AppLocalizations t) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: _pinned,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHigh,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.boardCardVersionsTitle,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      if (_pinned)
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: t.actionClose,
                          visualDensity: VisualDensity.compact,
                          onPressed: _close,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2),
                          1: FlexColumnWidth(1),
                        },
                        children: [
                          for (final r in widget.rows)
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                    horizontal: 2,
                                  ),
                                  child: Text(
                                    r.component,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                    horizontal: 2,
                                  ),
                                  child: Text(
                                    r.version,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    this.onCreate,
  });

  final String statusColor;
  final String title;
  final int count;

  /// When set, renders a "+" that creates an issue directly in this column.
  final VoidCallback? onCreate;

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
        if (onCreate != null)
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: AppLocalizations.of(context).actionNewIssue,
            onPressed: onCreate,
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
