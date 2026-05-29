import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/dtos/board_dtos.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';
import 'package:intellipilot/features/board/presentation/cubits/board_cubit.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_filters_drawer.dart';
import 'package:intellipilot/features/board/presentation/widgets/saved_views_menu.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Two scopes — user stories (sprint-bound, drives milestone planning) and
/// tasks (project-wide, day-to-day execution) — share one Board page with
/// a Stories ⇄ Tasks toggle in the app bar. The chosen view persists per
/// project in the UI Hive box so each project remembers what its team
/// uses most.
enum _BoardViewMode { stories, tasks }

class BoardPage extends StatefulWidget {
  const BoardPage({required this.projectId, super.key});
  final String projectId;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  static const _prefsKey = 'board.view';
  late _BoardViewMode _mode;

  @override
  void initState() {
    super.initState();
    final box = getIt<KeyValueStorage>(instanceName: HiveBoxes.ui);
    final saved = box.get<String>('$_prefsKey.${widget.projectId}');
    _mode = _BoardViewMode.values
            .cast<_BoardViewMode?>()
            .firstWhere((m) => m?.name == saved, orElse: () => null) ??
        _BoardViewMode.stories;
  }

  Future<void> _setMode(_BoardViewMode mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    final box = getIt<KeyValueStorage>(instanceName: HiveBoxes.ui);
    await box.set<String>('$_prefsKey.${widget.projectId}', mode.name);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future:
          getIt<ProfileRepository>().getProfile().then((r) => r.valueOrNull),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) {
          return Scaffold(
            body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider<ProjectDetailCubit>(
              create: (_) => ProjectDetailCubit(
                repo: getIt<ProjectsRepository>(),
                projectId: widget.projectId,
                currentUserId: profile.id,
              )..load(),
            ),
            BlocProvider<BoardCubit>(
              create: (_) => BoardCubit(
                milestones: getIt<MilestonesRepository>(),
                board: getIt<BoardRepository>(),
                backlog: getIt<BacklogRepository>(),
                projectId: widget.projectId,
              )..load(),
            ),
            BlocProvider<TaskBoardCubit>(
              create: (_) => TaskBoardCubit(
                repo: getIt<BacklogRepository>(),
                catalog: getIt<CatalogRepository>(),
                projectId: widget.projectId,
              )..load(),
            ),
          ],
          child: _BoardView(
            projectId: widget.projectId,
            mode: _mode,
            onModeChanged: _setMode,
          ),
        );
      },
    );
  }
}

typedef _Selected = ({EntityKind kind, String id});

class _BoardView extends StatefulWidget {
  const _BoardView({
    required this.projectId,
    required this.mode,
    required this.onModeChanged,
  });
  final String projectId;
  final _BoardViewMode mode;
  final ValueChanged<_BoardViewMode> onModeChanged;

  @override
  State<_BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<_BoardView> {
  /// The card a user clicked on. When non-null the right-side details
  /// panel shows the entity; the card itself renders with a primary
  /// outline so it's obvious which one is open.
  _Selected? _selected;

  void _select(EntityKind kind, String id) {
    setState(() => _selected = (kind: kind, id: id));
  }

  void _clearSelection() => setState(() => _selected = null);

  @override
  void didUpdateWidget(covariant _BoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching between Stories ⇄ Tasks invalidates the current
    // selection — the entity kind no longer matches the visible cards.
    if (oldWidget.mode != widget.mode) _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final body = widget.mode == _BoardViewMode.stories
        ? _StoryBoardBody(
            projectId: widget.projectId,
            selectedId: _selected?.kind == EntityKind.userStory
                ? _selected?.id
                : null,
            onSelect: (id) => _select(EntityKind.userStory, id),
          )
        : _TaskBoardBody(
            projectId: widget.projectId,
            selectedId:
                _selected?.kind == EntityKind.task ? _selected?.id : null,
            onSelect: (id) => _select(EntityKind.task, id),
          );
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<BoardCubit, BoardState>(
          builder: (context, state) {
            final extras = <Crumb>[];
            if (widget.mode == _BoardViewMode.stories &&
                state is BoardLoaded) {
              final m = state.milestones.firstWhere(
                (m) => m.id == state.milestoneId,
                orElse: () => state.milestones.first,
              );
              extras.add(Crumb(label: m.name));
            }
            return ProjectSectionBreadcrumb(
              projectId: widget.projectId,
              currentLabel: t.boardTitle,
              sectionRoute: extras.isEmpty
                  ? null
                  : Routes.projectBoardFor(widget.projectId),
              extraCrumbs: extras,
            );
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<_BoardViewMode>(
              segments: [
                ButtonSegment(
                  value: _BoardViewMode.stories,
                  label: Text(t.boardViewStories),
                  icon: const Icon(Icons.bookmark_outline, size: 16),
                ),
                ButtonSegment(
                  value: _BoardViewMode.tasks,
                  label: Text(t.boardViewTasks),
                  icon: const Icon(Icons.task_alt, size: 16),
                ),
              ],
              selected: {widget.mode},
              onSelectionChanged: (s) => widget.onModeChanged(s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          if (widget.mode == _BoardViewMode.stories)
            BlocBuilder<BoardCubit, BoardState>(
              builder: (context, state) {
                if (state is! BoardLoaded) return const SizedBox.shrink();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MilestonePicker(state: state),
                    IconButton(
                      icon: const Icon(Icons.bookmark_outline),
                      tooltip: t.boardSavedViewsTooltip,
                      onPressed: () => openSavedViewsMenu(context, state),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune),
                      tooltip: t.boardFiltersTooltip,
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      endDrawer: widget.mode == _BoardViewMode.stories
          ? const BoardFiltersDrawer()
          : null,
      body: Row(
        children: [
          Expanded(child: body),
          if (_selected != null) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 420,
              child: _BoardDetailsPanel(
                key: ValueKey('${_selected!.kind}:${_selected!.id}'),
                projectId: widget.projectId,
                kind: _selected!.kind,
                entityId: _selected!.id,
                onClose: _clearSelection,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stories view — user stories grouped by us_status, scoped to the active
// milestone.
// ---------------------------------------------------------------------------

class _StoryBoardBody extends StatelessWidget {
  const _StoryBoardBody({
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
    return BlocBuilder<BoardCubit, BoardState>(
      builder: (context, state) {
        if (state is BoardLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is BoardEmpty) {
          return EmptyState(
            icon: Icons.flag_outlined,
            title: t.boardTitle,
            body: t.boardNeedsMilestone,
          );
        }
        if (state is BoardFailed) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.boardLoadFailed),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => context.read<BoardCubit>().load(),
                  child: Text(t.actionRetry),
                ),
              ],
            ),
          );
        }
        if (state is BoardLoaded) {
          return _StoriesLoaded(
            state: state,
            projectId: projectId,
            selectedId: selectedId,
            onSelect: onSelect,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _MilestonePicker extends StatelessWidget {
  const _MilestonePicker({required this.state});
  final BoardLoaded state;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: state.milestoneId,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: [
        for (final m in state.milestones)
          DropdownMenuItem<String>(
            value: m.id,
            child: Text(
              m.closed ? '${m.name} (closed)' : m.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        context.read<BoardCubit>().switchMilestone(v);
      },
    );
  }
}

class _StoriesLoaded extends StatelessWidget {
  const _StoriesLoaded({
    required this.state,
    required this.projectId,
    required this.selectedId,
    required this.onSelect,
  });
  final BoardLoaded state;
  final String projectId;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        if (state.staleData)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.backlogStaleNotice)),
                ],
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final col in state.visibleColumns)
                  _StoryColumn(
                    column: col,
                    projectId: projectId,
                    selectedId: selectedId,
                    onSelect: onSelect,
                  ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryColumn extends StatelessWidget {
  const _StoryColumn({
    required this.column,
    required this.projectId,
    required this.selectedId,
    required this.onSelect,
  });
  final BoardColumn column;
  final String projectId;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        context.read<BoardCubit>().moveCard(
          storyId: details.data,
          targetStatusId: column.status?.id,
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
                statusColor: column.status?.color ?? '',
                title: column.status?.name ?? t.boardColumnNoStatus,
                count: column.userStories.length,
              ),
              const Divider(height: 12),
              for (final card in column.userStories)
                _StoryCard(
                  card: card,
                  projectId: projectId,
                  selected: card.story.id == selectedId,
                  onTap: () => onSelect(card.story.id),
                ),
              if (column.userStories.isEmpty) _EmptyColumnNote(label: t.boardEmptyColumn),
            ],
          ),
        );
      },
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.card,
    required this.projectId,
    required this.selected,
    required this.onTap,
  });
  final BoardCard card;
  final String projectId;
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
              Align(
                alignment: Alignment.centerLeft,
                child: IssueKeyChip(text: 'US-${card.story.reference}'),
              ),
              const SizedBox(height: 6),
              Text(
                card.story.subject,
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (card.tasks.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.checklist_outlined,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${card.tasks.length}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // Plain `Draggable` (not `LongPressDraggable`) so mouse-driven platforms
    // (web / desktop) start the drag on pointer-down + move without a hold
    // gesture. Flutter's gesture arena disambiguates this from the
    // InkWell's tap, so tap-to-open still works.
    return Draggable<String>(
      data: card.story.id,
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

// ---------------------------------------------------------------------------
// Tasks view — every project task grouped by task_status (no sprint scope).
// ---------------------------------------------------------------------------

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
    final buckets = state.bucketed;
    return Column(
      children: [
        if (state.staleData)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.backlogStaleNotice)),
                ],
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final status in state.statuses)
                  _TaskColumn(
                    status: status,
                    tasks: buckets[status.id] ?? const [],
                    projectId: projectId,
                    selectedId: selectedId,
                    onSelect: onSelect,
                  ),
                _TaskColumn(
                  status: null,
                  tasks: buckets[null] ?? const [],
                  projectId: projectId,
                  selectedId: selectedId,
                  onSelect: onSelect,
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.status,
    required this.tasks,
    required this.projectId,
    required this.selectedId,
    required this.onSelect,
  });

  /// Null for the trailing "no status" column.
  final TaxonomyItem? status;
  final List<Task> tasks;
  final String projectId;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        context.read<TaskBoardCubit>().moveTask(
          taskId: details.data,
          targetStatusId: status?.id,
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
              for (final task in tasks)
                _TaskCard(
                  task: task,
                  projectId: projectId,
                  selected: task.id == selectedId,
                  onTap: () => onSelect(task.id),
                ),
              if (tasks.isEmpty) _EmptyColumnNote(label: t.boardEmptyColumn),
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
    required this.selected,
    required this.onTap,
  });
  final Task task;
  final String projectId;
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
              Align(
                alignment: Alignment.centerLeft,
                child: IssueKeyChip(text: 'T-${task.reference}'),
              ),
              const SizedBox(height: 6),
              Text(
                task.subject,
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
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

// ---------------------------------------------------------------------------
// Shared bits used by both views.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Right-side details panel — opens when a card is clicked. Renders a summary
// card with the entity's key + subject (clickable → full detail page),
// status / type / priority / description preview, and a prominent "Open"
// button. Reload happens on selection change via the panel's ValueKey.
// ---------------------------------------------------------------------------

class _BoardDetailsPanel extends StatefulWidget {
  const _BoardDetailsPanel({
    required this.projectId,
    required this.kind,
    required this.entityId,
    required this.onClose,
    super.key,
  });

  final String projectId;
  final EntityKind kind;
  final String entityId;
  final VoidCallback onClose;

  @override
  State<_BoardDetailsPanel> createState() => _BoardDetailsPanelState();
}

class _BoardDetailsPanelState extends State<_BoardDetailsPanel> {
  late Future<_PanelData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PanelData?> _load() async {
    final backlog = getIt<BacklogRepository>();
    final catalog = getIt<CatalogRepository>();
    final taxonomy = <TaxonomyItem>[];
    for (final k in [
      TaxonomyKind.usStatus,
      TaxonomyKind.taskStatus,
      TaxonomyKind.issueStatus,
      TaxonomyKind.issueType,
      TaxonomyKind.priority,
      TaxonomyKind.severity,
      TaxonomyKind.point,
    ]) {
      taxonomy.addAll(
        (await catalog.listTaxonomy(widget.projectId, k)).valueOrNull ?? [],
      );
    }
    final byId = {for (final t in taxonomy) t.id: t};
    switch (widget.kind) {
      case EntityKind.userStory:
        final us =
            (await backlog.getUserStory(widget.projectId, widget.entityId))
                .valueOrNull;
        if (us == null) return null;
        return _PanelData(
          key: 'US-${us.reference}',
          subject: us.subject,
          description: us.description,
          rows: [
            _PanelRow('Status', byId[us.statusId]?.name ?? '—'),
            _PanelRow('Points', byId[us.pointsId]?.name ?? '—'),
          ],
        );
      case EntityKind.task:
        final task =
            (await backlog.getTask(widget.projectId, widget.entityId))
                .valueOrNull;
        if (task == null) return null;
        return _PanelData(
          key: 'T-${task.reference}',
          subject: task.subject,
          description: task.description,
          rows: [
            _PanelRow('Status', byId[task.statusId]?.name ?? '—'),
          ],
        );
      case EntityKind.epic:
        final epic =
            (await backlog.getEpic(widget.projectId, widget.entityId))
                .valueOrNull;
        if (epic == null) return null;
        return _PanelData(
          key: 'EPIC-${epic.reference}',
          subject: epic.subject,
          description: epic.description,
          rows: [
            _PanelRow('Status', byId[epic.statusId]?.name ?? '—'),
          ],
        );
      case EntityKind.issue:
        final issue =
            (await backlog.getIssue(widget.projectId, widget.entityId))
                .valueOrNull;
        if (issue == null) return null;
        return _PanelData(
          key: 'ISSUE-${issue.reference}',
          subject: issue.subject,
          description: issue.description,
          rows: [
            _PanelRow('Status', byId[issue.statusId]?.name ?? '—'),
            _PanelRow('Type', byId[issue.typeId]?.name ?? '—'),
            _PanelRow('Priority', byId[issue.priorityId]?.name ?? '—'),
            _PanelRow('Severity', byId[issue.severityId]?.name ?? '—'),
          ],
        );
    }
  }

  void _openFullPage() {
    context.go(
      Routes.entityDetailFor(
        widget.projectId,
        widget.kind,
        widget.entityId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: FutureBuilder<_PanelData?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      AppLocalizations.of(context).entityDetailLoadFailed,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            );
          }
          return _PanelBody(
            data: data,
            onClose: widget.onClose,
            onOpen: _openFullPage,
          );
        },
      ),
    );
  }
}

class _PanelData {
  const _PanelData({
    required this.key,
    required this.subject,
    required this.description,
    required this.rows,
  });
  final String key;
  final String subject;
  final String description;
  final List<_PanelRow> rows;
}

class _PanelRow {
  const _PanelRow(this.label, this.value);
  final String label;
  final String value;
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({
    required this.data,
    required this.onClose,
    required this.onOpen,
  });
  final _PanelData data;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              IssueKeyChip(text: data.key),
              const Spacer(),
              IconButton(
                tooltip: AppLocalizations.of(context).actionOpenDetail,
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: onOpen,
              ),
              IconButton(
                tooltip: AppLocalizations.of(context).actionCancel,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        // Subject — Jira pattern: clicking the title navigates to full
        // page; status pills / chips sit in the body below.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                data.subject,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in data.rows) ...[
                  _PanelKvRow(label: r.label, value: r.value),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).panelDescription,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (data.description.isEmpty)
                  Text(
                    AppLocalizations.of(context).descriptionPlaceholder,
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Text(
                    data.description,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 20,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            onPressed: onOpen,
            label: Text(AppLocalizations.of(context).actionOpenDetail),
          ),
        ),
      ],
    );
  }
}

class _PanelKvRow extends StatelessWidget {
  const _PanelKvRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
