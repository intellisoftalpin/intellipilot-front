import 'package:intellipilot/core/models/user_ref.dart';

/// The backlog entity kinds that share comments / history / attachments.
/// The `slug` is the URL path segment (`epics | issues`) the backend exposes;
/// `wire` is the stored `target_type` value the backend returns inside DTOs
/// (`epic | issue`).
enum EntityKind {
  epic('epics', 'epic'),
  issue('issues', 'issue');

  const EntityKind(this.slug, this.wire);
  final String slug;
  final String wire;

  static EntityKind? fromWire(String wire) {
    for (final k in EntityKind.values) {
      if (k.wire == wire) return k;
    }
    return null;
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.body,
    required this.bodyHtml,
    required this.createdAt,
    this.authorId,
    this.author,
    this.editedAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['id'] as String,
    targetType: json['target_type'] as String,
    targetId: json['target_id'] as String,
    authorId: json['author_id'] as String?,
    author: json['author'] == null
        ? null
        : UserRef.fromJson(json['author'] as Map<String, dynamic>),
    body: (json['body'] as String?) ?? '',
    bodyHtml: (json['body_html'] as String?) ?? '',
    editedAt: _parseOptional(json['edited_at']),
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String targetType;
  final String targetId;
  final String? authorId;

  /// The author's avatar + identity descriptor (null for a deleted user).
  final UserRef? author;
  final String body;
  final String bodyHtml;
  final DateTime? editedAt;
  final DateTime createdAt;
}

/// One row from `GET /…/history`. The backend serializes the raw `diff`
/// object as `{ "field": [old, new], … }`. We keep it as a typed map so the
/// UI can render per-field rows without parsing it again.
class HistoryEvent {
  const HistoryEvent({
    required this.diff,
    required this.createdAt,
    this.actorId,
  });

  factory HistoryEvent.fromJson(Map<String, dynamic> json) => HistoryEvent(
    diff: Map<String, dynamic>.from(json['diff'] as Map? ?? const {}),
    actorId: json['actor_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final Map<String, dynamic> diff;
  final String? actorId;
  final DateTime createdAt;
}

class Attachment {
  const Attachment({
    required this.id,
    required this.projectId,
    required this.targetType,
    required this.targetId,
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.createdAt,
    this.uploaderId,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    targetType: json['target_type'] as String,
    targetId: json['target_id'] as String,
    uploaderId: json['uploader_id'] as String?,
    filename: json['filename'] as String,
    contentType: (json['content_type'] as String?) ?? 'application/octet-stream',
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    sha256: (json['sha256'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String projectId;
  final String targetType;
  final String targetId;
  final String? uploaderId;
  final String filename;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final DateTime createdAt;
}

/// Signed-URL envelope returned by
/// `GET /projects/:id/attachments/:id` (used by the download button).
class SignedDownload {
  const SignedDownload({
    required this.url,
    required this.expiresAt,
    required this.filename,
  });

  factory SignedDownload.fromJson(Map<String, dynamic> json) => SignedDownload(
    url: json['url'] as String,
    expiresAt: (json['expires_at'] as num).toInt(),
    filename: (json['filename'] as String?) ?? '',
  );

  final String url;
  final int expiresAt;
  final String filename;
}

/// One filtered entry on the activity stream — either a comment or a history
/// row, plus the timestamp used for chronological merging.
class ActivityEntry {
  ActivityEntry.comment(Comment this.comment)
    : history = null,
      at = comment.createdAt;
  ActivityEntry.history(HistoryEvent this.history)
    : comment = null,
      at = history.createdAt;

  final Comment? comment;
  final HistoryEvent? history;
  final DateTime at;

  bool get isComment => comment != null;
  bool get isHistory => history != null;
}

class CreateCommentRequest {
  const CreateCommentRequest({required this.body});
  final String body;
  Map<String, dynamic> toJson() => {'body': body};
}

class UpdateCommentRequest {
  const UpdateCommentRequest({required this.body});
  final String body;
  Map<String, dynamic> toJson() => {'body': body};
}

DateTime? _parseOptional(Object? raw) {
  if (raw is String && raw.isNotEmpty) return DateTime.parse(raw);
  return null;
}
