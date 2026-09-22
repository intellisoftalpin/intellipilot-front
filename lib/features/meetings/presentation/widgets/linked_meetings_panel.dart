import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/domain/meetings_repository.dart';
import 'package:intellipilot/features/meetings/presentation/widgets/meeting_tile.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The meetings an issue or epic was linked to, newest first. Shown on the
/// issue / epic detail page to users who may view meetings.
class LinkedMeetingsPanel extends StatefulWidget {
  const LinkedMeetingsPanel({
    required this.projectId,
    required this.entityId,
    required this.isEpic,
    this.onNavigate,
    super.key,
  });

  final String projectId;
  final String entityId;
  final bool isEpic;

  /// Called before navigating away — the detail sheet closes itself with it.
  final VoidCallback? onNavigate;

  @override
  State<LinkedMeetingsPanel> createState() => _LinkedMeetingsPanelState();
}

class _LinkedMeetingsPanelState extends State<LinkedMeetingsPanel> {
  late Future<List<MeetingListItem>?> _meetings = _load();

  Future<List<MeetingListItem>?> _load() async {
    try {
      final repo = getIt<MeetingsRepository>();
      final res = widget.isEpic
          ? await repo.forEpic(widget.projectId, widget.entityId)
          : await repo.forIssue(widget.projectId, widget.entityId);
      return res.valueOrNull;
    } on Object {
      // A server without meetings (older than 0.7.2) — show nothing.
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant LinkedMeetingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId) _meetings = _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<List<MeetingListItem>?>(
      future: _meetings,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final list = snap.data ?? const <MeetingListItem>[];
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              t.meetingsPanelEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in list)
              MeetingTile(
                meeting: m,
                showDate: true,
                onTap: () {
                  final router = GoRouter.of(context);
                  widget.onNavigate?.call();
                  router.go(Routes.meetingFor(widget.projectId, m.id));
                },
              ),
          ],
        );
      },
    );
  }
}
