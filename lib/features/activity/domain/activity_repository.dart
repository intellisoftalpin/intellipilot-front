import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';

/// Comments + history + attachments wire-format gateway. The repository is a
/// single seam so the activity stream / detail page can resolve via DI without
/// reaching across to backlog code.
abstract interface class ActivityRepository {
  // ---- comments ----
  Future<Result<List<Comment>, AppFailure>> listComments(
    String projectId,
    EntityKind kind,
    String entityId,
  );
  Future<Result<Comment, AppFailure>> createComment(
    String projectId,
    EntityKind kind,
    String entityId,
    CreateCommentRequest body,
  );
  Future<Result<Comment, AppFailure>> updateComment(
    String projectId,
    EntityKind kind,
    String entityId,
    String commentId,
    UpdateCommentRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteComment(
    String projectId,
    EntityKind kind,
    String entityId,
    String commentId,
  );

  // ---- history ----
  Future<Result<List<HistoryEvent>, AppFailure>> listHistory(
    String projectId,
    EntityKind kind,
    String entityId,
  );

  // ---- attachments ----
  Future<Result<List<Attachment>, AppFailure>> listAttachments(
    String projectId,
    EntityKind kind,
    String entityId,
  );
  Future<Result<Attachment, AppFailure>> uploadAttachment(
    String projectId,
    EntityKind kind,
    String entityId, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  });
  Future<Result<Unit, AppFailure>> deleteAttachment(
    String projectId,
    String attachmentId,
  );
  Future<Result<SignedDownload, AppFailure>> signAttachmentUrl(
    String projectId,
    String attachmentId,
  );
}
