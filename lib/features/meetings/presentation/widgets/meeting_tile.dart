import 'package:flutter/material.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// One meeting in a list: time, title, location, and which artefacts it has.
class MeetingTile extends StatelessWidget {
  const MeetingTile({
    required this.meeting,
    required this.onTap,
    this.viewerTimezone,
    this.showDate = false,
    super.key,
  });

  final MeetingListItem meeting;
  final VoidCallback onTap;
  final String? viewerTimezone;

  /// Prefix the time with the date — for lists spanning many days.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final time = meetingTimeLabel(
      t,
      start: meeting.startTime,
      end: meeting.endTime,
      timezone: meeting.timezone,
      viewerTimezone: viewerTimezone,
    );
    final when = showDate
        ? '${MaterialLocalizations.of(context).formatMediumDate(meeting.date)}'
              ' · $time'
        : time;

    final badges = <Widget>[
      if (meeting.hasSummary)
        _Badge(icon: Icons.notes_outlined, label: t.meetingTabSummary),
      if (meeting.hasTranscript)
        _Badge(icon: Icons.subject_outlined, label: t.meetingTabTranscript),
      if (meeting.recordingCount > 0)
        _Badge(
          icon: Icons.videocam_outlined,
          label: t.meetingRecordingsCount(meeting.recordingCount),
        ),
      if (meeting.fileCount > 0)
        _Badge(
          icon: Icons.attach_file,
          label: t.meetingFilesCount(meeting.fileCount),
        ),
    ];

    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.groups_outlined),
      title: Text(
        meeting.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(when, style: TextStyle(color: muted)),
          if (meeting.location.isNotEmpty)
            Text(
              meeting.location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted),
            ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(spacing: 10, runSpacing: 2, children: badges),
          ],
        ],
      ),
      isThreeLine: meeting.location.isNotEmpty || badges.isNotEmpty,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: style),
      ],
    );
  }
}
