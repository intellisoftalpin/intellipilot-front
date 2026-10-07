import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/cubits/all_milestones_cubit.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_detail_sheet.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_gantt.dart';
import 'package:intellipilot/features/profile/presentation/widgets/profile_gate.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Milestones across every project the user may see them in, as one
/// timeline. View only: nothing is created here, but a row still opens the
/// usual detail sidebar, editable wherever the user's project role allows.
class AllMilestonesPage extends StatelessWidget {
  const AllMilestonesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileGate(
      builder: (context, profile) => BlocProvider<AllMilestonesCubit>(
        create: (_) {
          final c = AllMilestonesCubit(repo: getIt<MilestonesRepository>());
          unawaited(c.load());
          return c;
        },
        child: _AllMilestonesView(userId: profile.id),
      ),
    );
  }
}

/// Per-device preferences for this page, in the Hive `ui` box like the
/// project page's.
class _Prefs {
  _Prefs() : _storage = getIt(instanceName: HiveBoxes.ui);
  final KeyValueStorage _storage;

  static const _zoomKey = 'milestones.zoom:all';
  static const _groupingKey = 'milestones.grouping:all';

  double get zoom {
    final raw = _storage.get<double>(_zoomKey);
    if (raw == null || raw.isNaN) return GanttZoom.initial;
    return raw.clamp(GanttZoom.min, GanttZoom.max);
  }

  Future<void> setZoom(double v) => _storage.set<double>(_zoomKey, v);

  GanttGrouping get grouping =>
      _storage.get<String>(_groupingKey) == GanttGrouping.byProject.name
      ? GanttGrouping.byProject
      : GanttGrouping.chronological;

  Future<void> setGrouping(GanttGrouping g) =>
      _storage.set<String>(_groupingKey, g.name);
}

class _AllMilestonesView extends StatefulWidget {
  const _AllMilestonesView({required this.userId});
  final String userId;

  @override
  State<_AllMilestonesView> createState() => _AllMilestonesViewState();
}

class _AllMilestonesViewState extends State<_AllMilestonesView> {
  final _prefs = _Prefs();
  late double _zoom = _prefs.zoom;
  late GanttGrouping _grouping = _prefs.grouping;
  final _ganttController = MilestoneGanttController();

  @override
  void dispose() {
    _ganttController.dispose();
    super.dispose();
  }

  /// Open the sidebar with that milestone's own project permissions — there
  /// is no single project above this page to inherit them from.
  Future<void> _open(GanttEntry e) async {
    final cubit = context.read<AllMilestonesCubit>();
    final project = ProjectDetailCubit(
      repo: getIt<ProjectsRepository>(),
      projectId: e.milestone.projectId,
      currentUserId: widget.userId,
    );
    unawaited(project.load());
    try {
      final result = await showMilestoneDetailSheet(
        context,
        projectId: e.milestone.projectId,
        milestoneId: e.milestone.id,
        projectCubit: project,
      );
      if (result.changed || result.deleted) await cubit.load();
    } finally {
      await project.close();
    }
  }

  Future<void> _setZoom(double v) async {
    setState(() => _zoom = v);
    await _prefs.setZoom(v);
  }

  Future<void> _setGrouping(GanttGrouping g) async {
    setState(() => _grouping = g);
    await _prefs.setGrouping(g);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.milestonesTitle),
        actions: [
          SegmentedButton<GanttGrouping>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(
                value: GanttGrouping.chronological,
                icon: const Icon(Icons.sort, size: 18),
                tooltip: t.milestonesOrderChronological,
              ),
              ButtonSegment(
                value: GanttGrouping.byProject,
                icon: const Icon(Icons.workspaces_outline, size: 18),
                tooltip: t.milestonesOrderByProject,
              ),
            ],
            selected: {_grouping},
            onSelectionChanged: (s) => _setGrouping(s.first),
          ),
          const SizedBox(width: 8),
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
      ),
      body: BlocBuilder<AllMilestonesCubit, AllMilestonesState>(
        builder: (context, state) {
          switch (state) {
            case AllMilestonesLoading():
              return const Center(child: CircularProgressIndicator());
            case AllMilestonesFailed():
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.milestonesLoadFailed),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () =>
                          context.read<AllMilestonesCubit>().load(),
                      child: Text(t.actionRetry),
                    ),
                  ],
                ),
              );
            case AllMilestonesLoaded():
              break;
          }
          if (state.items.isEmpty && state.completedCount == 0) {
            return EmptyState(
              icon: Icons.flag_outlined,
              title: t.milestonesTitle,
              body: t.milestonesAllEmpty,
            );
          }
          GanttEntry entry(MilestoneOverview o) => GanttEntry(
            milestone: o.milestone,
            color:
                parseProjectColor(o.project.color) ?? theme.colorScheme.primary,
            taskTotal: o.taskTotal,
            taskClosed: o.taskClosed,
            epicCount: o.epicCount,
            project: o.project,
          );
          // The API strips business release dates per project already, so
          // any date present here is one the viewer may see.
          final anyBusiness = state.items.any(
            (o) => o.milestone.businessReleaseDate != null,
          );
          final cubit = context.read<AllMilestonesCubit>();
          return Column(
            children: [
              MilestoneGanttLegend(showBusinessRelease: anyBusiness),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _zoom),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, _) => MilestoneGantt(
                    open: state.open.map(entry).toList(),
                    completed: state.completed.map(entry).toList(),
                    completedCount: state.completedCount,
                    completedExpanded: state.completedExpanded,
                    completedLoading: state.completedLoading,
                    onToggleCompleted: cubit.toggleCompleted,
                    zoom: scale,
                    showBusinessRelease: true,
                    grouping: _grouping,
                    controller: _ganttController,
                    onOpen: _open,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
