import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';
import 'package:intellipilot/features/meetings/domain/project_access_cache.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meetings_calendar_cubit.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_format.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/meeting_edit_dialog.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/meeting_tile.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/month_calendar.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// What the meetings screens need to know about the viewer.
class MeetingViewer {
  const MeetingViewer({required this.access, required this.timezone});
  final ProjectAccess access;

  /// The viewer's own time zone (profile setting) — the default for new
  /// meetings, and the zone whose meetings need no zone suffix.
  final String timezone;

  static Future<MeetingViewer> load(String projectId) async {
    // Both in flight at once; awaited separately to keep their types.
    final accessFuture = getIt<ProjectAccessCache>().access(projectId);
    final profileFuture = getIt<ProfileRepository>().getProfile();
    final access = await accessFuture;
    final profile = (await profileFuture).valueOrNull;
    return MeetingViewer(access: access, timezone: profile?.timezone ?? 'UTC');
  }
}

/// Resolves the viewer, then builds [builder] — or a "no access" notice for
/// someone without `meeting.view`.
class MeetingViewerGate extends StatefulWidget {
  const MeetingViewerGate({
    required this.projectId,
    required this.builder,
    super.key,
  });

  final String projectId;
  final Widget Function(BuildContext context, MeetingViewer viewer) builder;

  @override
  State<MeetingViewerGate> createState() => _MeetingViewerGateState();
}

class _MeetingViewerGateState extends State<MeetingViewerGate> {
  late Future<MeetingViewer> _viewer = MeetingViewer.load(widget.projectId);

  @override
  void didUpdateWidget(covariant MeetingViewerGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _viewer = MeetingViewer.load(widget.projectId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MeetingViewer>(
      future: _viewer,
      builder: (context, snap) {
        final viewer = snap.data;
        if (viewer == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!viewer.access.has(Permission.meetingView)) {
          final t = AppLocalizations.of(context);
          return EmptyState(
            icon: Icons.lock_outline,
            title: t.meetingsNoAccess,
          );
        }
        return widget.builder(context, viewer);
      },
    );
  }
}

/// The meetings dashboard: a month calendar and the selected day's meetings.
class MeetingsPage extends StatelessWidget {
  const MeetingsPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return MeetingViewerGate(
      projectId: projectId,
      builder: (context, viewer) => BlocProvider<MeetingsCalendarCubit>(
        create: (_) {
          final c = MeetingsCalendarCubit(
            repo: getIt<MeetingsRepository>(),
            projectId: projectId,
            events: getIt.isRegistered<ProjectEventsService>()
                ? getIt<ProjectEventsService>()
                : null,
          );
          unawaited(c.load());
          return c;
        },
        child: MeetingsView(projectId: projectId, viewer: viewer),
      ),
    );
  }
}

class MeetingsView extends StatelessWidget {
  const MeetingsView({
    required this.projectId,
    required this.viewer,
    super.key,
  });

  final String projectId;
  final MeetingViewer viewer;

  Future<void> _create(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<MeetingsCalendarCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final value = await showMeetingEditDialog(
      context,
      initialDate: cubit.state.selectedDay,
      defaultTimezone: viewer.timezone,
    );
    if (value == null) return;
    final res = await getIt<MeetingsRepository>().create(
      projectId,
      value.toCreate(),
    );
    res.when(
      ok: (m) => router.go(Routes.meetingFor(projectId, m.id)),
      err: (f) => messenger.showSnackBar(
        SnackBar(content: Text(meetingFailureMessage(t, f))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canCreate = viewer.access.has(Permission.meetingCreate);

    return BlocBuilder<MeetingsCalendarCubit, MeetingsCalendarState>(
      builder: (context, state) {
        final cubit = context.read<MeetingsCalendarCubit>();
        final calendar = MonthCalendar(
          month: state.month,
          selectedDay: state.selectedDay,
          today: DateTime.now(),
          countOn: state.countOn,
          onSelect: (d) => unawaited(cubit.selectDay(d)),
          onPrevious: () => unawaited(cubit.shiftMonth(-1)),
          onNext: () => unawaited(cubit.shiftMonth(1)),
        );
        final dayList = _DayMeetings(
          projectId: projectId,
          state: state,
          viewer: viewer,
          onRetry: () => unawaited(cubit.load()),
        );

        final header = Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                t.meetingsTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => unawaited(cubit.today()),
                    child: Text(t.meetingsToday),
                  ),
                  if (canCreate)
                    FilledButton.icon(
                      key: const Key('meetings-new'),
                      onPressed: () => unawaited(_create(context)),
                      icon: const Icon(Icons.add),
                      label: Text(t.meetingsNew),
                    ),
                ],
              ),
            ],
          ),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final progress = state.loading
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox(height: 2);
            if (wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  progress,
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: calendar,
                            ),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 400, child: dayList),
                      ],
                    ),
                  ),
                ],
              );
            }
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                SliverToBoxAdapter(child: progress),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverToBoxAdapter(child: calendar),
                ),
                const SliverToBoxAdapter(child: Divider(height: 24)),
                SliverToBoxAdapter(child: dayList),
              ],
            );
          },
        );
      },
    );
  }
}

class _DayMeetings extends StatelessWidget {
  const _DayMeetings({
    required this.projectId,
    required this.state,
    required this.viewer,
    required this.onRetry,
  });

  final String projectId;
  final MeetingsCalendarState state;
  final MeetingViewer viewer;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meetings = state.selectedMeetings;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          meetingDayLabel(context, state.selectedDay),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (state.failure != null)
        ListTile(
          leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
          title: Text(t.meetingsLoadFailed),
          trailing: TextButton(onPressed: onRetry, child: Text(t.actionRetry)),
        )
      else if (meetings.isEmpty && !state.loading)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            t.meetingsNoneOnDay,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (final m in meetings)
        MeetingTile(
          meeting: m,
          viewerTimezone: viewer.timezone,
          onTap: () => context.go(Routes.meetingFor(projectId, m.id)),
        ),
      const SizedBox(height: 16),
    ];
    return LayoutBuilder(
      builder: (context, c) => c.maxHeight.isFinite
          ? ListView(children: children)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
    );
  }
}
