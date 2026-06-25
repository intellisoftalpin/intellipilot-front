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

class _Loaded extends StatelessWidget {
  const _Loaded({required this.data});

  final HomeDashboard data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
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
                  tone: data.overdue > 0
                      ? Theme.of(context).colorScheme.error
                      : null,
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
            const SizedBox(height: 16),
            DashboardSection(
              title: l10n.dashMyProjectsTitle,
              icon: Icons.folder_outlined,
              child: _ProjectGrid(projects: data.byProject),
            ),
          ],
        ),
      ),
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

class _ProjectGrid extends StatelessWidget {
  const _ProjectGrid({required this.projects});

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
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final p in projects)
          SizedBox(
            width: 220,
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => context.go(Routes.projectDetailFor(p.projectId)),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.dashOpenCount(p.openCount),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// `18.5` → `18.5`, `18.0` → `18`.
String _days(double v) {
  final r = v.toStringAsFixed(1);
  return r.endsWith('.0') ? r.substring(0, r.length - 2) : r;
}
