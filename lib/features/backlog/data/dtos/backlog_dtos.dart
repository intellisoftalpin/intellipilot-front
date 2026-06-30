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
    this.milestoneId,
    this.startDate,
    this.endDate,
    this.coverImageKind = 'none',
    this.coverImageUpdatedAt,
    this.taskTotal = 0,
    this.taskClosed = 0,
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
      milestoneId: json['milestone_id'] as String?,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      coverImageKind: (json['cover_image_kind'] as String?) ?? 'none',
      coverImageUpdatedAt: json['cover_image_updated_at'] as String?,
      taskTotal: (json['task_total'] as num?)?.toInt() ?? 0,
      taskClosed: (json['task_closed'] as num?)?.toInt() ?? 0,
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
  final String? milestoneId;

  /// `YYYY-MM-DD` dates (nullable).
  final String? startDate;
  final String? endDate;

  /// `none` (render the colour swatch) or `image` (served cover at
  /// `GET /projects/{pid}/epics/{id}/cover-image`).
  final String coverImageKind;

  /// RFC3339 timestamp used to cache-bust the cover image URL.
  final String? coverImageUpdatedAt;

  /// Derived task counts for the progress bar / count badge.
  final int taskTotal;
  final int taskClosed;
  final double order;
  final int version;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? etag;

  bool get hasCover => coverImageKind == 'image';
}

/// The unified work item (Story / Task / Bug / sub-task). `typeId` is an
/// `issue_type` taxonomy item; `parentId` nests sub-tasks; `epicId` groups
/// under an epic; `milestoneId` assigns a sprint; `sizeId` is the estimate.
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
    this.sizeId,
    this.epicId,
    this.parentId,
    this.milestoneId,
    this.ownerId,
    this.assignedTo,
    this.category,
    this.customerIds = const [],
    this.startDate,
    this.dueDate,
    this.resolution,
    this.resolvedAt,
    this.releaseVersionId,
    this.releaseText,
    this.watchers = const [],
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
      sizeId: json['size_id'] as String?,
      epicId: json['epic_id'] as String?,
      parentId: json['parent_id'] as String?,
      milestoneId: json['milestone_id'] as String?,
      ownerId: json['owner_id'] as String?,
      assignedTo: json['assigned_to'] as String?,
      category: json['category'] as String?,
      customerIds: (json['customer_ids'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      startDate: json['start_date'] as String?,
      dueDate: json['due_date'] as String?,
      resolution: json['resolution'] as String?,
      resolvedAt: json['resolved_at'] as String?,
      releaseVersionId: json['release_version_id'] as String?,
      releaseText: json['release_text'] as String?,
      labels: (json['labels'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      components: (json['components'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      watchers: (json['watchers'] as List<dynamic>? ?? const [])
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
  final String? sizeId;
  final String? epicId;
  final String? parentId;
  final String? milestoneId;
  final String? ownerId;
  final String? assignedTo;

  /// One of the fixed `IssueCategory` wire values (nullable).
  final String? category;

  /// Requesting customers (many-to-many).
  final List<String> customerIds;

  /// `YYYY-MM-DD` dates (nullable).
  final String? startDate;
  final String? dueDate;

  /// One of the fixed `IssueResolution` wire values (nullable).
  final String? resolution;

  /// RFC3339 timestamp — READ-ONLY, system-managed (never sent).
  final String? resolvedAt;

  /// Structured fix-version (id) or free-text fix-version. At most one set.
  final String? releaseVersionId;
  final String? releaseText;
  final List<String> labels;
  final List<String> components;

  /// User ids watching this issue (read path; mutate via sub-resources).
  final List<String> watchers;
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
    this.milestoneId = const _Absent(),
    this.startDate,
    this.endDate,
  });

  final String? subject;
  final String? description;

  /// `_Absent` keeps the field out of the body; `null` clears the FK.
  final Object? statusId;
  final String? color;
  final Object? assignedTo;
  final Object? ownerId;
  final Object? milestoneId;

  /// `YYYY-MM-DD`; omitted when null (backend leaves it unchanged — clearing a
  /// date is not supported, matching issues / milestones).
  final String? startDate;
  final String? endDate;

  Map<String, dynamic> toJson() => {
    if (subject != null) 'subject': subject,
    if (description != null) 'description': description,
    if (statusId is! _Absent) 'status_id': statusId,
    if (color != null) 'color': color,
    if (assignedTo is! _Absent) 'assigned_to': assignedTo,
    if (ownerId is! _Absent) 'owner_id': ownerId,
    if (milestoneId is! _Absent) 'milestone_id': milestoneId,
    if (startDate != null) 'start_date': startDate,
    if (endDate != null) 'end_date': endDate,
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
    this.sizeId,
    this.epicId,
    this.parentId,
    this.milestoneId,
    this.assignedTo,
    this.category,
    this.customerIds = const [],
    this.startDate,
    this.dueDate,
    this.resolution,
    this.releaseVersionId,
    this.releaseText,
    this.labels = const [],
    this.components = const [],
  });

  final String subject;
  final String description;
  final String? statusId;
  final String? typeId;
  final String? priorityId;
  final String? sizeId;
  final String? epicId;
  final String? parentId;
  final String? milestoneId;
  final String? assignedTo;
  final String? category;
  final List<String> customerIds;
  final String? startDate;
  final String? dueDate;
  final String? resolution;
  final String? releaseVersionId;
  final String? releaseText;
  final List<String> labels;
  final List<String> components;

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'description': description,
    if (statusId != null) 'status_id': statusId,
    if (typeId != null) 'type_id': typeId,
    if (priorityId != null) 'priority_id': priorityId,
    if (sizeId != null) 'size_id': sizeId,
    if (epicId != null) 'epic_id': epicId,
    if (parentId != null) 'parent_id': parentId,
    if (milestoneId != null) 'milestone_id': milestoneId,
    if (assignedTo != null) 'assigned_to': assignedTo,
    if (category != null) 'category': category,
    'customer_ids': customerIds,
    if (startDate != null) 'start_date': startDate,
    if (dueDate != null) 'due_date': dueDate,
    if (resolution != null) 'resolution': resolution,
    if (releaseVersionId != null) 'release_version_id': releaseVersionId,
    if (releaseText != null) 'release_text': releaseText,
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
    this.sizeId = const _Absent(),
    this.epicId = const _Absent(),
    this.parentId = const _Absent(),
    this.milestoneId = const _Absent(),
    this.assignedTo = const _Absent(),
    this.ownerId = const _Absent(),
    this.category = const _Absent(),
    this.customerIds,
    this.startDate = const _Absent(),
    this.dueDate = const _Absent(),
    this.resolution = const _Absent(),
    this.releaseVersionId = const _Absent(),
    this.releaseText = const _Absent(),
    this.labels,
    this.components,
  });

  final String? subject;
  final String? description;
  final Object? statusId;
  final Object? typeId;
  final Object? priorityId;
  final Object? sizeId;
  final Object? epicId;
  final Object? parentId;
  final Object? milestoneId;
  final Object? assignedTo;
  final Object? ownerId;
  final Object? category;

  /// Full replacement of the issue's customers when present.
  final List<String>? customerIds;
  final Object? startDate;
  final Object? dueDate;
  final Object? resolution;
  final Object? releaseVersionId;
  final Object? releaseText;

  /// Backend treats absent as "leave alone", present as "replace fully".
  final List<String>? labels;
  final List<String>? components;

  Map<String, dynamic> toJson() => {
    if (subject != null) 'subject': subject,
    if (description != null) 'description': description,
    if (statusId is! _Absent) 'status_id': statusId,
    if (typeId is! _Absent) 'type_id': typeId,
    if (priorityId is! _Absent) 'priority_id': priorityId,
    if (sizeId is! _Absent) 'size_id': sizeId,
    if (epicId is! _Absent) 'epic_id': epicId,
    if (parentId is! _Absent) 'parent_id': parentId,
    if (milestoneId is! _Absent) 'milestone_id': milestoneId,
    if (assignedTo is! _Absent) 'assigned_to': assignedTo,
    if (ownerId is! _Absent) 'owner_id': ownerId,
    if (category is! _Absent) 'category': category,
    if (customerIds != null) 'customer_ids': customerIds,
    if (startDate is! _Absent) 'start_date': startDate,
    if (dueDate is! _Absent) 'due_date': dueDate,
    if (resolution is! _Absent) 'resolution': resolution,
    if (releaseVersionId is! _Absent) 'release_version_id': releaseVersionId,
    if (releaseText is! _Absent) 'release_text': releaseText,
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
