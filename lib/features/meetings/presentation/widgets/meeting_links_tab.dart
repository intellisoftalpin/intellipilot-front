import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/data/project_lookups_cache.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_sheet.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/presentation/cubits/meeting_detail_cubit.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Something a meeting can link to, as shown in a chip and in the picker.
class LinkCandidate {
  const LinkCandidate({required this.id, required this.label, this.key});
  final String id;
  final String label;

  /// Issue / epic key shown before the label (`PS-12`, `PS-E-3`).
  final String? key;

  String get display => key == null ? label : '$key  $label';
}

/// The candidates of each link kind, from the project's lookup tables.
Map<MeetingLinkKind, List<LinkCandidate>> linkCandidates(ProjectLookups l) {
  final prefix = l.project.issuePrefix;
  int byLabel(LinkCandidate a, LinkCandidate b) =>
      a.label.toLowerCase().compareTo(b.label.toLowerCase());
  return {
    MeetingLinkKind.participants: [
      for (final m in l.membersById.values)
        if (m.id.isNotEmpty) LinkCandidate(id: m.id, label: m.displayName),
    ]..sort(byLabel),
    // Newest first: the work a meeting discusses is usually recent.
    MeetingLinkKind.issues: [
      for (final i
          in l.issuesById.values.toList()
            ..sort((a, b) => b.reference.compareTo(a.reference)))
        LinkCandidate(
          id: i.id,
          label: i.subject,
          key: issueKeyLabel(prefix, i.reference),
        ),
    ],
    MeetingLinkKind.epics: [
      for (final e
          in l.epicsById.values.toList()
            ..sort((a, b) => b.reference.compareTo(a.reference)))
        LinkCandidate(
          id: e.id,
          label: e.subject,
          key: epicKeyLabel(prefix, e.reference),
        ),
    ],
    MeetingLinkKind.customers: [
      for (final c in l.customersById.values)
        LinkCandidate(id: c.id, label: c.name),
    ]..sort(byLabel),
  };
}

/// Participants, issues, epics and customers linked to the meeting.
class MeetingLinksTab extends StatefulWidget {
  const MeetingLinksTab({
    required this.projectId,
    required this.meeting,
    required this.canModify,
    super.key,
  });

  final String projectId;
  final Meeting meeting;
  final bool canModify;

  @override
  State<MeetingLinksTab> createState() => _MeetingLinksTabState();
}

class _MeetingLinksTabState extends State<MeetingLinksTab> {
  late final Future<ProjectLookups?> _lookups =
      getIt.isRegistered<ProjectLookupsCache>()
      ? getIt<ProjectLookupsCache>().get(widget.projectId)
      : Future.value();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FutureBuilder<ProjectLookups?>(
      future: _lookups,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final lookups = snap.data;
        final candidates = lookups == null
            ? const <MeetingLinkKind, List<LinkCandidate>>{}
            : linkCandidates(lookups);
        String title(MeetingLinkKind k) => switch (k) {
          MeetingLinkKind.participants => t.meetingParticipants,
          MeetingLinkKind.issues => t.meetingLinkedIssues,
          MeetingLinkKind.epics => t.meetingLinkedEpics,
          MeetingLinkKind.customers => t.meetingLinkedCustomers,
        };
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            for (final kind in MeetingLinkKind.values)
              _LinkSection(
                projectId: widget.projectId,
                kind: kind,
                title: title(kind),
                linkedIds: widget.meeting.idsOf(kind),
                candidates: candidates[kind] ?? const [],
                canModify: widget.canModify,
              ),
          ],
        );
      },
    );
  }
}

class _LinkSection extends StatelessWidget {
  const _LinkSection({
    required this.projectId,
    required this.kind,
    required this.title,
    required this.linkedIds,
    required this.candidates,
    required this.canModify,
  });

  final String projectId;
  final MeetingLinkKind kind;
  final String title;
  final List<String> linkedIds;
  final List<LinkCandidate> candidates;
  final bool canModify;

  Future<void> _run(
    BuildContext context,
    Future<AppFailure?> Function(MeetingDetailCubit c) action,
  ) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failure = await action(context.read<MeetingDetailCubit>());
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(meetingFailureMessage(t, failure))),
      );
    }
  }

  Future<void> _add(BuildContext context) async {
    final linked = linkedIds.toSet();
    final options = candidates.where((c) => !linked.contains(c.id)).toList();
    final picked = await showDialog<LinkCandidate>(
      context: context,
      builder: (_) => _PickDialog(title: title, options: options),
    );
    if (picked == null || !context.mounted) return;
    await _run(context, (c) => c.link(kind, picked.id));
  }

  void _open(BuildContext context, String id) {
    final entityKind = switch (kind) {
      MeetingLinkKind.issues => EntityKind.issue,
      MeetingLinkKind.epics => EntityKind.epic,
      _ => null,
    };
    if (entityKind == null) return;
    unawaited(
      showEntityDetailSheet(
        context,
        projectId: projectId,
        kind: entityKind,
        entityId: id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final byId = {for (final c in candidates) c.id: c};
    final opens =
        kind == MeetingLinkKind.issues || kind == MeetingLinkKind.epics;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (canModify)
                TextButton.icon(
                  key: Key('meeting-link-add-${kind.wire}'),
                  onPressed: () => unawaited(_add(context)),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(t.actionAdd),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (linkedIds.isEmpty)
            Text(
              t.meetingLinkNone,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in linkedIds)
                  InputChip(
                    label: Text(byId[id]?.display ?? '…'),
                    onPressed: opens ? () => _open(context, id) : null,
                    onDeleted: canModify
                        ? () => unawaited(
                            _run(context, (c) => c.unlink(kind, id)),
                          )
                        : null,
                    deleteButtonTooltipMessage: t.actionRemove,
                  ),
              ],
            ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

class _PickDialog extends StatefulWidget {
  const _PickDialog({required this.title, required this.options});

  final String title;
  final List<LinkCandidate> options;

  @override
  State<_PickDialog> createState() => _PickDialogState();
}

class _PickDialogState extends State<_PickDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.options
        : widget.options
              .where((o) => o.display.toLowerCase().contains(q))
              .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.meetingLinkSearch,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(t.meetingLinkNone))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final o = shown[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            o.display,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(o),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
      ],
    );
  }
}
