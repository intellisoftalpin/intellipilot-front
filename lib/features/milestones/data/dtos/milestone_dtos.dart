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
