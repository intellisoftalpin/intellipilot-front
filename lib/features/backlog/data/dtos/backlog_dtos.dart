/// Backend epic. `etag` is filled from the response header when available so
/// callers can round-trip it as `If-Match` on subsequent updates.
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
      etag: etag,
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

class UserStory {
  const UserStory({
    required this.id,
    required this.projectId,
    required this.reference,
    required this.subject,
    required this.description,
    required this.order,
    required this.version,
    required this.createdAt,
    required this.modifiedAt,
    this.statusId,
    this.epicId,
    this.milestoneId,
    this.pointsId,
    this.ownerId,
    this.assignedTo,
    this.etag,
  });

  factory UserStory.fromJson(Map<String, dynamic> json, {String? etag}) {
    return UserStory(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      reference: (json['ref'] as num?)?.toInt() ?? 0,
      subject: json['subject'] as String,
      description: (json['description'] as String?) ?? '',
      statusId: json['status_id'] as String?,
      epicId: json['epic_id'] as String?,
      milestoneId: json['milestone_id'] as String?,
      pointsId: json['points_id'] as String?,
      ownerId: json['owner_id'] as String?,
      assignedTo: json['assigned_to'] as String?,
      order: (json['order'] as num?)?.toDouble() ?? 0.0,
      version: (json['version'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      modifiedAt: DateTime.parse(json['modified_at'] as String),
      etag: etag,
    );
  }

  final String id;
  final String projectId;
  final int reference;
  final String subject;
  final String description;
  final String? statusId;
  final String? epicId;
  final String? milestoneId;
  final String? pointsId;
  final String? ownerId;
  final String? assignedTo;
  final double order;
  final int version;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? etag;
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
  });

  final String? subject;
  final String? description;

  /// `_Absent` keeps the field out of the body; `null` clears the FK.
  final Object? statusId;
  final String? color;
  final Object? assignedTo;

  Map<String, dynamic> toJson() => {
    if (subject != null) 'subject': subject,
    if (description != null) 'description': description,
    if (statusId is! _Absent) 'status_id': statusId,
    if (color != null) 'color': color,
    if (assignedTo is! _Absent) 'assigned_to': assignedTo,
  };
}

class CreateUserStoryRequest {
  const CreateUserStoryRequest({
    required this.subject,
    this.description = '',
    this.statusId,
    this.epicId,
    this.milestoneId,
    this.pointsId,
    this.assignedTo,
  });

  final String subject;
  final String description;
  final String? statusId;
  final String? epicId;
  final String? milestoneId;
  final String? pointsId;
  final String? assignedTo;

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'description': description,
    if (statusId != null) 'status_id': statusId,
    if (epicId != null) 'epic_id': epicId,
    if (milestoneId != null) 'milestone_id': milestoneId,
    if (pointsId != null) 'points_id': pointsId,
    if (assignedTo != null) 'assigned_to': assignedTo,
  };
}

class UpdateUserStoryRequest {
  const UpdateUserStoryRequest({
    this.subject,
    this.description,
    this.statusId = const _Absent(),
    this.epicId = const _Absent(),
    this.milestoneId = const _Absent(),
    this.pointsId = const _Absent(),
    this.assignedTo = const _Absent(),
  });

  final String? subject;
  final String? description;
  final Object? statusId;
  final Object? epicId;
  final Object? milestoneId;
  final Object? pointsId;
  final Object? assignedTo;

  Map<String, dynamic> toJson() => {
    if (subject != null) 'subject': subject,
    if (description != null) 'description': description,
    if (statusId is! _Absent) 'status_id': statusId,
    if (epicId is! _Absent) 'epic_id': epicId,
    if (milestoneId is! _Absent) 'milestone_id': milestoneId,
    if (pointsId is! _Absent) 'points_id': pointsId,
    if (assignedTo is! _Absent) 'assigned_to': assignedTo,
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

class BulkCreateUserStoryItem {
  const BulkCreateUserStoryItem({
    required this.subject,
    this.epicId,
    this.milestoneId,
  });
  final String subject;
  final String? epicId;
  final String? milestoneId;

  Map<String, dynamic> toJson() => {
    'subject': subject,
    if (epicId != null) 'epic_id': epicId,
    if (milestoneId != null) 'milestone_id': milestoneId,
  };
}

class BulkCreateUserStoriesRequest {
  const BulkCreateUserStoriesRequest(this.items);
  final List<BulkCreateUserStoryItem> items;

  Map<String, dynamic> toJson() => {
    'items': items.map((i) => i.toJson()).toList(),
  };
}

class _Absent {
  const _Absent();
}
