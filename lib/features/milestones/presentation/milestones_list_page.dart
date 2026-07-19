import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/cubits/milestones_list_cubit.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_edit_dialog.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:intl/intl.dart';

class MilestonesListPage extends StatelessWidget {
  const MilestonesListPage({required this.projectId, super.key});
  final String projectId;

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
            BlocProvider<MilestonesListCubit>(
              create: (_) {
                final c = MilestonesListCubit(
                  repo: getIt<MilestonesRepository>(),
                  projectId: projectId,
                );
                unawaited(c.load());
                return c;
              },
            ),
          ],
          child: _ListView(projectId: projectId),
        );
      },
    );
  }
}

/// Effective schedule of a milestone for display: a missing start defaults
/// to today, a missing end to start + 7 days. [estimated] marks defaulted
/// values so views can render them as tentative.
({DateTime start, DateTime end, bool estimated}) _effectiveRange(Milestone m) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = m.startDate ?? today;
  final end = m.endDate ?? start.add(const Duration(days: 7));
  return (
    start: start,
    end: end.isBefore(start) ? start : end,
    estimated: m.startDate == null || m.endDate == null,
  );
}

/// Open milestones sorted by nearest effective end date first; closed ones
/// keep their recency order at the bottom.
List<Milestone> _byEndDate(List<Milestone> all) {
  final open = all.where((m) => !m.closed).toList()
    ..sort((a, b) => _effectiveRange(a).end.compareTo(_effectiveRange(b).end));
  final closed = all.where((m) => m.closed).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return [...open, ...closed];
}

class _ListView extends StatefulWidget {
  const _ListView({required this.projectId});
  final String projectId;

  @override
  State<_ListView> createState() => _ListViewState();
}

class _ListViewState extends State<_ListView> {
  bool _gantt = false;

  String get projectId => widget.projectId;

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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.view_list_outlined, size: 18),
                  tooltip: t.milestonesViewList,
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.view_timeline_outlined, size: 18),
                  tooltip: t.milestonesViewGantt,
                ),
              ],
              selected: {_gantt},
              onSelectionChanged: (s) => setState(() => _gantt = s.first),
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
            onPressed: () async {
              final body = await showMilestoneEditDialog(context);
              if (body == null || !context.mounted) return;
              await context.read<MilestonesListCubit>().create(body);
            },
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
          if (state.milestones.isEmpty) {
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
                      onPressed: () async {
                        final cubit = context.read<MilestonesListCubit>();
                        final body = await showMilestoneEditDialog(context);
                        if (body == null) return;
                        await cubit.create(body);
                      },
                      label: Text(t.actionNewMilestone),
                    )
                  : null,
            );
          }
          final detail = context.watch<ProjectDetailCubit>().state;
          final canEdit =
              detail is ProjectDetailLoaded &&
              detail.has(Permission.milestoneModify);
          final canDelete =
              detail is ProjectDetailLoaded &&
              detail.has(Permission.milestoneDelete);
          if (_gantt) {
            return _MilestonesGantt(
              milestones: _byEndDate(state.milestones),
              projectId: projectId,
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Nearest deadline first, so what is due next is on top.
                  for (final m in _byEndDate(state.milestones))
                    _Row(
                      milestone: m,
                      projectId: projectId,
                      canEdit: canEdit,
                      canDelete: canDelete,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.milestone,
    required this.projectId,
    required this.canEdit,
    required this.canDelete,
  });
  final Milestone milestone;
  final String projectId;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = [
      if (milestone.startDate != null) _isoDate(milestone.startDate!),
      if (milestone.endDate != null) _isoDate(milestone.endDate!),
    ].join(' → ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          milestone.closed ? Icons.check_circle : Icons.outlined_flag,
          color: milestone.closed
              ? theme.colorScheme.outline
              : theme.colorScheme.primary,
        ),
        title: Text(milestone.name),
        subtitle: Text(
          [
            if (dates.isNotEmpty) dates,
            if (milestone.closed)
              t.milestoneStatusClosed
            else
              t.milestoneStatusOpen,
          ].join(' · '),
        ),
        onTap: () =>
            context.go(Routes.milestoneDetailFor(projectId, milestone.id)),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final body = await showMilestoneEditDialog(
                    context,
                    existing: milestone,
                  );
                  if (body == null || !context.mounted) return;
                  await context.read<MilestonesListCubit>().update(
                    milestone.id,
                    UpdateMilestoneRequest(
                      name: body.name,
                      startDate: body.startDate,
                      endDate: body.endDate,
                    ),
                  );
                },
              ),
            if (canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t.milestoneDeleteTitle),
                      content: Text(
                        t.milestoneDeleteConfirm(milestone.name),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(t.actionCancel),
                        ),
                        FilledButton.tonal(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(t.actionDelete),
                        ),
                      ],
                    ),
                  );
                  if ((ok ?? false) && context.mounted) {
                    await context.read<MilestonesListCubit>().delete(
                      milestone.id,
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Gantt view
// ---------------------------------------------------------------------------

const double _kGanttLabelWidth = 200;
const double _kGanttRowHeight = 44;
const double _kGanttHeaderHeight = 34;
const double _kMinPxPerDay = 4;

/// Timeline of milestones as horizontal bars over a shared month axis.
/// Missing dates use the display defaults (start = today, end = +7 days) and
/// render semi-transparent to signal an estimate; a vertical line marks
/// today; clicking a bar/name opens the milestone.
class _MilestonesGantt extends StatelessWidget {
  const _MilestonesGantt({required this.milestones, required this.projectId});

  final List<Milestone> milestones;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (milestones.isEmpty) return const SizedBox.shrink();

    final ranges = {for (final m in milestones) m.id: _effectiveRange(m)};
    var min = ranges.values.first.start;
    var max = ranges.values.first.end;
    for (final r in ranges.values) {
      if (r.start.isBefore(min)) min = r.start;
      if (r.end.isAfter(max)) max = r.end;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(min)) min = today;
    if (today.isAfter(max)) max = today;
    // Pad the window so bars never touch the edges.
    min = min.subtract(const Duration(days: 3));
    max = max.add(const Duration(days: 7));
    final totalDays = max.difference(min).inDays.clamp(1, 3650);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            constraints.maxWidth - _kGanttLabelWidth - 32 /* padding */;
        final pxPerDay = (available / totalDays).clamp(
          _kMinPxPerDay,
          double.infinity,
        );
        final chartWidth = totalDays * pxPerDay;
        double x(DateTime d) => d.difference(min).inDays * pxPerDay;

        // Month tick marks across the window.
        final months = <DateTime>[];
        var tick = DateTime(min.year, min.month);
        while (!tick.isAfter(max)) {
          if (!tick.isBefore(min)) months.add(tick);
          tick = DateTime(tick.year, tick.month + 1);
        }
        final monthFmt = DateFormat.yMMM(
          Localizations.localeOf(context).toLanguageTag(),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fixed name column.
              SizedBox(
                width: _kGanttLabelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: _kGanttHeaderHeight),
                    for (final m in milestones)
                      SizedBox(
                        height: _kGanttRowHeight,
                        child: InkWell(
                          onTap: () => context.go(
                            Routes.milestoneDetailFor(projectId, m.id),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  m.closed
                                      ? Icons.check_circle
                                      : Icons.outlined_flag,
                                  size: 16,
                                  color: m.closed
                                      ? theme.colorScheme.outline
                                      : theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    m.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Scrollable timeline.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth,
                    height:
                        _kGanttHeaderHeight +
                        milestones.length * _kGanttRowHeight,
                    child: Stack(
                      children: [
                        // Month gridlines + labels.
                        for (final month in months)
                          Positioned(
                            left: x(month),
                            top: 0,
                            bottom: 0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  monthFmt.format(month),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    width: 1,
                                    color: theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Today marker.
                        Positioned(
                          left: x(today),
                          top: _kGanttHeaderHeight - 6,
                          bottom: 0,
                          child: Tooltip(
                            message: _isoDate(today),
                            child: Container(
                              width: 2,
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ),
                        // Bars.
                        for (var i = 0; i < milestones.length; i++)
                          _ganttBar(
                            context,
                            milestones[i],
                            ranges[milestones[i].id]!,
                            top:
                                _kGanttHeaderHeight +
                                i * _kGanttRowHeight +
                                (_kGanttRowHeight - 20) / 2,
                            x: x,
                            pxPerDay: pxPerDay,
                            estimatedLabel: t.milestonesDatesEstimated,
                          ),
                      ],
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

  Widget _ganttBar(
    BuildContext context,
    Milestone m,
    ({DateTime start, DateTime end, bool estimated}) range, {
    required double top,
    required double Function(DateTime) x,
    required double pxPerDay,
    required String estimatedLabel,
  }) {
    final theme = Theme.of(context);
    final left = x(range.start);
    final width = ((range.end.difference(range.start).inDays + 1) * pxPerDay)
        .clamp(6.0, double.infinity);
    final color = m.closed
        ? theme.colorScheme.outline
        : theme.colorScheme.primary;
    final label =
        '${_isoDate(range.start)} → ${_isoDate(range.end)}'
        '${range.estimated ? ' · $estimatedLabel' : ''}';
    return Positioned(
      left: left,
      top: top,
      child: Tooltip(
        message: '${m.name}\n$label',
        child: InkWell(
          onTap: () => context.go(Routes.milestoneDetailFor(projectId, m.id)),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: width,
            height: 20,
            decoration: BoxDecoration(
              color: color.withValues(alpha: range.estimated ? 0.35 : 0.85),
              borderRadius: BorderRadius.circular(6),
              border: range.estimated
                  ? Border.all(color: color, width: 1)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
