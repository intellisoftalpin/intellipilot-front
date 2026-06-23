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
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_page.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
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
        final (profile, members) = snap.data ?? (null, const <String, UserRef>{});
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

  void _select(String id) => setState(() => _selectedId = id);
  void _clearSelection() => setState(() => _selectedId = null);

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
          if (_selectedId != null) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 420,
              child: _BoardDetailsPanel(
                key: ValueKey('issue:$_selectedId'),
                projectId: widget.projectId,
                kind: EntityKind.issue,
                entityId: _selectedId!,
                onClose: _clearSelection,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Search box + optional Sprint filter, shown in the app bar.
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: cubit.setSearch,
              ),
            ),
            const SizedBox(width: 8),
            if (state.milestones.isNotEmpty)
              DropdownButton<String?>(
                value: state.sprintFilter,
                hint: Text(t.boardSprintAll),
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(t.boardSprintAll),
                  ),
                  for (final m in state.milestones)
                    DropdownMenuItem<String?>(
                      value: m.id,
                      child: Text(m.name),
                    ),
                ],
                onChanged: cubit.setSprintFilter,
              ),
          ],
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
        _BoardFilterBar(state: state),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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

/// Horizontal row of filter dropdowns (assignee, epic, label, component,
/// category) below the app bar. Each dropdown is `null` = no filter.
class _BoardFilterBar extends StatelessWidget {
  const _BoardFilterBar({required this.state});
  final TaskBoardLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cubit = context.read<TaskBoardCubit>();
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            _FilterDropdown<String>(
              hint: t.boardFilterAssignee,
              value: state.assigneeFilter,
              items: [
                for (final id in state.assigneeIds)
                  (id, MembersScope.user(context, id)?.displayName ?? id),
              ],
              onChanged: cubit.setAssigneeFilter,
            ),
            const SizedBox(width: 8),
            _FilterDropdown<String>(
              hint: t.boardFilterEpic,
              value: state.epicFilter,
              items: [
                for (final e in state.epics)
                  (e.id, 'EPIC-${e.reference} · ${e.subject}'),
              ],
              onChanged: cubit.setEpicFilter,
            ),
            const SizedBox(width: 8),
            _FilterDropdown<String>(
              hint: t.boardFilterLabel,
              value: state.labelFilter,
              items: [for (final l in state.labels) (l.id, l.name)],
              onChanged: cubit.setLabelFilter,
            ),
            const SizedBox(width: 8),
            _FilterDropdown<String>(
              hint: t.boardFilterComponent,
              value: state.componentFilter,
              items: [for (final c in state.components) (c.id, c.name)],
              onChanged: cubit.setComponentFilter,
            ),
            const SizedBox(width: 8),
            _FilterDropdown<String>(
              hint: t.boardFilterCategory,
              value: state.categoryFilter,
              items: [
                for (final c in IssueCategory.values) (c.wire, c.label),
              ],
              onChanged: cubit.setCategoryFilter,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact "All / pick one" dropdown chip used in the board filter bar.
/// Each item is an `(id, label)` record; a leading "All" entry clears it.
class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String hint;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final active = value != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
        color: active ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          hint: Text(hint, style: theme.textTheme.bodyMedium),
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          items: [
            DropdownMenuItem<T?>(value: null, child: Text(t.boardFilterAll)),
            for (final (id, label) in items)
              DropdownMenuItem<T?>(
                value: id,
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selectedItemBuilder: (_) => [
            Text(hint),
            for (final (_, label) in items)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
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
  final List<Issue> tasks;
  final String projectId;
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
    required this.selected,
    required this.onTap,
  });
  final Issue task;
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
              Row(
                children: [
                  IssueKeyChip(text: '#${task.reference}'),
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

// ---------------------------------------------------------------------------
// Right-side details panel — opens when a card is clicked. Embeds the full
// EntityDetailPage so the panel renders the same edit affordances,
// description, links, attachments, and activity stream the standalone
// detail page shows.
// ---------------------------------------------------------------------------

class _BoardDetailsPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return EntityDetailPage(
      projectId: projectId,
      kind: kind,
      entityId: entityId,
      onClose: onClose,
      onOpen: () => GoRouter.of(context).go(
        Routes.entityDetailFor(projectId, kind, entityId),
      ),
    );
  }
}
