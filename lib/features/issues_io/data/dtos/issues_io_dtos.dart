/// DTOs for the issue import/export feature.
///
/// Import is a two-step flow: `preview` parses the uploaded CSV and reports
/// the distinct Type/Status/Priority/Component values (each pre-matched
/// against the project taxonomy where possible) plus unmatched comment
/// authors and warnings. The UI turns those into a [ImportMapping] (map each
/// value to an existing item, or create a new one) and posts it back to
/// `commit`, which returns an [ImportResult] summary.
library;

/// A distinct categorical value found in the file, with the taxonomy item it
/// auto-matched to (case-insensitive by name) — null when nothing matched.
class ValueMatch {
  const ValueMatch({required this.value, this.matchedId});

  factory ValueMatch.fromJson(Map<String, dynamic> json) => ValueMatch(
    value: json['value'] as String,
    matchedId: json['matched_id'] as String?,
  );

  final String value;
  final String? matchedId;
}

/// Result of parsing the file: counts + the distinct values per dimension.
class ImportPreview {
  const ImportPreview({
    required this.issueCount,
    required this.types,
    required this.statuses,
    required this.priorities,
    required this.components,
    required this.unmatchedUsers,
    required this.warnings,
  });

  factory ImportPreview.fromJson(Map<String, dynamic> json) {
    List<ValueMatch> matches(String key) =>
        ((json[key] as List<dynamic>?) ?? const [])
            .map((e) => ValueMatch.fromJson(e as Map<String, dynamic>))
            .toList();
    List<String> strings(String key) =>
        ((json[key] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList();
    return ImportPreview(
      issueCount: (json['issue_count'] as num).toInt(),
      types: matches('types'),
      statuses: matches('statuses'),
      priorities: matches('priorities'),
      components: matches('components'),
      unmatchedUsers: strings('unmatched_users'),
      warnings: strings('warnings'),
    );
  }

  final int issueCount;
  final List<ValueMatch> types;
  final List<ValueMatch> statuses;
  final List<ValueMatch> priorities;
  final List<ValueMatch> components;
  final List<String> unmatchedUsers;
  final List<String> warnings;
}

/// What to do with one categorical value on commit: map it to an existing
/// taxonomy item ([target]), create a new item ([create]), or skip (both unset).
class ValueChoice {
  const ValueChoice({required this.value, this.target, this.create = false});

  final String value;
  final String? target;
  final bool create;

  Map<String, dynamic> toJson() => {
    'value': value,
    if (target != null) 'target': target,
    'create': create,
  };
}

/// The full mapping payload posted to commit, one list per dimension.
class ImportMapping {
  const ImportMapping({
    this.types = const [],
    this.statuses = const [],
    this.priorities = const [],
    this.components = const [],
    this.users = const [],
  });

  final List<ValueChoice> types;
  final List<ValueChoice> statuses;
  final List<ValueChoice> priorities;
  final List<ValueChoice> components;
  final List<ValueChoice> users;

  Map<String, dynamic> toJson() => {
    'types': types.map((c) => c.toJson()).toList(),
    'statuses': statuses.map((c) => c.toJson()).toList(),
    'priorities': priorities.map((c) => c.toJson()).toList(),
    'components': components.map((c) => c.toJson()).toList(),
    'users': users.map((c) => c.toJson()).toList(),
  };
}

/// Commit summary returned by the server.
class ImportResult {
  const ImportResult({
    required this.createdIssues,
    required this.createdEpics,
    required this.createdComments,
    required this.createdTaxonomy,
    required this.skipped,
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) => ImportResult(
    createdIssues: (json['created_issues'] as num).toInt(),
    createdEpics: (json['created_epics'] as num).toInt(),
    createdComments: (json['created_comments'] as num).toInt(),
    createdTaxonomy: (json['created_taxonomy'] as num).toInt(),
    skipped: ((json['skipped'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toList(),
  );

  final int createdIssues;
  final int createdEpics;
  final int createdComments;
  final int createdTaxonomy;
  final List<String> skipped;
}

/// The two export formats the server can render.
enum ExportFormat {
  csv('csv', 'text/csv', 'csv'),
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'xlsx',
  );

  const ExportFormat(this.wire, this.mimeType, this.extension);
  final String wire;
  final String mimeType;
  final String extension;
}
