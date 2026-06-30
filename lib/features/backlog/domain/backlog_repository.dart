import 'dart:typed_data';

import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';

abstract interface class BacklogRepository {
  // ---- epics ----
  Future<Result<List<Epic>, AppFailure>> listEpics(String projectId);
  Future<Result<Epic, AppFailure>> getEpic(String projectId, String id);
  Future<Result<Epic, AppFailure>> createEpic(
    String projectId,
    CreateEpicRequest body,
  );
  Future<Result<Epic, AppFailure>> updateEpic(
    String projectId,
    String id, {
    required UpdateEpicRequest body,
    required String etag,
  });
  Future<Result<Unit, AppFailure>> deleteEpic(
    String projectId,
    String id, {
    required String etag,
  });
  Future<Result<Unit, AppFailure>> moveEpic(
    String projectId,
    String id,
    ReorderRequest body,
  );

  /// Upload (replace) an epic's cover image. Returns the refreshed epic so the
  /// caller picks up the new `coverImageUpdatedAt` for cache-busting.
  Future<Result<Epic, AppFailure>> uploadEpicCover(
    String projectId,
    String id, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
  });

  /// Remove an epic's cover image (reset to the colour swatch). Returns the
  /// refreshed epic.
  Future<Result<Epic, AppFailure>> deleteEpicCover(String projectId, String id);

  // ---- issues (unified: Story / Task / Bug / sub-task) ----
  Future<Result<List<Issue>, AppFailure>> listIssues(String projectId);
  Future<Result<Issue, AppFailure>> getIssue(String projectId, String id);

  /// Resolve a human-readable issue key's numeric ref (e.g. 398 from `PS-398`)
  /// to the full issue — backs key-based deep links.
  Future<Result<Issue, AppFailure>> getIssueByRef(String projectId, int ref);
  Future<Result<Issue, AppFailure>> createIssue(
    String projectId,
    CreateIssueRequest body,
  );
  Future<Result<Issue, AppFailure>> updateIssue(
    String projectId,
    String id, {
    required UpdateIssueRequest body,
    required String etag,
  });
  Future<Result<Unit, AppFailure>> deleteIssue(
    String projectId,
    String id, {
    required String etag,
  });
  Future<Result<Unit, AppFailure>> moveIssue(
    String projectId,
    String id,
    ReorderRequest body,
  );
  Future<Result<List<Issue>, AppFailure>> bulkCreateIssues(
    String projectId,
    BulkCreateIssuesRequest body,
  );

  /// Resolve a numeric reference within a project to its entity kind + id.
  Future<Result<ResolvedRef, AppFailure>> resolveRef(
    String projectId,
    int reference,
  );
}
