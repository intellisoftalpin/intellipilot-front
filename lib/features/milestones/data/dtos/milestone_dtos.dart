import 'package:intellipilot/core/network/etag.dart';

/// A milestone: the unit of release planning. A milestone is composed of
/// epics — issues reach it through their epic and never directly.
class Milestone {
  const Milestone({
    required this.id,
    required this.projectId,
    required this.name,
    required this.slug,
    required this.closed,
    required this.order,
    required this.version,
    required this.createdAt,
    required this.modifiedAt,
    this.description = '',
    this.startDate,
    this.endDate,
    this.actualEndDate,
    this.businessReleaseDate,
    this.closedAt,
    this.etag,
  });

  factory Milestone.fromJson(Map<String, dynamic> json, {String? etag}) =>
      Milestone(
        id: json['id'] as String,
        projectId: json['project_id'] as String,
        name: json['name'] as String,
        slug: (json['slug'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        startDate: _date(json['start_date']),
        endDate: _date(json['end_date']),
        actualEndDate: _date(json['actual_end_date']),
        businessReleaseDate: _date(json['business_release_date']),
        closed: (json['closed'] as bool?) ?? false,
        closedAt: _dt(json['closed_at']),
        order: (json['order'] as num?)?.toDouble() ?? 0.0,
        version: (json['version'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        modifiedAt: DateTime.parse(json['modified_at'] as String),
        etag: canonicalEtag(json, etag),
      );

  final String id;
  final String projectId;
  final String name;
  final String slug;

  /// Markdown notes. Empty when unset.
  final String description;

  final DateTime? startDate;

  /// The planned technical release date.
  final DateTime? endDate;

  /// When the milestone actually finished, once recorded. The gap against
  /// [endDate] is the slip — or, when earlier, the time saved.
  final DateTime? actualEndDate;

  /// The technical end that really happened: the actual date when recorded,
  /// otherwise the plan. Sorting and the gantt bar both key off this.
  DateTime? get effectiveEndDate => actualEndDate ?? endDate;

  /// Days late (positive) or early (negative), or null when the milestone has
  /// no recorded actual end or nothing to compare it against.
  int? get slipDays {
    final planned = endDate;
    final actual = actualEndDate;
    if (planned == null || actual == null) return null;
    final days = actual.difference(planned).inDays;
    return days == 0 ? null : days;
  }

  /// Commercial ship date, always after whichever technical end really
  /// happened — [actualEndDate] when set, otherwise [endDate].
  ///
  /// The API omits the field entirely for users without
  /// `milestone.business_release.view`, so `null` here means "unset **or** not
  /// visible to me". Gate the UI on the permission, not on this being null.
  final DateTime? businessReleaseDate;

  /// `true` once the milestone is marked completed. Reversible.
  final bool closed;
  final DateTime? closedAt;
  final double order;
  final int version;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// Revision token for `If-Match` on updates.
  final String? etag;
}

DateTime? _date(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

DateTime? _dt(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

class CreateMilestoneRequest {
  const CreateMilestoneRequest({
    required this.name,
    this.slug,
    this.description = '',
    this.startDate,
    this.endDate,
    this.businessReleaseDate,
  });
  final String name;
  final String? slug;
  final String description;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? businessReleaseDate;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (slug != null && slug!.isNotEmpty) 'slug': slug,
    if (description.isNotEmpty) 'description': description,
    if (startDate != null) 'start_date': isoDate(startDate!),
    if (endDate != null) 'end_date': isoDate(endDate!),
    if (businessReleaseDate != null)
      'business_release_date': isoDate(businessReleaseDate!),
  };
}

/// Partial milestone edit.
///
/// Date fields are three-state: leaving them at [absent] keeps the stored
/// value, `null` clears it, a `DateTime` sets it.
class UpdateMilestoneRequest {
  const UpdateMilestoneRequest({
    this.name,
    this.description,
    this.startDate = absent,
    this.endDate = absent,
    this.actualEndDate = absent,
    this.businessReleaseDate = absent,
  });

  /// Sentinel meaning "don't send this field at all".
  static const Object absent = _Absent();

  final String? name;
  final String? description;
  final Object? startDate;
  final Object? endDate;

  /// When the milestone actually finished. `null` clears it.
  final Object? actualEndDate;
  final Object? businessReleaseDate;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    ..._dateField('start_date', startDate),
    ..._dateField('end_date', endDate),
    ..._dateField('actual_end_date', actualEndDate),
    ..._dateField('business_release_date', businessReleaseDate),
  };

  static Map<String, dynamic> _dateField(String key, Object? value) {
    if (value is _Absent) return const {};
    return {key: value is DateTime ? isoDate(value) : null};
  }

  /// Whether this patch would change anything at all.
  bool get isEmpty => toJson().isEmpty;
}

class MilestoneStats {
  const MilestoneStats({
    required this.totalPoints,
    required this.completedPoints,
    required this.totalTasks,
    required this.completedTasks,
  });

  factory MilestoneStats.fromJson(Map<String, dynamic> json) => MilestoneStats(
    totalPoints: (json['total_points'] as num?)?.toDouble() ?? 0.0,
    completedPoints: (json['completed_points'] as num?)?.toDouble() ?? 0.0,
    totalTasks: (json['total_tasks'] as num?)?.toInt() ?? 0,
    completedTasks: (json['completed_tasks'] as num?)?.toInt() ?? 0,
  );

  static const empty = MilestoneStats(
    totalPoints: 0,
    completedPoints: 0,
    totalTasks: 0,
    completedTasks: 0,
  );

  final double totalPoints;
  final double completedPoints;
  final int totalTasks;
  final int completedTasks;

  /// Fraction in [0, 1] for the progress bar, or null when total is 0.
  double? get pointsFraction =>
      totalPoints <= 0 ? null : completedPoints / totalPoints;

  double? get tasksFraction =>
      totalTasks <= 0 ? null : completedTasks / totalTasks;
}

class _Absent {
  const _Absent();
}
