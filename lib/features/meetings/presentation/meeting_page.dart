import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meeting_detail_cubit.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meeting_uploads_cubit.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_format.dart';
import 'package:intellipilot/features/meetings/presentation/meetings_page.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/meeting_edit_dialog.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/meeting_files_tabs.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/meeting_links_tab.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/meeting_text_tabs.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// One meeting: its details, minutes, recordings, files and links.
class MeetingPage extends StatelessWidget {
  const MeetingPage({
    required this.projectId,
    required this.meetingId,
    super.key,
  });

  final String projectId;
  final String meetingId;

  @override
  Widget build(BuildContext context) {
    return MeetingViewerGate(
      projectId: projectId,
      builder: (context, viewer) {
        final events = getIt.isRegistered<ProjectEventsService>()
            ? getIt<ProjectEventsService>()
            : null;
        return MultiBlocProvider(
          providers: [
            BlocProvider<MeetingDetailCubit>(
              create: (_) {
                final c = MeetingDetailCubit(
                  repo: getIt<MeetingsRepository>(),
                  projectId: projectId,
                  meetingId: meetingId,
                  events: events,
                );
                unawaited(c.load());
                return c;
              },
            ),
            BlocProvider<MeetingUploadsCubit>(
              create: (context) => MeetingUploadsCubit(
                repo: getIt<MeetingsRepository>(),
                projectId: projectId,
                meetingId: meetingId,
                onUploaded: () =>
                    context.read<MeetingDetailCubit>().artifactAdded(),
              ),
            ),
          ],
          child: MeetingView(projectId: projectId, viewer: viewer),
        );
      },
    );
  }
}

class MeetingView extends StatelessWidget {
  const MeetingView({required this.projectId, required this.viewer, super.key});

  final String projectId;
  final MeetingViewer viewer;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<MeetingDetailCubit, MeetingDetailState>(
      builder: (context, state) => switch (state) {
        MeetingDetailLoading() => const Center(
          child: CircularProgressIndicator(),
        ),
        MeetingDetailFailed(:final failure) => EmptyState(
          icon: Icons.error_outline,
          title: meetingFailureMessage(t, failure),
          action: FilledButton(
            onPressed: () =>
                unawaited(context.read<MeetingDetailCubit>().load()),
            child: Text(t.actionRetry),
          ),
        ),
        MeetingDetailDeleted() => EmptyState(
          icon: Icons.event_busy_outlined,
          title: t.meetingDeleted,
          action: FilledButton(
            onPressed: () => context.go(Routes.projectMeetingsFor(projectId)),
            child: Text(t.meetingBackToCalendar),
          ),
        ),
        MeetingDetailLoaded(:final meeting, :final saving) => _Loaded(
          projectId: projectId,
          viewer: viewer,
          meeting: meeting,
          saving: saving,
        ),
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.projectId,
    required this.viewer,
    required this.meeting,
    required this.saving,
  });

  final String projectId;
  final MeetingViewer viewer;
  final Meeting meeting;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final mayModify = viewer.access.has(Permission.meetingModify);
    // Text editors keep their controls through a save (they show their own
    // progress); the other tabs pause their actions while one is running.
    final canModify = mayModify && !saving;
    final recordings = meeting.artifactsOf(ArtifactKind.recording);
    final files = meeting.artifacts
        .where((a) => ArtifactKind.fromWire(a.kind) != ArtifactKind.recording)
        .toList();
    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(projectId: projectId, viewer: viewer, meeting: meeting),
          if (saving) const LinearProgressIndicator(minHeight: 2),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: t.meetingTabSummary),
              Tab(text: t.meetingTabTranscript),
              Tab(text: '${t.meetingTabRecordings} (${recordings.length})'),
              Tab(text: '${t.meetingTabFiles} (${files.length})'),
              Tab(text: t.meetingTabLinks),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                SummaryTab(meeting: meeting, canModify: mayModify),
                TranscriptTab(meeting: meeting, canModify: mayModify),
                RecordingsTab(
                  projectId: projectId,
                  recordings: recordings,
                  canModify: canModify,
                ),
                FilesTab(
                  projectId: projectId,
                  files: files,
                  canModify: canModify,
                ),
                MeetingLinksTab(
                  projectId: projectId,
                  meeting: meeting,
                  canModify: canModify,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.projectId,
    required this.viewer,
    required this.meeting,
  });

  final String projectId;
  final MeetingViewer viewer;
  final Meeting meeting;

  Future<void> _edit(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<MeetingDetailCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final value = await showMeetingEditDialog(
      context,
      initialDate: meeting.date,
      defaultTimezone: viewer.timezone,
      initial: meeting,
    );
    if (value == null) return;
    final failure = await cubit.update(value.toUpdate());
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(meetingFailureMessage(t, failure))),
      );
    }
  }

  Future<void> _delete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<MeetingDetailCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.meetingDeleteTitle),
        content: Text(t.meetingDeleteConfirm(meeting.title)),
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
    if (!(ok ?? false)) return;
    final failure = await cubit.deleteMeeting();
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(meetingFailureMessage(t, failure))),
      );
      return;
    }
    router.go(Routes.projectMeetingsFor(projectId));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final location = meeting.location.trim();
    final isLink =
        location.startsWith('https://') || location.startsWith('http://');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: t.meetingBackToCalendar,
                onPressed: () =>
                    context.go(Routes.projectMeetingsFor(projectId)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meeting.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${meetingDayLabel(context, meeting.date)} · '
                        '${meetingTimeLabel(t, start: meeting.startTime, end: meeting.endTime, timezone: meeting.timezone, viewerTimezone: viewer.timezone)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isLink ? Icons.link : Icons.place_outlined,
                              size: 16,
                              color: muted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: isLink
                                  ? InkWell(
                                      onTap: () => openExternalUrl(location),
                                      child: Text(
                                        location,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      location,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: muted),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (viewer.access.has(Permission.meetingModify))
                IconButton(
                  key: const Key('meeting-edit'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: t.meetingEditTitle,
                  onPressed: () => unawaited(_edit(context)),
                ),
              if (viewer.access.has(Permission.meetingDelete))
                IconButton(
                  key: const Key('meeting-delete'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: t.meetingDeleteTitle,
                  onPressed: () => unawaited(_delete(context)),
                ),
            ],
          ),
          if (meeting.description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 8, 0, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: MarkdownText(meeting.description),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
