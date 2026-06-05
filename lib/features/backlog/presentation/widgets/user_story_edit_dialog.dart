import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Lightweight create/edit dialog for a backlog issue (Story/Task/Bug grouped
/// under epics). Returns a [CreateIssueRequest] on save; callers map it to
/// create or update via `BacklogCubit`.
Future<CreateIssueRequest?> showBacklogIssueDialog(
  BuildContext context, {
  required List<Epic> epics,
  required List<TaxonomyItem> statuses,
  required List<TaxonomyItem> types,
  required List<TaxonomyItem> points,
  Issue? existing,
}) async {
  final t = AppLocalizations.of(context);
  final subjectCtrl =
      TextEditingController(text: existing?.subject ?? '');
  final descCtrl =
      TextEditingController(text: existing?.description ?? '');
  var statusId = existing?.statusId;
  var typeId = existing?.typeId;
  var epicId = existing?.epicId;
  var pointsId = existing?.pointsId;

  return showDialog<CreateIssueRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          existing == null ? t.actionNewIssue : t.actionEditIssue,
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: subjectCtrl,
                  autofocus: true,
                  decoration:
                      InputDecoration(labelText: t.backlogFieldSubject),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: t.backlogFieldDescription,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: typeId,
                  decoration:
                      InputDecoration(labelText: t.detailFieldIssueType),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(t.statusValueNone),
                    ),
                    ...types.map(
                      (e) => DropdownMenuItem<String?>(
                        value: e.id,
                        child: Text(e.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => typeId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: epicId,
                  decoration: InputDecoration(labelText: t.backlogFieldEpic),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(t.backlogNoEpic),
                    ),
                    ...epics.map(
                      (e) => DropdownMenuItem<String?>(
                        value: e.id,
                        child: Text('EPIC-${e.reference} · ${e.subject}'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => epicId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: statusId,
                  decoration: InputDecoration(labelText: t.backlogFieldStatus),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(t.backlogNoStatus),
                    ),
                    ...statuses.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(s.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => statusId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: pointsId,
                  decoration: InputDecoration(labelText: t.backlogFieldPoints),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(t.backlogNoPoints),
                    ),
                    ...points.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(
                          p.value == null ? p.name : '${p.name} (${p.value})',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => pointsId = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () {
              final subject = subjectCtrl.text.trim();
              if (subject.isEmpty) return;
              Navigator.of(ctx).pop(
                CreateIssueRequest(
                  subject: subject,
                  description: descCtrl.text.trim(),
                  statusId: statusId,
                  typeId: typeId,
                  epicId: epicId,
                  pointsId: pointsId,
                ),
              );
            },
            child: Text(t.actionSave),
          ),
        ],
      ),
    ),
  );
}
