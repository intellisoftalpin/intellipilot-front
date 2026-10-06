import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/widgets/error_view.dart';
import 'package:intellipilot/core/widgets/loading_indicator.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';
import 'package:intellipilot/features/dashboard/domain/dashboard_repository.dart';
import 'package:intellipilot/features/dashboard/presentation/cubits/global_dashboard_cubit.dart';
import 'package:intellipilot/features/dashboard/presentation/widgets/dashboard_widgets.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/presentation/widgets/project_avatar.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_warning_card.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Global home dashboard — the user's cross-project plate, shown on app entry.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GlobalDashboardCubit>(
      create: (_) {
        final c = GlobalDashboardCubit(getIt<DashboardRepository>());
        unawaited(c.load());
        return c;
      },
      child: const _GlobalDashboardView(),
    );
  }
}

class _GlobalDashboardView extends StatelessWidget {
  const _GlobalDashboardView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<GlobalDashboardCubit, GlobalDashboardState>(
          builder: (context, state) {
            if (state is GlobalDashboardLoading) {
              return const LoadingIndicator();
            }
            if (state is GlobalDashboardFailed) {
              return ErrorView(
                failure: state.failure,
                onRetry: () => context.read<GlobalDashboardCubit>().load(),
              );
            }
            if (state is GlobalDashboardLoaded) {
              return _Loaded(data: state.data);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

/// From this width the projects move into a column of their own.
const double _kTwoColumnWidth = 1000;

class _Loaded extends StatelessWidget {
  const _Loaded({required this.data});

  final HomeDashboard data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final main = <Widget>[
      const _Greeting(),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          KpiTile(
            label: l10n.dashKpiAssigned,
            value: '${data.assignedTotal}',
            icon: Icons.assignment_ind_outlined,
          ),
          KpiTile(
            label: l10n.dashKpiOverdue,
            value: '${data.overdue}',
            icon: Icons.warning_amber_outlined,
            tone: data.overdue > 0 ? Theme.of(context).colorScheme.error : null,
          ),
          KpiTile(
            label: l10n.dashKpiDueSoon,
            value: '${data.dueSoon}',
            icon: Icons.event_outlined,
          ),
          KpiTile(
            label: l10n.dashKpiVacation,
            value: _days(data.vacationDaysLeft),
            icon: Icons.beach_access_outlined,
          ),
        ],
      ),
      const SizedBox(height: 16),
      const TimesheetWarningCard(),
      const SizedBox(height: 16),
      DashboardSection(
        title: l10n.dashAttentionTitle,
        icon: Icons.priority_high_outlined,
        child: _AttentionList(items: data.attention),
      ),
      const SizedBox(height: 16),
      DashboardSection(
        title: l10n.dashMyWorkTitle,
        icon: Icons.donut_large_outlined,
        child: StatusBarChart(
          buckets: data.byStatus,
          emptyLabel: l10n.dashNoWork,
        ),
      ),
    ];
    final projects = DashboardSection(
      title: l10n.dashMyProjectsTitle,
      icon: Icons.folder_outlined,
      child: _ProjectList(projects: data.byProject),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _kTwoColumnWidth) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [...main, const SizedBox(height: 16), projects],
              ),
            ),
          );
        }
        // Each column scrolls on its own: a long project list must not push
        // the user's work out of view, nor the other way round.
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 12, 24),
                    children: main,
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 24, 24, 24),
                    children: [projects],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<String>(
      future: _name(),
      builder: (context, snap) {
        final name = snap.data ?? '';
        return Text(
          l10n.dashGreeting(name),
          style: theme.textTheme.headlineSmall,
        );
      },
    );
  }

  Future<String> _name() async {
    final res = await getIt<ProfileRepository>().getProfile();
    final p = res.valueOrNull;
    if (p == null) return '';
    return p.fullName.isNotEmpty ? p.fullName : p.username;
  }
}

class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.items});

  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(
        l10n.dashAttentionEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (final it in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              it.overdue ? Icons.error_outline : Icons.schedule_outlined,
              color: it.overdue
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            title: Text(
              '${it.projectSlug}-${it.reference}  ${it.subject}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              it.dueDate == null
                  ? it.statusName
                  : '${it.statusName} · ${l10n.dashDue(it.dueDate!)}',
            ),
            onTap: () => context.go(
              Routes.entityDetailFor(
                it.projectId,
                EntityKind.issue,
                it.issueId,
              ),
            ),
          ),
      ],
    );
  }
}

/// The user's projects, one card each: icon and name. Their order — the
/// projects the user works in most first — comes from the server.
class _ProjectList extends StatelessWidget {
  const _ProjectList({required this.projects});

  final List<ProjectBucket> projects;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (projects.isEmpty) {
      return Text(
        l10n.dashMyProjectsEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in projects.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: () => context.go(Routes.projectDetailFor(p.projectId)),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ProjectAvatar.fromParts(
                      projectId: p.projectId,
                      name: p.name,
                      issuePrefix: p.issuePrefix,
                      color: p.color,
                      hasIcon: p.hasIcon,
                      iconImageUpdatedAt: p.iconImageUpdatedAt,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// `18.5` → `18.5`, `18.0` → `18`.
String _days(double v) {
  final r = v.toStringAsFixed(1);
  return r.endsWith('.0') ? r.substring(0, r.length - 2) : r;
}
