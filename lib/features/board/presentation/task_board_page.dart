import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/presentation/cubits/task_board_cubit.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Task-only board: columns from `task_status` taxonomy, cards from every
/// task in the project. Drag a card to move it between status columns —
/// PATCHes `task.status_id` with ETag round-trip. Optimistic; rolls back
/// on 409.
class TaskBoardPage extends StatelessWidget {
  const TaskBoardPage({required this.projectId, super.key});
  final String projectId;

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
                projectId: projectId,
                currentUserId: profile.id,
              )..load(),
            ),
            BlocProvider<TaskBoardCubit>(
              create: (_) => TaskBoardCubit(
                repo: getIt<BacklogRepository>(),
                catalog: getIt<CatalogRepository>(),
                projectId: projectId,
              )..load(),
            ),
          ],
          child: _View(projectId: projectId),
        );
      },
    );
  }
}

class _View extends StatelessWidget {
  const _View({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.taskBoardTitle)),
      body: BlocBuilder<TaskBoardCubit, TaskBoardState>(
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
          return _Loaded(state: state, projectId: projectId);
        },
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.projectId});
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
                  _Column(
                    status: status,
                    tasks: buckets[status.id] ?? const [],
                    projectId: projectId,
                  ),
                _Column(
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

class _Column extends StatelessWidget {
  const _Column({
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
              Row(
                children: [
                  HexColorDot(hex: status?.color ?? '', size: 10),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (status?.name ?? t.boardColumnNoStatus).toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 12),
              for (final task in tasks)
                _TaskCard(task: task, projectId: projectId),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      t.boardEmptyColumn,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
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
