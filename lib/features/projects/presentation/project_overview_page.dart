import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';
import 'package:intellipilot/core/widgets/error_view.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';
import 'package:intellipilot/features/dashboard/domain/dashboard_repository.dart';
import 'package:intellipilot/features/dashboard/presentation/cubits/project_dashboard_cubit.dart';
import 'package:intellipilot/features/dashboard/presentation/widgets/dashboard_widgets.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/features/projects/presentation/widgets/permission_debug_overlay.dart';
import 'package:intellipilot/features/projects/presentation/widgets/permission_gate.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/availability_card.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_warning_card.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class ProjectOverviewPage extends StatelessWidget {
  const ProjectOverviewPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _loadProfile(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) {
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).errUnknown),
            ),
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
            BlocProvider<ProjectDashboardCubit>(
              create: (_) {
                final c = ProjectDashboardCubit(
                  repo: getIt<DashboardRepository>(),
                  projectId: projectId,
                );
                unawaited(c.load());
                return c;
              },
            ),
          ],
          child: _ProjectOverviewView(currentUserId: profile.id),
        );
      },
    );
  }

  Future<UserProfile?> _loadProfile() async {
    final res = await getIt<ProfileRepository>().getProfile();
    return res.valueOrNull;
  }
}

class _ProjectOverviewView extends StatelessWidget {
  const _ProjectOverviewView({required this.currentUserId});
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
          builder: (_, s) {
            final projectName = s is ProjectDetailLoaded
                ? s.project.name
                : t.projectOverviewTitle;
            return BreadcrumbBar(
              crumbs: [
                Crumb(
                  label: t.projectsTitle,
                  onTap: () => context.go(Routes.projects),
                ),
                Crumb(label: projectName),
              ],
            );
          },
        ),
        actions: [
          PermissionGate(
            permission: Permission.projectModify,
            child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
              builder: (context, s) {
                if (s is! ProjectDetailLoaded) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: t.projectSettingsTitle,
                  onPressed: () => context.go(
                    Routes.projectSettingsFor(s.project.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
            builder: (context, state) {
              if (state is ProjectDetailLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is ProjectDetailFailed) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.projectLoadFailed),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () =>
                            context.read<ProjectDetailCubit>().load(),
                        child: Text(t.actionRetry),
                      ),
                    ],
                  ),
                );
              }
              if (state is ProjectDetailLoaded) {
                return _Overview(
                  state: state,
                  currentUserId: currentUserId,
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const PermissionDebugOverlay(),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.state, required this.currentUserId});
  final ProjectDetailLoaded state;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final project = state.project;
    final maxWidth = responsiveValue<double>(
      context,
      compact: double.infinity,
      medium: 720,
      expanded: 960,
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        project.slug,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(_visibilityLabel(t, project.visibility))),
              ],
            ),
            const SizedBox(height: 16),
            _ProjectDashboardBlock(
              projectId: project.id,
              currentUserId: currentUserId,
            ),
            const SizedBox(height: 16),
            const TimesheetWarningCard(),
            const SizedBox(height: 8),
            AvailabilityCard(projectId: project.id),
            const SizedBox(height: 16),
            if (project.description.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(project.description),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              t.projectFeaturesTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _FeatureChip(
                  label: t.projectFeatureBacklog,
                  on: project.backlogEnabled,
                ),
                _FeatureChip(
                  label: t.projectFeatureKanban,
                  on: project.kanbanEnabled,
                ),
                _FeatureChip(
                  label: t.projectFeatureEpics,
                  on: project.epicsEnabled,
                ),
                _FeatureChip(
                  label: t.projectFeatureWiki,
                  on: project.wikiEnabled,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.list_alt),
                  onPressed: () =>
                      context.go(Routes.projectBacklogFor(project.id)),
                  label: Text(t.actionOpenBacklog),
                ),
                // One Board button — Stories/Tasks toggle lives in the
                // board's app bar so we no longer need a separate
                // 'Open task board' entry here.
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.view_kanban_outlined),
                  onPressed: () =>
                      context.go(Routes.projectBoardFor(project.id)),
                  label: Text(t.actionOpenBoard),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: () =>
                      context.go(Routes.projectMilestonesFor(project.id)),
                  label: Text(t.actionOpenMilestones),
                ),
                if (project.wikiEnabled)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.menu_book_outlined),
                    onPressed: () =>
                        context.go(Routes.projectWikiFor(project.id)),
                    label: Text(t.actionOpenWiki),
                  ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.bug_report_outlined),
                  onPressed: () =>
                      context.go(Routes.projectIssuesFor(project.id)),
                  label: Text(t.actionOpenIssues),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _visibilityLabel(AppLocalizations t, ProjectVisibility v) =>
      switch (v) {
        ProjectVisibility.private => t.projectVisibilityPrivate,
        ProjectVisibility.internal => t.projectVisibilityInternal,
        ProjectVisibility.publicReadonly => t.projectVisibilityPublicReadonly,
      };
}

class _ProjectDashboardBlock extends StatelessWidget {
  const _ProjectDashboardBlock({
    required this.projectId,
    required this.currentUserId,
  });
  final String projectId;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProjectDashboardCubit, ProjectDashboardState>(
      builder: (context, state) {
        if (state is ProjectDashboardLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: LoadingIndicator(),
          );
        }
        if (state is ProjectDashboardFailed) {
          return ErrorView(
            failure: state.failure,
            onRetry: () => context.read<ProjectDashboardCubit>().load(),
          );
        }
        if (state is ProjectDashboardLoaded) {
          return _DashboardContent(
            data: state.data,
            projectId: projectId,
            currentUserId: currentUserId,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.data,
    required this.projectId,
    required this.currentUserId,
  });

  final ProjectDashboard data;
  final String projectId;
  final String currentUserId;

  void _go(BuildContext context, String location) => context.go(location);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final categories = [
      for (final c in data.byCategory)
        NamedCount(
          name: _humanizeCategory(c.name),
          color: c.color,
          count: c.count,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            KpiTile(
              label: t.dashKpiOpen,
              value: '${data.open}',
              icon: Icons.radio_button_unchecked,
              onTap: () => _go(context, Routes.projectIssuesFor(projectId)),
            ),
            KpiTile(
              label: t.dashKpiOverdue,
              value: '${data.overdue}',
              icon: Icons.warning_amber_outlined,
              tone: data.overdue > 0 ? theme.colorScheme.error : null,
              onTap: () => _go(
                context,
                Routes.projectIssuesFiltered(projectId, overdue: true),
              ),
            ),
            KpiTile(
              label: t.dashKpiUnassigned,
              value: '${data.unassigned}',
              icon: Icons.person_off_outlined,
              onTap: () => _go(
                context,
                Routes.projectIssuesFiltered(projectId, assignee: 'none'),
              ),
            ),
            KpiTile(
              label: t.dashKpiBugs,
              value: '${data.bugsOpen}',
              icon: Icons.bug_report_outlined,
              onTap: () => _go(context, Routes.projectIssuesFor(projectId)),
            ),
            KpiTile(
              label: t.dashKpiAssigned,
              value: '${data.myAssigned}',
              icon: Icons.assignment_ind_outlined,
              onTap: () => _go(
                context,
                Routes.projectIssuesFiltered(
                  projectId,
                  assignee: currentUserId,
                ),
              ),
            ),
            KpiTile(
              label: t.dashKpiMyOverdue,
              value: '${data.myOverdue}',
              icon: Icons.event_busy_outlined,
              tone: data.myOverdue > 0 ? theme.colorScheme.error : null,
              onTap: () => _go(
                context,
                Routes.projectIssuesFiltered(
                  projectId,
                  assignee: currentUserId,
                  overdue: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DashboardSection(
          title: t.dashBoardTitle,
          icon: Icons.view_kanban_outlined,
          child: StatusBarChart(
            buckets: data.byStatus,
            emptyLabel: t.dashNoWork,
          ),
        ),
        const SizedBox(height: 16),
        DashboardSection(
          title: t.dashMyTasksTitle,
          icon: Icons.assignment_ind_outlined,
          child: StatusBarChart(
            buckets: data.myByStatus,
            emptyLabel: t.dashNoWork,
          ),
        ),
        const SizedBox(height: 16),
        DashboardSection(
          title: t.dashEpicsTitle,
          icon: Icons.flag_outlined,
          child: data.epics.isEmpty
              ? Text(
                  t.dashEpicsEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Column(
                  children: [
                    for (final e in data.epics)
                      EpicProgressTile(
                        epic: e,
                        onTap: () => _go(
                          context,
                          Routes.entityDetailFor(
                            projectId,
                            EntityKind.epic,
                            e.epicId,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        DashboardSection(
          title: t.dashThroughputTitle,
          icon: Icons.show_chart_outlined,
          child: ThroughputChart(weeks: data.throughput),
        ),
        const SizedBox(height: 16),
        DashboardSection(
          title: t.dashByTypeTitle,
          icon: Icons.category_outlined,
          child: BreakdownList(
            items: data.byType,
            emptyLabel: t.dashBreakdownEmpty,
          ),
        ),
        const SizedBox(height: 16),
        DashboardSection(
          title: t.dashByPriorityTitle,
          icon: Icons.low_priority_outlined,
          child: BreakdownList(
            items: data.byPriority,
            emptyLabel: t.dashBreakdownEmpty,
          ),
        ),
        const SizedBox(height: 16),
        DashboardSection(
          title: t.dashByCategoryTitle,
          icon: Icons.workspaces_outline,
          child: BreakdownList(
            items: categories,
            emptyLabel: t.dashBreakdownEmpty,
          ),
        ),
      ],
    );
  }
}

/// `customer_request` → `Customer request`.
String _humanizeCategory(String raw) {
  if (raw.isEmpty) return raw;
  final spaced = raw.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.on});
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        on ? Icons.check_circle_outline : Icons.do_not_disturb_alt,
        size: 16,
        color: on
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      label: Text(label),
    );
  }
}
