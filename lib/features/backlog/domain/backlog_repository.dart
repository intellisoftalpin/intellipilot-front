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

  // ---- issues (unified: Story / Task / Bug / sub-task) ----
  Future<Result<List<Issue>, AppFailure>> listIssues(String projectId);
  Future<Result<Issue, AppFailure>> getIssue(String projectId, String id);
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
