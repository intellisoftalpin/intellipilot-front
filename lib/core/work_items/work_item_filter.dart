import 'dart:convert';

import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';

/// A single, shared filter model for work-item lists (the Issues list and the
/// Board), so both expose an identical set of filter dimensions. Each id field
/// is `null` for "no filter"; the assignee/epic/milestone fields also accept
/// the sentinel `'none'` to match items with that field unset.
class WorkItemFilter {
  const WorkItemFilter({
    this.search = '',
    this.statusId,
    this.typeId,
    this.priorityId,
    this.sizeId,
    this.assigneeId,
    this.epicId,
    this.milestoneId,
    this.labelId,
    this.componentId,
    this.category,
    this.overdueOnly = false,
  });

  factory WorkItemFilter.fromJson(Map<String, dynamic> j) => WorkItemFilter(
    search: j['search'] as String? ?? '',
    statusId: j['status'] as String?,
    typeId: j['type'] as String?,
    priorityId: j['priority'] as String?,
    sizeId: j['size'] as String?,
    assigneeId: j['assignee'] as String?,
    epicId: j['epic'] as String?,
    milestoneId: j['milestone'] as String?,
    labelId: j['label'] as String?,
    componentId: j['component'] as String?,
    category: j['category'] as String?,
    overdueOnly: j['overdue'] as bool? ?? false,
  );

  /// Decode from a JSON string stored in [KeyValueStorage]; empty/invalid → a
  /// blank filter.
  factory WorkItemFilter.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const WorkItemFilter();
    try {
      return WorkItemFilter.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const WorkItemFilter();
    }
  }

  final String search;
  final String? statusId;
  final String? typeId;
  final String? priorityId;
  final String? sizeId;
  final String? assigneeId;
  final String? epicId;
  final String? milestoneId;
  final String? labelId;
  final String? componentId;
  final String? category;
  final bool overdueOnly;

  static const _keep = Object();

  WorkItemFilter copyWith({
    String? search,
    Object? statusId = _keep,
    Object? typeId = _keep,
    Object? priorityId = _keep,
    Object? sizeId = _keep,
    Object? assigneeId = _keep,
    Object? epicId = _keep,
    Object? milestoneId = _keep,
    Object? labelId = _keep,
    Object? componentId = _keep,
    Object? category = _keep,
    bool? overdueOnly,
  }) => WorkItemFilter(
    search: search ?? this.search,
    statusId: statusId == _keep ? this.statusId : statusId as String?,
    typeId: typeId == _keep ? this.typeId : typeId as String?,
    priorityId: priorityId == _keep ? this.priorityId : priorityId as String?,
    sizeId: sizeId == _keep ? this.sizeId : sizeId as String?,
    assigneeId: assigneeId == _keep ? this.assigneeId : assigneeId as String?,
    epicId: epicId == _keep ? this.epicId : epicId as String?,
    milestoneId: milestoneId == _keep
        ? this.milestoneId
        : milestoneId as String?,
    labelId: labelId == _keep ? this.labelId : labelId as String?,
    componentId: componentId == _keep
        ? this.componentId
        : componentId as String?,
    category: category == _keep ? this.category : category as String?,
    overdueOnly: overdueOnly ?? this.overdueOnly,
  );

  Map<String, dynamic> toJson() => {
    if (search.isNotEmpty) 'search': search,
    if (statusId != null) 'status': statusId,
    if (typeId != null) 'type': typeId,
    if (priorityId != null) 'priority': priorityId,
    if (sizeId != null) 'size': sizeId,
    if (assigneeId != null) 'assignee': assigneeId,
    if (epicId != null) 'epic': epicId,
    if (milestoneId != null) 'milestone': milestoneId,
    if (labelId != null) 'label': labelId,
    if (componentId != null) 'component': componentId,
    if (category != null) 'category': category,
    if (overdueOnly) 'overdue': true,
  };

  String encode() => jsonEncode(toJson());

  /// True when any dimension is constraining the result set.
  bool get isActive =>
      search.trim().isNotEmpty ||
      statusId != null ||
      typeId != null ||
      priorityId != null ||
      sizeId != null ||
      assigneeId != null ||
      epicId != null ||
      milestoneId != null ||
      labelId != null ||
      componentId != null ||
      category != null ||
      overdueOnly;

  /// Whether [issue] passes this filter. [closedStatusIds] flags closed
  /// statuses (for the overdue test, which only counts open, past-due items).
  bool matches(
    Issue issue, {
    required Set<String> closedStatusIds,
    DateTime? today,
  }) {
    if (statusId != null && issue.statusId != statusId) return false;
    if (typeId != null && issue.typeId != typeId) return false;
    if (priorityId != null && issue.priorityId != priorityId) return false;
    if (sizeId != null && issue.sizeId != sizeId) return false;
    if (!_idMatches(assigneeId, issue.assignedTo)) return false;
    if (!_idMatches(epicId, issue.epicId)) return false;
    if (!_idMatches(milestoneId, issue.milestoneId)) return false;
    if (category != null && issue.category != category) return false;
    if (labelId != null && !issue.labels.contains(labelId)) return false;
    if (componentId != null && !issue.components.contains(componentId)) {
      return false;
    }
    if (overdueOnly) {
      final due = issue.dueDate;
      if (due == null) return false;
      final parsed = DateTime.tryParse(due);
      final now = today ?? DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      if (parsed == null || !parsed.isBefore(midnight)) return false;
      if (closedStatusIds.contains(issue.statusId)) return false;
    }
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return true;
    return issue.subject.toLowerCase().contains(q) ||
        issue.description.toLowerCase().contains(q) ||
        'issue-${issue.reference}'.contains(q) ||
        '#${issue.reference}'.contains(q);
  }

  /// `null` filter → match all; `'none'` → field must be unset; otherwise exact.
  bool _idMatches(String? filterValue, String? itemValue) {
    if (filterValue == null) return true;
    if (filterValue == 'none') return itemValue == null;
    return itemValue == filterValue;
  }
}

/// Persists the last-used [WorkItemFilter] per (view, project) in the Hive
/// `ui` box, so a user returns to a list with the same filter they left.
class WorkItemFilterStore {
  WorkItemFilterStore(this._storage);
  final KeyValueStorage _storage;

  static String _key(String view, String projectId) =>
      'wifilter:$view:$projectId';

  WorkItemFilter load(String view, String projectId) =>
      WorkItemFilter.decode(_storage.get<String>(_key(view, projectId)));

  Future<void> save(String view, String projectId, WorkItemFilter f) =>
      _storage.set<String>(_key(view, projectId), f.encode());
}
