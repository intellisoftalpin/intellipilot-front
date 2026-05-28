import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/dtos/board_dtos.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';
import 'package:intellipilot/features/board/presentation/cubits/board_cubit.dart';
import 'package:intellipilot/features/board/presentation/widgets/board_filters_drawer.dart';
import 'package:intellipilot/features/board/presentation/widgets/saved_views_menu.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class BoardPage extends StatelessWidget {
  const BoardPage({required this.projectId, super.key});
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
            BlocProvider<BoardCubit>(
              create: (_) => BoardCubit(
                milestones: getIt<MilestonesRepository>(),
                board: getIt<BoardRepository>(),
                backlog: getIt<BacklogRepository>(),
                projectId: projectId,
              )..load(),
            ),
          ],
          child: _BoardView(projectId: projectId),
        );
      },
    );
  }
}

class _BoardView extends StatelessWidget {
  const _BoardView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<BoardCubit, BoardState>(
          builder: (context, state) {
            if (state is BoardLoaded) {
              final m = state.milestones.firstWhere(
                (m) => m.id == state.milestoneId,
                orElse: () => state.milestones.first,
              );
              return Text('${t.boardTitle} · ${m.name}');
            }
            return Text(t.boardTitle);
          },
        ),
        actions: [
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
      endDrawer: const BoardFiltersDrawer(),
      body: BlocBuilder<BoardCubit, BoardState>(
        builder: (context, state) {
          if (state is BoardLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is BoardEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(t.boardNeedsMilestone, textAlign: TextAlign.center),
                  ],
                ),
              ),
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
            return _Loaded(state: state, projectId: projectId);
          }
          return const SizedBox.shrink();
        },
      ),
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

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.projectId});
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
                  _BoardColumnView(column: col, projectId: projectId),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BoardColumnView extends StatelessWidget {
  const _BoardColumnView({required this.column, required this.projectId});
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
              Row(
                children: [
                  HexColorDot(hex: column.status?.color ?? '', size: 12),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      column.status?.name ?? t.boardColumnNoStatus,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '${column.userStories.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const Divider(height: 12),
              for (final card in column.userStories)
                _CardView(card: card, projectId: projectId),
              if (column.userStories.isEmpty)
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

class _CardView extends StatelessWidget {
  const _CardView({required this.card, required this.projectId});
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
              Text(
                'US-${card.story.reference}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 2),
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
    return LongPressDraggable<String>(
      data: card.story.id,
      delay: const Duration(milliseconds: 200),
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
