import 'package:flutter/material.dart';
import 'package:intellipilot/core/widgets/members_scope.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Fixed issue categories (mirror `IssueCategory` on the backend).
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

/// A single, shared filter bar so the Issues list and the Board expose an
/// identical set of filter controls. The Board passes `showStatus: false`
/// (its columns already represent statuses); everything else is identical.
class WorkItemFilterBar extends StatelessWidget {
  const WorkItemFilterBar({
    required this.filter,
    required this.onChanged,
    required this.statuses,
    required this.types,
    required this.priorities,
    required this.sizes,
    required this.epics,
    required this.milestones,
    required this.labels,
    required this.components,
    this.showStatus = true,
    this.lockedDimensions = const {},
    this.hiddenDimensions = const {},
    super.key,
  });

  final WorkItemFilter filter;
  final ValueChanged<WorkItemFilter> onChanged;
  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> sizes;
  final List<Epic> epics;
  final List<Milestone> milestones;
  final List<Label> labels;
  final List<Component> components;
  final bool showStatus;

  /// Dimension keys rendered as disabled chips showing their current value
  /// (the board's locked filters). Keys: 'status','type','priority','size',
  /// 'assignee','epic','milestone','label','component','category','overdue'.
  final Set<String> lockedDimensions;

  /// Dimension keys not rendered at all (e.g. the active swimlane dimension).
  final Set<String> hiddenDimensions;

  bool _hidden(String dim) => hiddenDimensions.contains(dim);
  bool _locked(String dim) => lockedDimensions.contains(dim);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final members = MembersScope.of(context);
    final memberOptions = <_Opt>[
      _Opt('none', t.dashKpiUnassigned),
      for (final e in members.entries) _Opt(e.key, e.value.displayName),
    ];

    // Row 1: the high-frequency filters. Assignee leads, then status (board
    // hides it), type, priority, size, label, component, the overdue toggle
    // and the clear button.
    final row1 = <Widget>[
      if (!_hidden('assignee'))
        _Dropdown(
          hint: t.issueFieldAssignee,
          value: filter.assigneeId,
          options: memberOptions,
          enabled: !_locked('assignee'),
          onChanged: (v) => onChanged(filter.copyWith(assigneeId: v)),
        ),
      if (showStatus && !_hidden('status'))
        _Dropdown(
          hint: t.issueFieldStatus,
          value: filter.statusId,
          options: _tax(types: statuses),
          enabled: !_locked('status'),
          onChanged: (v) => onChanged(filter.copyWith(statusId: v)),
        ),
      if (!_hidden('type'))
        _Dropdown(
          hint: t.issueFieldType,
          value: filter.typeId,
          options: _tax(types: types),
          enabled: !_locked('type'),
          onChanged: (v) => onChanged(filter.copyWith(typeId: v)),
        ),
      if (!_hidden('priority'))
        _Dropdown(
          hint: t.issueFieldPriority,
          value: filter.priorityId,
          options: _tax(types: priorities),
          enabled: !_locked('priority'),
          onChanged: (v) => onChanged(filter.copyWith(priorityId: v)),
        ),
      if (!_hidden('size'))
        _Dropdown(
          hint: t.detailFieldPoints,
          value: filter.sizeId,
          options: _tax(types: sizes),
          enabled: !_locked('size'),
          onChanged: (v) => onChanged(filter.copyWith(sizeId: v)),
        ),
      if (!_hidden('label'))
        _Dropdown(
          hint: t.issueFieldLabels,
          value: filter.labelId,
          options: [for (final l in labels) _Opt(l.id, l.name)],
          enabled: !_locked('label'),
          onChanged: (v) => onChanged(filter.copyWith(labelId: v)),
        ),
      if (!_hidden('component'))
        _Dropdown(
          hint: t.issueFieldComponents,
          value: filter.componentId,
          options: [for (final c in components) _Opt(c.id, c.name)],
          enabled: !_locked('component'),
          onChanged: (v) => onChanged(filter.copyWith(componentId: v)),
        ),
      if (!_hidden('overdue'))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: FilterChip(
            avatar: const Icon(Icons.error_outline, size: 16),
            label: Text(t.dashKpiOverdue),
            selected: filter.overdueOnly,
            onSelected: _locked('overdue')
                ? null
                : (v) => onChanged(filter.copyWith(overdueOnly: v)),
          ),
        ),
      if (filter.isActive)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: TextButton.icon(
            icon: const Icon(Icons.clear_all, size: 18),
            label: Text(t.actionClearFilters),
            onPressed: () => onChanged(const WorkItemFilter()),
          ),
        ),
    ];

    // Row 2: the longer-tail planning dimensions.
    final row2 = <Widget>[
      if (!_hidden('epic'))
        _Dropdown(
          hint: t.detailFieldEpic,
          value: filter.epicId,
          options: [
            _Opt('none', t.backlogNoEpic),
            for (final e in epics)
              _Opt(e.id, 'EPIC-${e.reference} ${e.subject}'),
          ],
          enabled: !_locked('epic'),
          onChanged: (v) => onChanged(filter.copyWith(epicId: v)),
        ),
      if (!_hidden('milestone'))
        _Dropdown(
          hint: t.detailFieldMilestone,
          value: filter.milestoneId,
          options: [
            _Opt('none', t.backlogNoMilestone),
            for (final m in milestones) _Opt(m.id, m.name),
          ],
          enabled: !_locked('milestone'),
          onChanged: (v) => onChanged(filter.copyWith(milestoneId: v)),
        ),
      if (!_hidden('category'))
        _Dropdown(
          hint: t.issueFieldCategory,
          value: filter.category,
          options: [for (final c in _categories) _Opt(c, _humanize(c))],
          enabled: !_locked('category'),
          onChanged: (v) => onChanged(filter.copyWith(category: v)),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: row1,
          ),
          if (row2.isNotEmpty)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: row2,
            ),
        ],
      ),
    );
  }

  List<_Opt> _tax({required List<TaxonomyItem> types}) => [
    for (final item in types)
      _Opt(
        item.id,
        item.emoji.isEmpty ? item.name : '${item.emoji} ${item.name}',
      ),
  ];
}

class _Opt {
  const _Opt(this.id, this.label);
  final String id;
  final String label;
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final String hint;
  final String? value;
  final List<_Opt> options;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final selected = value == null
        ? null
        : options.where((o) => o.id == value).firstOrNull;
    final active = selected != null;
    final theme = Theme.of(context);

    // Locked dimension: a disabled chip that only displays its value. We keep
    // it visible even when it has no value so the user sees the constraint.
    if (!enabled) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Chip(
          avatar: const Icon(Icons.lock_outline, size: 14),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          label: Text(active ? '$hint: ${selected.label}' : hint),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: PopupMenuButton<String?>(
        onSelected: onChanged,
        itemBuilder: (_) => [
          PopupMenuItem<String?>(value: null, child: Text('— $hint')),
          for (final o in options)
            PopupMenuItem<String?>(value: o.id, child: Text(o.label)),
        ],
        child: Chip(
          backgroundColor: active ? theme.colorScheme.secondaryContainer : null,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(active ? '$hint: ${selected.label}' : hint),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

String _humanize(String raw) {
  if (raw.isEmpty) return raw;
  final spaced = raw.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}
