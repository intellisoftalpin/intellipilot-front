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

class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.projectId,
    required this.mode,
    required this.onModeChanged,
  });
  final String projectId;
  final _BoardViewMode mode;
  final ValueChanged<_BoardViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<BoardCubit, BoardState>(
          builder: (context, state) {
            final extras = <Crumb>[];
            if (mode == _BoardViewMode.stories && state is BoardLoaded) {
              final m = state.milestones.firstWhere(
                (m) => m.id == state.milestoneId,
                orElse: () => state.milestones.first,
              );
              extras.add(Crumb(label: m.name));
            }
            return ProjectSectionBreadcrumb(
              projectId: projectId,
              currentLabel: t.boardTitle,
              sectionRoute: extras.isEmpty
                  ? null
                  : Routes.projectBoardFor(projectId),
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
              selected: {mode},
              onSelectionChanged: (s) => onModeChanged(s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          if (mode == _BoardViewMode.stories)
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
      endDrawer: mode == _BoardViewMode.stories
          ? const BoardFiltersDrawer()
          : null,
      body: mode == _BoardViewMode.stories
          ? _StoryBoardBody(projectId: projectId)
          : _TaskBoardBody(projectId: projectId),
    );
  }
}

// ---------------------------------------------------------------------------
// Stories view — user stories grouped by us_status, scoped to the active
// milestone.
// ---------------------------------------------------------------------------

class _StoryBoardBody extends StatelessWidget {
  const _StoryBoardBody({required this.projectId});
  final String projectId;

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
          return _StoriesLoaded(state: state, projectId: projectId);
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
  const _StoriesLoaded({required this.state, required this.projectId});
  final BoardLoaded state;
  final String projectId;

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
                  _StoryColumn(column: col, projectId: projectId),
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
  const _StoryColumn({required this.column, required this.projectId});
  final BoardColumn column;
  final String projectId;

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
                _StoryCard(card: card, projectId: projectId),
              if (column.userStories.isEmpty) _EmptyColumnNote(label: t.boardEmptyColumn),
            ],
          ),
        );
      },
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.card, required this.projectId});
  final BoardCard card;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardWidget = Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => context.go(
          Routes.entityDetailFor(
            projectId,
            EntityKind.userStory,
            card.story.id,
          ),
        ),
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
  const _TaskBoardBody({required this.projectId});
  final String projectId;

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
        return _TasksLoaded(state: state, projectId: projectId);
      },
    );
  }
}

class _TasksLoaded extends StatelessWidget {
  const _TasksLoaded({required this.state, required this.projectId});
  final TaskBoardLoaded state;
  final String projectId;

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
                  ),
                _TaskColumn(
                  status: null,
                  tasks: buckets[null] ?? const [],
                  projectId: projectId,
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
  });

  /// Null for the trailing "no status" column.
  final TaxonomyItem? status;
  final List<Task> tasks;
  final String projectId;

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
                _TaskCard(task: task, projectId: projectId),
              if (tasks.isEmpty) _EmptyColumnNote(label: t.boardEmptyColumn),
            ],
          ),
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.projectId});
  final Task task;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardWidget = Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => context.go(
          Routes.entityDetailFor(
            projectId,
            EntityKind.task,
            task.id,
          ),
        ),
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
