import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';

/// One column of the board: a status taxonomy item (or null = "no status")
/// plus the cards in that column.
class BoardColumn {
  const BoardColumn({required this.status, required this.userStories});

  factory BoardColumn.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    final stories =
        (json['user_stories'] as List<dynamic>? ?? const [])
            .map((e) => BoardCard.fromJson(e as Map<String, dynamic>))
            .toList();
    return BoardColumn(
      status: rawStatus is Map<String, dynamic>
          ? TaxonomyItem.fromJson(rawStatus)
          : null,
      userStories: stories,
    );
  }

  /// `null` for the trailing column that collects stories with no status.
  final TaxonomyItem? status;
  final List<BoardCard> userStories;

  /// Column id. Null status uses a stable sentinel so [Map] keys + drag
  /// targets work consistently.
  String get id => status?.id ?? _noStatusId;

  static const _noStatusId = '__no_status__';
}

/// A user-story card on the board, with its nested tasks (the backend
/// already inlines tasks under each story for this view).
class BoardCard {
  const BoardCard({required this.story, required this.tasks});

  factory BoardCard.fromJson(Map<String, dynamic> json) {
    final tasksRaw = json['tasks'] as List<dynamic>? ?? const [];
    return BoardCard(
      story: UserStory.fromJson(json),
      tasks: tasksRaw
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final UserStory story;
  final List<Task> tasks;

  int get totalTasks => tasks.length;
  int get closedTasks => tasks.where((t) => t.statusId != null).length;
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
