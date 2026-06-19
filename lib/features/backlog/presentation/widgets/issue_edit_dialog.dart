import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/issues_cubit.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Shared create / edit dialog for issues. The result is a
/// [CreateIssueRequest]; callers pass it straight to `IssuesCubit.create`
/// or map to `UpdateIssueRequest`.
Future<CreateIssueRequest?> showIssueEditDialog(
  BuildContext context, {
  required IssuesLoaded state,
  Issue? existing,
}) {
  final t = AppLocalizations.of(context);
  final subjectCtrl =
      TextEditingController(text: existing?.subject ?? '');
  final descCtrl =
      TextEditingController(text: existing?.description ?? '');
  var statusId = existing?.statusId;
  var typeId = existing?.typeId;
  var priorityId = existing?.priorityId;
  var sizeId = existing?.sizeId;
  final labels = <String>{...?existing?.labels};
  final components = <String>{...?existing?.components};

  return showDialog<CreateIssueRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          existing == null ? t.actionNewIssue : t.actionEditIssue,
        ),
        content: SizedBox(
          width: 480,
          height: 540,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: subjectCtrl,
                  autofocus: true,
                  decoration: InputDecoration(labelText: t.backlogFieldSubject),
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
                _kindDropdown(
                  label: t.issueFieldStatus,
                  items: state.statuses,
                  current: statusId,
                  onChanged: (v) => setState(() => statusId = v),
                ),
                const SizedBox(height: 8),
                _kindDropdown(
                  label: t.issueFieldType,
                  items: state.types,
                  current: typeId,
                  onChanged: (v) => setState(() => typeId = v),
                ),
                const SizedBox(height: 8),
                _kindDropdown(
                  label: t.issueFieldPriority,
                  items: state.priorities,
                  current: priorityId,
                  onChanged: (v) => setState(() => priorityId = v),
                ),
                const SizedBox(height: 8),
                _kindDropdown(
                  label: 'Size',
                  items: state.sizes,
                  current: sizeId,
                  onChanged: (v) => setState(() => sizeId = v),
                ),
                const SizedBox(height: 12),
                Text(t.issueFieldLabels),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final l in state.labels)
                      FilterChip(
                        label: Text(l.name),
                        selected: labels.contains(l.id),
                        onSelected: (on) => setState(() {
                          if (on) {
                            labels.add(l.id);
                          } else {
                            labels.remove(l.id);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(t.issueFieldComponents),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in state.components)
                      FilterChip(
                        label: Text(c.name),
                        selected: components.contains(c.id),
                        onSelected: (on) => setState(() {
                          if (on) {
                            components.add(c.id);
                          } else {
                            components.remove(c.id);
                          }
                        }),
                      ),
                  ],
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
                  priorityId: priorityId,
                  sizeId: sizeId,
                  labels: labels.toList(),
                  components: components.toList(),
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

Widget _kindDropdown({
  required String label,
  required List<TaxonomyItem> items,
  required String? current,
  required ValueChanged<String?> onChanged,
}) {
  return DropdownButtonFormField<String?>(
    initialValue: current,
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('—')),
      for (final item in items)
        DropdownMenuItem<String?>(
          value: item.id,
          child: Text(item.name),
        ),
    ],
    onChanged: onChanged,
  );
}
