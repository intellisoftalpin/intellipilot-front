import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';

/// One column of the board: a status taxonomy item (or null = "no status")
/// plus the cards in that column.
class BoardColumn {
  const BoardColumn({required this.status, required this.issues});

  factory BoardColumn.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    final issues =
        (json['issues'] as List<dynamic>? ?? const [])
            .map((e) => BoardCard.fromJson(e as Map<String, dynamic>))
            .toList();
    return BoardColumn(
      status: rawStatus is Map<String, dynamic>
          ? TaxonomyItem.fromJson(rawStatus)
          : null,
      issues: issues,
    );
  }

  /// `null` for the trailing column that collects issues with no status.
  final TaxonomyItem? status;
  final List<BoardCard> issues;

  /// Column id. Null status uses a stable sentinel so [Map] keys + drag
  /// targets work consistently.
  String get id => status?.id ?? _noStatusId;

  static const _noStatusId = '__no_status__';
}

/// An issue card on the board, with its nested sub-tasks (the backend
/// already inlines sub-tasks under each issue for this view).
class BoardCard {
  const BoardCard({required this.issue, required this.subtasks});

  factory BoardCard.fromJson(Map<String, dynamic> json) {
    final subtasksRaw = json['subtasks'] as List<dynamic>? ?? const [];
    return BoardCard(
      issue: Issue.fromJson(json),
      subtasks: subtasksRaw
          .map((e) => Issue.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final Issue issue;
  final List<Issue> subtasks;

  int get totalSubtasks => subtasks.length;
  int get closedSubtasks => subtasks.where((t) => t.statusId != null).length;
}

class BoardSnapshot {
  const BoardSnapshot({required this.milestoneId, required this.columns});

  factory BoardSnapshot.fromJson(Map<String, dynamic> json) => BoardSnapshot(
    milestoneId: json['milestone_id'] as String,
    columns: (json['columns'] as List<dynamic>? ?? const [])
        .map((e) => BoardColumn.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String milestoneId;
  final List<BoardColumn> columns;
}
