import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/issues_cubit.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Fixed business categories (mirror `IssueCategory` on the backend).
const List<String> _categories = [
  'customer_request',
  'compliance',
  'security',
  'roadmap',
  'technical_debt',
  'operational',
  'research_discovery',
  'other',
];

/// Shared create / edit dialog for issues. Loads the related pickers
/// (members, epics, milestones) so every field can be set from the start.
/// The result is a [CreateIssueRequest]; callers pass it straight to
/// `IssuesCubit.create` or map to `UpdateIssueRequest`.
Future<CreateIssueRequest?> showIssueEditDialog(
  BuildContext context, {
  required IssuesLoaded state,
  required String projectId,
  Issue? existing,
}) async {
  final membersRes = await getIt<ProjectsRepository>().listMembers(projectId);
  final epicsRes = await getIt<BacklogRepository>().listEpics(projectId);
  final milestonesRes = await getIt<MilestonesRepository>().list(projectId);
  if (!context.mounted) return null;
  final members = membersRes.valueOrNull ?? const <Membership>[];
  final epics = epicsRes.valueOrNull ?? const <Epic>[];
  final milestones = milestonesRes.valueOrNull ?? const <Milestone>[];

  final t = AppLocalizations.of(context);
  final subjectCtrl = TextEditingController(text: existing?.subject ?? '');
  final descCtrl = TextEditingController(text: existing?.description ?? '');
  var statusId = existing?.statusId;
  var typeId = existing?.typeId;
  var priorityId = existing?.priorityId;
  var sizeId = existing?.sizeId;
  var assignedTo = existing?.assignedTo;
  var epicId = existing?.epicId;
  var milestoneId = existing?.milestoneId;
  var category = existing?.category;
  var startDate = _parseDate(existing?.startDate);
  var dueDate = _parseDate(existing?.dueDate);
  final labels = <String>{...?existing?.labels};
  final components = <String>{...?existing?.components};

  return showDialog<CreateIssueRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? t.actionNewIssue : t.actionEditIssue),
        content: SizedBox(
          width: 520,
          height: 620,
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
                _taxonomyDropdown(
                  label: t.issueFieldStatus,
                  items: state.statuses,
                  current: statusId,
                  onChanged: (v) => setState(() => statusId = v),
                ),
                const SizedBox(height: 8),
                _taxonomyDropdown(
                  label: t.issueFieldType,
                  items: state.types,
                  current: typeId,
                  onChanged: (v) => setState(() => typeId = v),
                ),
                const SizedBox(height: 8),
                _taxonomyDropdown(
                  label: t.issueFieldPriority,
                  items: state.priorities,
                  current: priorityId,
                  onChanged: (v) => setState(() => priorityId = v),
                ),
                const SizedBox(height: 8),
                _taxonomyDropdown(
                  label: 'Size',
                  items: state.sizes,
                  current: sizeId,
                  onChanged: (v) => setState(() => sizeId = v),
                ),
                const SizedBox(height: 8),
                _optionsDropdown(
                  label: t.issueFieldAssignee,
                  current: assignedTo,
                  options: [
                    for (final m in members) (m.userId, m.displayName),
                  ],
                  onChanged: (v) => setState(() => assignedTo = v),
                ),
                const SizedBox(height: 8),
                _optionsDropdown(
                  label: t.detailFieldEpic,
                  current: epicId,
                  options: [
                    for (final e in epics) (e.id, e.subject),
                  ],
                  onChanged: (v) => setState(() => epicId = v),
                ),
                const SizedBox(height: 8),
                _optionsDropdown(
                  label: t.detailFieldMilestone,
                  current: milestoneId,
                  options: [
                    for (final m in milestones) (m.id, m.name),
                  ],
                  onChanged: (v) => setState(() => milestoneId = v),
                ),
                const SizedBox(height: 8),
                _optionsDropdown(
                  label: t.issueFieldCategory,
                  current: category,
                  options: [
                    for (final c in _categories) (c, _humanizeCategory(c)),
                  ],
                  onChanged: (v) => setState(() => category = v),
                ),
                const SizedBox(height: 8),
                _DateField(
                  label: t.ttStartDate,
                  value: startDate,
                  onChanged: (d) => setState(() => startDate = d),
                ),
                _DateField(
                  label: t.issueFieldDueDate,
                  value: dueDate,
                  onChanged: (d) => setState(() => dueDate = d),
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
                  assignedTo: assignedTo,
                  epicId: epicId,
                  milestoneId: milestoneId,
                  category: category,
                  startDate: _fmtDate(startDate),
                  dueDate: _fmtDate(dueDate),
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

Widget _taxonomyDropdown({
  required String label,
  required List<TaxonomyItem> items,
  required String? current,
  required ValueChanged<String?> onChanged,
}) => _optionsDropdown(
  label: label,
  current: current,
  options: [
    for (final item in items)
      (item.id, item.emoji.isEmpty ? item.name : '${item.emoji} ${item.name}'),
  ],
  onChanged: onChanged,
);

/// A nullable single-select dropdown over `(id, label)` options with a "—"
/// (none) entry at the top.
Widget _optionsDropdown({
  required String label,
  required String? current,
  required List<(String, String)> options,
  required ValueChanged<String?> onChanged,
}) {
  // Guard against a stale current value not present in options.
  final has = current == null || options.any((o) => o.$1 == current);
  return DropdownButtonFormField<String?>(
    initialValue: has ? current : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('—')),
      for (final (id, text) in options)
        DropdownMenuItem<String?>(
          value: id,
          child: Text(text, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text('$label: ${value == null ? '—' : _fmtDate(value)}'),
          ),
          TextButton(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 5),
              );
              if (picked != null) onChanged(picked);
            },
            child: Text(MaterialLocalizations.of(context).dateInputLabel),
          ),
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }
}

DateTime? _parseDate(String? iso) =>
    (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso);

String? _fmtDate(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

String _humanizeCategory(String raw) {
  if (raw.isEmpty) return raw;
  final spaced = raw.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}
