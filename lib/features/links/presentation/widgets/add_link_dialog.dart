import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/links/data/dtos/link_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Pick a link type + a target backlog entity. Returns a tuple of
/// `(LinkType, EntityKind, entityId)` on save, or null on cancel.
class AddLinkResult {
  const AddLinkResult({
    required this.type,
    required this.targetKind,
    required this.targetId,
  });
  final LinkType type;
  final EntityKind targetKind;
  final String targetId;
}

Future<AddLinkResult?> showAddLinkDialog(
  BuildContext context, {
  required String projectId,
  required EntityKind sourceKind,
  required String sourceId,
  String keyPrefix = '',
}) async {
  final t = AppLocalizations.of(context);
  final candidates = await _loadCandidates(projectId, keyPrefix);
  if (!context.mounted) return null;
  return showDialog<AddLinkResult>(
    context: context,
    builder: (ctx) => _Dialog(
      title: t.addLinkDialogTitle(_kindLabel(t, sourceKind)),
      sourceKind: sourceKind,
      sourceId: sourceId,
      candidates: candidates,
    ),
  );
}

String _kindLabel(AppLocalizations t, EntityKind k) => switch (k) {
  EntityKind.epic => t.kindLabelEpic,
  EntityKind.issue => t.kindLabelIssue,
};

class _Candidate {
  const _Candidate({
    required this.kind,
    required this.id,
    required this.key,
    required this.subject,
  });
  final EntityKind kind;
  final String id;
  final String key;
  final String subject;
}

Future<List<_Candidate>?> _loadCandidates(
  String projectId,
  String keyPrefix,
) async {
  final backlog = getIt<BacklogRepository>();
  final epics = await backlog.listEpics(projectId);
  final issues = await backlog.listIssues(projectId);
  if (epics.isErr || issues.isErr) return null;
  final out = <_Candidate>[];
  for (final e in epics.valueOrNull ?? const <Epic>[]) {
    out.add(
      _Candidate(
        kind: EntityKind.epic,
        id: e.id,
        key: epicKeyLabel(keyPrefix, e.reference),
        subject: e.subject,
      ),
    );
  }
  for (final i in issues.valueOrNull ?? const <Issue>[]) {
    out.add(
      _Candidate(
        kind: EntityKind.issue,
        id: i.id,
        key: issueKeyLabel(keyPrefix, i.reference),
        subject: i.subject,
      ),
    );
  }
  return out;
}

class _Dialog extends StatefulWidget {
  const _Dialog({
    required this.title,
    required this.sourceKind,
    required this.sourceId,
    required this.candidates,
  });

  final String title;
  final EntityKind sourceKind;
  final String sourceId;
  final List<_Candidate>? candidates;

  @override
  State<_Dialog> createState() => _DialogState();
}

class _DialogState extends State<_Dialog> {
  LinkType _type = LinkType.blocks;
  _Candidate? _selected;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 520,
        child: widget.candidates == null
            ? Center(child: Text(t.linkPickerLoadFailed))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<LinkType>(
                    initialValue: _type,
                    decoration: InputDecoration(labelText: t.linkFieldType),
                    items: LinkType.values
                        .map(
                          (tp) => DropdownMenuItem(
                            value: tp,
                            child: Text(_typeLabel(t, tp)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _type = v ?? LinkType.blocks),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: t.linkFieldTarget,
                      hintText: t.linkSearchHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _CandidatesList(
                      candidates: _filtered(widget.candidates!),
                      selected: _selected,
                      onSelected: (c) => setState(() => _selected = c),
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
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(
                  AddLinkResult(
                    type: _type,
                    targetKind: _selected!.kind,
                    targetId: _selected!.id,
                  ),
                ),
          child: Text(t.actionSave),
        ),
      ],
    );
  }

  List<_Candidate> _filtered(List<_Candidate> all) {
    final q = _query.trim().toLowerCase();
    final out = all.where(
      // Hide the source item — can't link to self — and apply the search.
      (c) {
        if (c.kind == widget.sourceKind && c.id == widget.sourceId) {
          return false;
        }
        if (q.isEmpty) return true;
        return c.key.toLowerCase().contains(q) ||
            c.subject.toLowerCase().contains(q);
      },
    );
    return out.toList();
  }
}

class _CandidatesList extends StatelessWidget {
  const _CandidatesList({
    required this.candidates,
    required this.selected,
    required this.onSelected,
  });
  final List<_Candidate> candidates;
  final _Candidate? selected;
  final ValueChanged<_Candidate> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (candidates.isEmpty) {
      return Center(
        child: Text(
          '—',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: candidates.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = candidates[i];
        final isSelected = selected?.kind == c.kind && selected?.id == c.id;
        return ListTile(
          dense: true,
          selected: isSelected,
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              c.key,
              style: AppTheme.mono(context, size: 11).copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          title: Text(c.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onSelected(c),
        );
      },
    );
  }
}

String _typeLabel(AppLocalizations t, LinkType type) => switch (type) {
  LinkType.blocks => t.linkTypeBlocks,
  LinkType.relates => t.linkTypeRelates,
  LinkType.duplicates => t.linkTypeDuplicates,
  LinkType.clones => t.linkTypeClones,
  LinkType.causes => t.linkTypeCauses,
};
