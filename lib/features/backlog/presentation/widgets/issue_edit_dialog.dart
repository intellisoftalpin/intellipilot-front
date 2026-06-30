import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/issues_cubit.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Minimal issue creation dialog — asks only for a subject and an issue type.
/// Everything else (status, priority, assignee, dates, labels…) is filled in
/// on the issue sidebar, which the caller opens right after creating. The
/// backend auto-assigns the default "new" status. Mirrors the epic create
/// flow ([showEpicEditDialog]).
Future<CreateIssueRequest?> showIssueEditDialog(
  BuildContext context, {
  required IssuesLoaded state,
  required String projectId,
}) async {
  final t = AppLocalizations.of(context);
  final subjectCtrl = TextEditingController();
  String? typeId;

  return showDialog<CreateIssueRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(t.actionNewIssue),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: subjectCtrl,
                autofocus: true,
                decoration: InputDecoration(labelText: t.backlogFieldSubject),
              ),
              const SizedBox(height: 12),
              _taxonomyDropdown(
                label: t.issueFieldType,
                items: state.types,
                current: typeId,
                onChanged: (v) => setState(() => typeId = v),
              ),
            ],
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
                CreateIssueRequest(subject: subject, typeId: typeId),
              );
            },
            child: Text(t.actionSave),
          ),
        ],
      ),
    ),
  );
}

Widget _taxonomyDropdown({
  required String label,
  required List<TaxonomyItem> items,
  required String? current,
  required ValueChanged<String?> onChanged,
}) {
  // Guard against a stale current value not present in options.
  final has = current == null || items.any((o) => o.id == current);
  return DropdownButtonFormField<String?>(
    initialValue: has ? current : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('—')),
      for (final item in items)
        DropdownMenuItem<String?>(
          value: item.id,
          child: Text(
            item.emoji.isEmpty ? item.name : '${item.emoji} ${item.name}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: onChanged,
  );
}
