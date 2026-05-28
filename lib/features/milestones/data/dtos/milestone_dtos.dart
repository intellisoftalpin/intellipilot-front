/// Minimal milestone DTO — Phase 10 only needs the list to populate the
/// board's milestone picker. Full CRUD lands in Phase 11.
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
    this.startDate,
    this.endDate,
    this.closedAt,
  });

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    name: json['name'] as String,
    slug: (json['slug'] as String?) ?? '',
    startDate: _date(json['start_date']),
    endDate: _date(json['end_date']),
    closed: (json['closed'] as bool?) ?? false,
    closedAt: _dt(json['closed_at']),
    order: (json['order'] as num?)?.toDouble() ?? 0.0,
    version: (json['version'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
    modifiedAt: DateTime.parse(json['modified_at'] as String),
  );

  final String id;
  final String projectId;
  final String name;
  final String slug;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool closed;
  final DateTime? closedAt;
  final double order;
  final int version;
  final DateTime createdAt;
  final DateTime modifiedAt;
}

DateTime? _date(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

DateTime? _dt(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

class CreateMilestoneRequest {
  const CreateMilestoneRequest({
    required this.name,
    this.slug,
    this.startDate,
    this.endDate,
  });
  final String name;
  final String? slug;
  final DateTime? startDate;
  final DateTime? endDate;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (slug != null && slug!.isNotEmpty) 'slug': slug,
    if (startDate != null) 'start_date': _isoDate(startDate!),
    if (endDate != null) 'end_date': _isoDate(endDate!),
  };
}

class UpdateMilestoneRequest {
  const UpdateMilestoneRequest({
    this.name,
    this.startDate = const _Absent(),
    this.endDate = const _Absent(),
  });
  final String? name;

  /// `_Absent` keeps the date out of the body; `null` clears it.
  final Object? startDate;
  final Object? endDate;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (startDate is! _Absent)
      'start_date': startDate is DateTime ? _isoDate(startDate! as DateTime) : null,
    if (endDate is! _Absent)
      'end_date': endDate is DateTime ? _isoDate(endDate! as DateTime) : null,
  };
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
    completedPoints:
        (json['completed_points'] as num?)?.toDouble() ?? 0.0,
    totalTasks: (json['total_tasks'] as num?)?.toInt() ?? 0,
    completedTasks: (json['completed_tasks'] as num?)?.toInt() ?? 0,
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
