import 'package:intellipilot/core/network/etag.dart';

/// Backend epic. `etag` is the canonical `"<id>:<version>"` revision token,
/// round-tripped as `If-Match` on subsequent updates.
class Epic {
  const Epic({
    required this.id,
    required this.projectId,
    required this.reference,
    required this.subject,
    required this.description,
    required this.color,
    required this.order,
    required this.version,
    required this.createdAt,
    required this.modifiedAt,
    this.statusId,
    this.ownerId,
    this.assignedTo,
    this.etag,
  });

  factory Epic.fromJson(Map<String, dynamic> json, {String? etag}) {
    return Epic(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      reference: (json['ref'] as num?)?.toInt() ?? 0,
      subject: json['subject'] as String,
      description: (json['description'] as String?) ?? '',
      color: (json['color'] as String?) ?? '',
      order: (json['order'] as num?)?.toDouble() ?? 0.0,
      version: (json['version'] as num?)?.toInt() ?? 0,
      statusId: json['status_id'] as String?,
      ownerId: json['owner_id'] as String?,
      assignedTo: json['assigned_to'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      modifiedAt: DateTime.parse(json['modified_at'] as String),
      etag: canonicalEtag(json, etag),
    );
  }

  final String id;
  final String projectId;
  final int reference;
  final String subject;
  final String description;
  final String? statusId;
  final String color;
  final String? ownerId;
  final String? assignedTo;
  final double order;
  final int version;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? etag;
}

/// The unified work item (Story / Task / Bug / sub-task). `typeId` is an
/// `issue_type` taxonomy item; `parentId` nests sub-tasks; `epicId` groups
/// under an epic; `milestoneId` assigns a sprint; `pointsId` is the estimate.
class Issue {
  const Issue({
    required this.id,
    required this.projectId,
    required this.reference,
    required this.subject,
    required this.description,
    required this.labels,
    required this.components,
    required this.order,
    required this.version,
    required this.createdAt,
    required this.modifiedAt,
    this.statusId,
    this.typeId,
    this.priorityId,
    this.severityId,
    this.pointsId,
    this.epicId,
    this.parentId,
    this.milestoneId,
    this.ownerId,
    this.assignedTo,
    this.etag,
  });

  factory Issue.fromJson(Map<String, dynamic> json, {String? etag}) {
    return Issue(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      reference: (json['ref'] as num?)?.toInt() ?? 0,
      subject: json['subject'] as String,
      description: (json['description'] as String?) ?? '',
      statusId: json['status_id'] as String?,
      typeId: json['type_id'] as String?,
      priorityId: json['priority_id'] as String?,
      severityId: json['severity_id'] as String?,
      pointsId: json['points_id'] as String?,
      epicId: json['epic_id'] as String?,
      parentId: json['parent_id'] as String?,
      milestoneId: json['milestone_id'] as String?,
      ownerId: json['owner_id'] as String?,
      assignedTo: json['assigned_to'] as String?,
      labels: (json['labels'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      components: (json['components'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      order: (json['order'] as num?)?.toDouble() ?? 0.0,
      version: (json['version'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      modifiedAt: DateTime.parse(json['modified_at'] as String),
      etag: canonicalEtag(json, etag),
    );
  }

  final String id;
  final String projectId;
  final int reference;
  final String subject;
  final String description;
  final String? statusId;
  final String? typeId;
  final String? priorityId;
  final String? severityId;
  final String? pointsId;
  final String? epicId;
  final String? parentId;
  final String? milestoneId;
  final String? ownerId;
  final String? assignedTo;
  final List<String> labels;
  final List<String> components;
  final double order;
  final int version;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? etag;

  /// Whether this issue is a sub-task (has a parent issue).
  bool get isSubtask => parentId != null;
}

// ---- request bodies ----

class CreateEpicRequest {
  const CreateEpicRequest({
    required this.subject,
    this.description = '',
    this.statusId,
    this.color = '',
    this.assignedTo,
  });

  final String subject;
  final String description;
  final String? statusId;
  final String color;
  final String? assignedTo;

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'description': description,
    if (statusId != null) 'status_id': statusId,
    'color': color,
    if (assignedTo != null) 'assigned_to': assignedTo,
  };
}

class UpdateEpicRequest {
  const UpdateEpicRequest({
    this.subject,
    this.description,
    this.statusId = const _Absent(),
    this.color,
    this.assignedTo = const _Absent(),
    this.ownerId = const _Absent(),
  });

  final String? subject;
  final String? description;

  /// `_Absent` keeps the field out of the body; `null` clears the FK.
  final Object? statusId;
  final String? color;
  final Object? assignedTo;
  final Object? ownerId;

  Map<String, dynamic> toJson() => {
    if (subject != null) 'subject': subject,
    if (description != null) 'description': description,
    if (statusId is! _Absent) 'status_id': statusId,
    if (color != null) 'color': color,
    if (assignedTo is! _Absent) 'assigned_to': assignedTo,
    if (ownerId is! _Absent) 'owner_id': ownerId,
  };
}

class ReorderRequest {
  const ReorderRequest({this.beforeId, this.afterId});
  final String? beforeId;
  final String? afterId;

  Map<String, dynamic> toJson() => {
    if (beforeId != null) 'before_id': beforeId,
    if (afterId != null) 'after_id': afterId,
  };
}

class CreateIssueRequest {
  const CreateIssueRequest({
    required this.subject,
    this.description = '',
    this.statusId,
    this.typeId,
    this.priorityId,
    this.severityId,
    this.pointsId,
    this.epicId,
    this.parentId,
    this.milestoneId,
    this.assignedTo,
    this.labels = const [],
    this.components = const [],
  });

  final String subject;
  final String description;
  final String? statusId;
  final String? typeId;
  final String? priorityId;
  final String? severityId;
  final String? pointsId;
  final String? epicId;
  final String? parentId;
  final String? milestoneId;
  final String? assignedTo;
  final List<String> labels;
  final List<String> components;

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'description': description,
    if (statusId != null) 'status_id': statusId,
    if (typeId != null) 'type_id': typeId,
    if (priorityId != null) 'priority_id': priorityId,
    if (severityId != null) 'severity_id': severityId,
    if (pointsId != null) 'points_id': pointsId,
    if (epicId != null) 'epic_id': epicId,
    if (parentId != null) 'parent_id': parentId,
    if (milestoneId != null) 'milestone_id': milestoneId,
    if (assignedTo != null) 'assigned_to': assignedTo,
    'labels': labels,
    'components': components,
  };
}

class UpdateIssueRequest {
  const UpdateIssueRequest({
    this.subject,
    this.description,
    this.statusId = const _Absent(),
    this.typeId = const _Absent(),
    this.priorityId = const _Absent(),
    this.severityId = const _Absent(),
    this.pointsId = const _Absent(),
    this.epicId = const _Absent(),
    this.parentId = const _Absent(),
    this.milestoneId = const _Absent(),
    this.assignedTo = const _Absent(),
    this.ownerId = const _Absent(),
    this.labels,
    this.components,
  });

  final String? subject;
  final String? description;
  final Object? statusId;
  final Object? typeId;
  final Object? priorityId;
  final Object? severityId;
  final Object? pointsId;
  final Object? epicId;
  final Object? parentId;
  final Object? milestoneId;
  final Object? assignedTo;
  final Object? ownerId;

  /// Backend treats absent as "leave alone", present as "replace fully".
  final List<String>? labels;
  final List<String>? components;

  Map<String, dynamic> toJson() => {
    if (subject != null) 'subject': subject,
    if (description != null) 'description': description,
    if (statusId is! _Absent) 'status_id': statusId,
    if (typeId is! _Absent) 'type_id': typeId,
    if (priorityId is! _Absent) 'priority_id': priorityId,
    if (severityId is! _Absent) 'severity_id': severityId,
    if (pointsId is! _Absent) 'points_id': pointsId,
    if (epicId is! _Absent) 'epic_id': epicId,
    if (parentId is! _Absent) 'parent_id': parentId,
    if (milestoneId is! _Absent) 'milestone_id': milestoneId,
    if (assignedTo is! _Absent) 'assigned_to': assignedTo,
    if (ownerId is! _Absent) 'owner_id': ownerId,
    if (labels != null) 'labels': labels,
    if (components != null) 'components': components,
  };
}

class BulkCreateIssuesRequest {
  const BulkCreateIssuesRequest(this.items);
  final List<CreateIssueRequest> items;

  Map<String, dynamic> toJson() => {
    'items': items.map((i) => i.toJson()).toList(),
  };
}

/// Output of `GET /projects/:id/resolve/:ref`: which entity kind a numeric
/// reference belongs to.
class ResolvedRef {
  const ResolvedRef({required this.kind, required this.id, required this.ref});

  factory ResolvedRef.fromJson(Map<String, dynamic> json) => ResolvedRef(
    kind: json['kind'] as String,
    id: json['id'] as String,
    ref: (json['ref'] as num?)?.toInt() ?? 0,
  );

  /// One of `epic`, `issue`.
  final String kind;
  final String id;
  final int ref;
}

class _Absent {
  const _Absent();
}
