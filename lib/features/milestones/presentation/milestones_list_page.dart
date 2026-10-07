import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/cubits/milestones_list_cubit.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_detail_sheet.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_edit_dialog.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_gantt.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/progress_ring.dart';
import 'package:intellipilot/features/profile/presentation/widgets/profile_gate.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

export 'package:intellipilot/features/milestones/presentation/widgets/milestone_gantt.dart'
    show GanttScale, GanttZoom, MilestonePalette;

/// The milestones screen: a timeline (the default) or a two-column board
/// (in progress / completed), whichever the user last used. Clicking a milestone anywhere opens
/// the detail sidebar — there is no separate milestone screen.
class MilestonesListPage extends StatelessWidget {
  const MilestonesListPage({
    required this.projectId,
    this.openMilestoneId,
    super.key,
  });

  final String projectId;

  /// Deep link: open the sidebar on this milestone as soon as the page mounts.
  final String? openMilestoneId;

  @override
  Widget build(BuildContext context) {
    return ProfileGate(
      key: ValueKey(projectId),
      builder: (context, profile) {
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
            BlocProvider<MilestonesListCubit>(
              create: (_) {
                final c = MilestonesListCubit(
                  repo: getIt<MilestonesRepository>(),
                  backlog: getIt<BacklogRepository>(),
                  projectId: projectId,
                );
                unawaited(c.load());
                return c;
              },
            ),
          ],
          child: _MilestonesView(
            projectId: projectId,
            openMilestoneId: openMilestoneId,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// remembered view + zoom
// ---------------------------------------------------------------------------

/// Per-project, per-device view preferences. Kept local (Hive `ui` box, like
/// the board's collapsed columns) so the page can render its remembered view
/// on the first frame instead of waiting on a round-trip.
class _ViewPrefs {
  _ViewPrefs(this.projectId) : _storage = getIt(instanceName: HiveBoxes.ui);
  final String projectId;
  final KeyValueStorage _storage;

  String get _viewKey => 'milestones.view:$projectId';
  String get _zoomKey => 'milestones.zoom:$projectId';

  /// The timeline is the default; a board choice the user made before it
  /// became one is kept.
  bool get gantt => _storage.get<bool>(_viewKey) ?? true;
  Future<void> setGantt({required bool value}) =>
      _storage.set<bool>(_viewKey, value);

  /// Stored as the scale itself rather than an index, so the remembered value
  /// survives any future change to the range without silently meaning
  /// something else.
  double get zoom {
    final raw = _storage.get<double>(_zoomKey);
    if (raw == null || raw.isNaN) return GanttZoom.initial;
    return raw.clamp(GanttZoom.min, GanttZoom.max);
  }

  Future<void> setZoom(double value) => _storage.set<double>(_zoomKey, value);
}

class _MilestonesView extends StatefulWidget {
  const _MilestonesView({required this.projectId, this.openMilestoneId});
  final String projectId;
  final String? openMilestoneId;

  @override
  State<_MilestonesView> createState() => _MilestonesViewState();
}

class _MilestonesViewState extends State<_MilestonesView> {
  late final _prefs = _ViewPrefs(widget.projectId);
  late bool _gantt = _prefs.gantt;
  late double _zoom = _prefs.zoom;
  final _ganttController = MilestoneGanttController();

  String get projectId => widget.projectId;

  @override
  void dispose() {
    _ganttController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final deepLink = widget.openMilestoneId;
    if (deepLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_open(deepLink, fromDeepLink: true));
      });
    }
  }

  /// Open the sidebar and refresh the page underneath only when something
  /// actually changed.
  ///
  /// Deliberately does **not** navigate to the detail URL on the way in. The
  /// detail route builds its own `MilestonesListPage`, whose `initState` opens
  /// a second sheet on top of this one — so every close revealed another copy
  /// and the panel had to be dismissed twice. Deep links still work: they
  /// arrive on the detail route, open the sheet once, and return to the list
  /// URL on close.
  Future<void> _open(String milestoneId, {bool fromDeepLink = false}) async {
    final cubit = context.read<MilestonesListCubit>();
    final router = GoRouter.of(context);
    final result = await showMilestoneDetailSheet(
      context,
      projectId: projectId,
      milestoneId: milestoneId,
    );
    if (!mounted) return;
    if (fromDeepLink) {
      router.go(Routes.projectMilestonesFor(projectId));
    }
    if (result.deleted) {
      cubit.forget(milestoneId);
    } else if (result.changed) {
      await cubit.load();
    }
  }

  Future<void> _setGantt({required bool value}) async {
    setState(() => _gantt = value);
    await _prefs.setGantt(value: value);
  }

  Future<void> _setZoom(double value) async {
    setState(() => _zoom = value);
    await _prefs.setZoom(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: projectId,
          currentLabel: t.milestonesTitle,
        ),
        actions: [
          if (_gantt) ...[
            TextButton.icon(
              icon: const Icon(Icons.today_outlined, size: 18),
              label: Text(t.milestonesToday),
              onPressed: _ganttController.centerToday,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.zoom_out),
              tooltip: t.milestoneZoomOut,
              onPressed: GanttZoom.canZoomOut(_zoom)
                  ? () => _setZoom(GanttZoom.zoomOut(_zoom))
                  : null,
            ),
            Tooltip(
              message: t.milestoneZoomLabel,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(GanttZoom.label(t, _zoom)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in),
              tooltip: t.milestoneZoomIn,
              onPressed: GanttZoom.canZoomIn(_zoom)
                  ? () => _setZoom(GanttZoom.zoomIn(_zoom))
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  tooltip: t.milestonesViewList,
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.view_timeline_outlined, size: 18),
                  tooltip: t.milestonesViewGantt,
                ),
              ],
              selected: {_gantt},
              onSelectionChanged: (s) => _setGantt(value: s.first),
            ),
          ),
        ],
      ),
      floatingActionButton: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, s) {
          if (s is! ProjectDetailLoaded || !s.has(Permission.milestoneCreate)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewMilestone),
            onPressed: _create,
          );
        },
      ),
      body: BlocBuilder<MilestonesListCubit, MilestonesListState>(
        builder: (context, state) {
          if (state is MilestonesListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is MilestonesListFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.milestonesLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<MilestonesListCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is! MilestonesListLoaded) return const SizedBox.shrink();
          if (state.milestones.isEmpty && state.completedCount == 0) {
            final detail = context.watch<ProjectDetailCubit>().state;
            final canCreate =
                detail is ProjectDetailLoaded &&
                detail.has(Permission.milestoneCreate);
            return EmptyState(
              icon: Icons.flag_outlined,
              title: t.milestonesTitle,
              body: t.milestonesEmpty,
              action: canCreate
                  ? FilledButton.icon(
                      icon: const Icon(Icons.add),
                      onPressed: _create,
                      label: Text(t.actionNewMilestone),
                    )
                  : null,
            );
          }
          final detail = context.watch<ProjectDetailCubit>().state;
          final showBusiness =
              detail is ProjectDetailLoaded &&
              detail.has(Permission.milestoneBusinessReleaseView);
          final color =
              (detail is ProjectDetailLoaded
                  ? parseProjectColor(detail.project.color)
                  : null) ??
              Theme.of(context).colorScheme.primary;
          final cubit = context.read<MilestonesListCubit>();
          if (!_gantt) {
            return _MilestonesBoard(
              state: state,
              onOpen: _open,
              onToggleCompleted: cubit.toggleCompleted,
            );
          }
          GanttEntry entry(Milestone m) {
            final tasks = state.tasksFor(m.id);
            return GanttEntry(
              milestone: m,
              color: color,
              taskTotal: tasks.total,
              taskClosed: tasks.closed,
              epicCount: state.epicCountFor(m.id),
            );
          }

          return Column(
            children: [
              MilestoneGanttLegend(
                showBusinessRelease: showBusiness,
                color: color,
              ),
              Expanded(
                // Animate between scales so a zoom reads as the timeline
                // stretching rather than as the whole chart being replaced.
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _zoom),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, _) => MilestoneGantt(
                    open: state.inProgress.map(entry).toList(),
                    completed: state.completed.map(entry).toList(),
                    completedCount: state.completedCount,
                    completedExpanded: state.completedExpanded,
                    completedLoading: state.completedLoading,
                    onToggleCompleted: cubit.toggleCompleted,
                    zoom: scale,
                    showBusinessRelease: showBusiness,
                    controller: _ganttController,
                    onOpen: (e) => _open(e.milestone.id),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create() async {
    final cubit = context.read<MilestonesListCubit>();
    final body = await showMilestoneEditDialog(context);
    if (body == null) return;
    await cubit.create(body);
  }
}

// ---------------------------------------------------------------------------
// board view — In progress / Completed
// ---------------------------------------------------------------------------

class _MilestonesBoard extends StatelessWidget {
  const _MilestonesBoard({
    required this.state,
    required this.onOpen,
    required this.onToggleCompleted,
  });
  final MilestonesListLoaded state;
  final Future<void> Function(String milestoneId) onOpen;
  final VoidCallback onToggleCompleted;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = [
          _BoardColumn(
            title: t.milestoneColumnInProgress,
            count: state.inProgress.length,
            emptyLabel: t.milestoneColumnInProgressEmpty,
            milestones: state.inProgress,
            state: state,
            onOpen: onOpen,
          ),
          _BoardColumn(
            title: t.milestoneColumnCompleted,
            count: state.completedCount,
            emptyLabel: t.milestoneColumnCompletedEmpty,
            milestones: state.completed,
            state: state,
            onOpen: onOpen,
            // Collapsed until asked for: completed milestones are only
            // fetched once the user expands the column.
            collapsible: true,
            expanded: state.completedExpanded,
            loading: state.completedLoading,
            onToggle: onToggleCompleted,
          ),
        ];
        // Below ~840px the two columns would each be too narrow to read, so
        // they stack instead of shrinking.
        if (constraints.maxWidth < 840) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final c in columns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: c,
                ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in columns) ...[
                Expanded(child: c),
                if (c != columns.last) const SizedBox(width: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.title,
    required this.count,
    required this.emptyLabel,
    required this.milestones,
    required this.state,
    required this.onOpen,
    this.collapsible = false,
    this.expanded = true,
    this.loading = false,
    this.onToggle,
  });
  final String title;
  final int count;
  final String emptyLabel;
  final List<Milestone> milestones;
  final MilestonesListLoaded state;
  final Future<void> Function(String milestoneId) onOpen;
  final bool collapsible;
  final bool expanded;
  final bool loading;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final Widget body;
    if (collapsible && !expanded) {
      body = const SizedBox.shrink();
    } else if (loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (milestones.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          emptyLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in milestones)
            _MilestoneCard(
              milestone: m,
              progress: state.progressFor(m.id),
              epicCount: state.epicCountFor(m.id),
              onTap: () => onOpen(m.id),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (collapsible && count > 0) ...[
                const Spacer(),
                IconButton(
                  tooltip: expanded
                      ? t.milestoneHideCompleted
                      : t.milestoneShowCompleted,
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: onToggle,
                ),
              ],
            ],
          ),
        ),
        body,
      ],
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.milestone,
    required this.progress,
    required this.epicCount,
    required this.onTap,
  });
  final Milestone milestone;
  final double? progress;
  final int epicCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final completed = milestone.closed;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: completed ? theme.colorScheme.surfaceContainerHighest : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProgressRing(value: progress, completed: completed),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      milestone.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: completed
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    RowDates(milestone: milestone),
                    const SizedBox(height: 2),
                    Text(
                      t.milestoneEpicCount(epicCount),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAtRisk(milestone))
                Tooltip(
                  message: t.milestoneOverdue,
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
