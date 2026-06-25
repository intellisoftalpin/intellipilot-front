import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/dtos/board_dtos.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/cubits/milestone_detail_cubit.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class MilestoneDetailPage extends StatelessWidget {
  const MilestoneDetailPage({
    required this.projectId,
    required this.milestoneId,
    super.key,
  });
  final String projectId;
  final String milestoneId;

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
            body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
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
            BlocProvider<MilestoneDetailCubit>(
              create: (_) {
                final c = MilestoneDetailCubit(
                  milestones: getIt<MilestonesRepository>(),
                  backlog: getIt<BacklogRepository>(),
                  projectId: projectId,
                  milestoneId: milestoneId,
                );
                unawaited(c.load());
                return c;
              },
            ),
          ],
          child: _DetailView(projectId: projectId),
        );
      },
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: BlocBuilder<MilestoneDetailCubit, MilestoneDetailState>(
            builder: (_, s) {
              final name = s is MilestoneDetailLoaded
                  ? s.milestone.name
                  : t.milestoneDetailTitle;
              return ProjectSectionBreadcrumb(
                projectId: projectId,
                currentLabel: t.milestonesTitle,
                sectionRoute: Routes.projectMilestonesFor(projectId),
                extraCrumbs: [Crumb(label: name)],
              );
            },
          ),
          actions: [
            BlocBuilder<MilestoneDetailCubit, MilestoneDetailState>(
              builder: (context, state) {
                if (state is! MilestoneDetailLoaded) {
                  return const SizedBox.shrink();
                }
                if (state.milestone.closed) return const SizedBox.shrink();
                final detail = context.watch<ProjectDetailCubit>().state;
                final canModify =
                    detail is ProjectDetailLoaded &&
                    detail.has(Permission.milestoneModify);
                if (!canModify) return const SizedBox.shrink();
                return TextButton.icon(
                  icon: const Icon(Icons.lock_outline),
                  onPressed: state.busy ? null : () => _close(context, state),
                  label: Text(t.milestoneCloseAction),
                );
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: t.milestoneTabStats),
              Tab(text: t.milestoneTabScope),
              Tab(text: t.milestoneTabBoard),
            ],
          ),
        ),
        body: BlocBuilder<MilestoneDetailCubit, MilestoneDetailState>(
          builder: (context, state) {
            if (state is MilestoneDetailLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is MilestoneDetailFailed) {
              return Center(child: Text(t.milestoneLoadFailed));
            }
            if (state is! MilestoneDetailLoaded) {
              return const SizedBox.shrink();
            }
            return TabBarView(
              children: [
                _StatsTab(state: state),
                _ScopeTab(state: state, projectId: projectId),
                _BoardTab(
                  projectId: projectId,
                  milestoneId: state.milestone.id,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _close(
    BuildContext context,
    MilestoneDetailLoaded state,
  ) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<MilestoneDetailCubit>();
    final unfinished = state.openInScope.length;
    final move = await showDialog<bool?>(
      context: context,
      builder: (ctx) {
        var moveToBacklog = unfinished > 0;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(t.milestoneCloseTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.milestoneCloseSummary(unfinished)),
                if (unfinished > 0) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: moveToBacklog,
                    title: Text(t.milestoneCloseMoveToBacklog),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) =>
                        setState(() => moveToBacklog = v ?? false),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(t.actionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(moveToBacklog),
                child: Text(t.milestoneCloseAction),
              ),
            ],
          ),
        );
      },
    );
    if (move == null) return;
    await cubit.closeSprint(moveUnfinishedToBacklog: move);
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.state});
  final MilestoneDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = state.stats;
    final detail = context.watch<ProjectDetailCubit>().state;
    final canManage =
        detail is ProjectDetailLoaded && detail.has(Permission.milestoneModify);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _StatCard(
          title: t.milestoneStatPoints,
          done: s.completedPoints.toStringAsFixed(1),
          total: s.totalPoints.toStringAsFixed(1),
          fraction: s.pointsFraction,
        ),
        const SizedBox(height: 12),
        _StatCard(
          title: t.milestoneStatTasks,
          done: '${s.completedTasks}',
          total: '${s.totalTasks}',
          fraction: s.tasksFraction,
        ),
        const SizedBox(height: 12),
        _EpicsCard(state: state, canManage: canManage),
      ],
    );
  }
}

/// The epics composing this milestone, with a manager to add/remove epics.
class _EpicsCard extends StatelessWidget {
  const _EpicsCard({required this.state, required this.canManage});
  final MilestoneDetailLoaded state;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final inMilestone = state.epicsInMilestone;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bookmarks_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t.railEpics, style: theme.textTheme.titleMedium),
                ),
                if (canManage)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(t.milestoneManageEpics),
                    onPressed: state.busy ? null : () => _manage(context),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (inMilestone.isEmpty)
              Text(
                t.milestoneNoEpics,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final e in inMilestone)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_outline, size: 18),
                  title: Text('EPIC-${e.reference}  ${e.subject}'),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _manage(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<MilestoneDetailCubit>();
    final selected = {for (final e in state.epicsInMilestone) e.id};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t.milestoneManageEpics),
          content: SizedBox(
            width: 420,
            child: state.epics.isEmpty
                ? Text(t.epicsEmpty)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final e in state.epics)
                          CheckboxListTile(
                            value: selected.contains(e.id),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text('EPIC-${e.reference}  ${e.subject}'),
                            onChanged: (on) => setState(() {
                              if (on ?? false) {
                                selected.add(e.id);
                              } else {
                                selected.remove(e.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: Text(t.actionSave),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await cubit.setEpics(result.toList());
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.done,
    required this.total,
    required this.fraction,
  });
  final String title;
  final String done;
  final String total;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '$done / $total',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction ?? 0),
          ],
        ),
      ),
    );
  }
}

class _ScopeTab extends StatelessWidget {
  const _ScopeTab({required this.state, required this.projectId});
  final MilestoneDetailLoaded state;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ScopeColumn(
              title: t.milestoneScopeBacklog,
              stories: state.backlog,
              actionLabel: t.milestoneScopeAdd,
              actionIcon: Icons.arrow_forward,
              onAction: (id) =>
                  context.read<MilestoneDetailCubit>().addToScope(id),
              projectId: projectId,
            ),
          ),
          const VerticalDivider(),
          Expanded(
            child: _ScopeColumn(
              title: t.milestoneScopeIn,
              stories: state.scope,
              actionLabel: t.milestoneScopeRemove,
              actionIcon: Icons.arrow_back,
              onAction: (id) =>
                  context.read<MilestoneDetailCubit>().removeFromScope(id),
              projectId: projectId,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeColumn extends StatelessWidget {
  const _ScopeColumn({
    required this.title,
    required this.stories,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.projectId,
  });
  final String title;
  final List<Issue> stories;
  final String actionLabel;
  final IconData actionIcon;
  final Future<bool> Function(String storyId) onAction;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(
          child: stories.isEmpty
              ? Center(
                  child: Text(
                    t.milestoneScopeEmpty,
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  itemCount: stories.length,
                  itemBuilder: (context, i) {
                    final s = stories[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(s.subject),
                        subtitle: Text('US-${s.reference}'),
                        onTap: () => context.go(
                          Routes.entityDetailFor(
                            projectId,
                            EntityKind.issue,
                            s.id,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(actionIcon),
                          tooltip: actionLabel,
                          onPressed: () => onAction(s.id),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Embedded board view, scoped to this milestone. Lighter than the full
/// `BoardPage`: no milestone picker, no saved-views menu — the parent page
/// already provides those affordances.
class _BoardTab extends StatelessWidget {
  const _BoardTab({required this.projectId, required this.milestoneId});
  final String projectId;
  final String milestoneId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<BoardSnapshot?>(
      future: getIt<BoardRepository>()
          .load(projectId, milestoneId)
          .then((r) => r.valueOrNull),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final board = snap.data;
        if (board == null) {
          return Center(child: Text(t.boardLoadFailed));
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final col in board.columns)
                Container(
                  width: 240,
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        col.status?.name ?? t.boardColumnNoStatus,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Divider(height: 12),
                      for (final card in col.issues)
                        Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            title: Text(card.issue.subject),
                            subtitle: Text('#${card.issue.reference}'),
                            onTap: () => context.go(
                              Routes.entityDetailFor(
                                projectId,
                                EntityKind.issue,
                                card.issue.id,
                              ),
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
