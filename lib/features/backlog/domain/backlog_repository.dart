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

  // ---- user stories ----
  Future<Result<List<UserStory>, AppFailure>> listUserStories(String projectId);
  Future<Result<UserStory, AppFailure>> getUserStory(
    String projectId,
    String id,
  );
  Future<Result<UserStory, AppFailure>> createUserStory(
    String projectId,
    CreateUserStoryRequest body,
  );
  Future<Result<UserStory, AppFailure>> updateUserStory(
    String projectId,
    String id, {
    required UpdateUserStoryRequest body,
    required String etag,
  });
  Future<Result<Unit, AppFailure>> deleteUserStory(
    String projectId,
    String id, {
    required String etag,
  });
  Future<Result<Unit, AppFailure>> moveUserStory(
    String projectId,
    String id,
    ReorderRequest body,
  );
  Future<Result<List<UserStory>, AppFailure>> bulkCreateUserStories(
    String projectId,
    BulkCreateUserStoriesRequest body,
  );

  // ---- tasks ----
  Future<Result<List<Task>, AppFailure>> listTasks(String projectId);
  Future<Result<Task, AppFailure>> getTask(String projectId, String id);
  Future<Result<Task, AppFailure>> createTask(
    String projectId,
    CreateTaskRequest body,
  );
  Future<Result<Task, AppFailure>> updateTask(
    String projectId,
    String id, {
    required UpdateTaskRequest body,
    required String etag,
  });
  Future<Result<Unit, AppFailure>> deleteTask(
    String projectId,
    String id, {
    required String etag,
  });

  // ---- issues ----
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

  /// Resolve a numeric reference within a project to its entity kind + id.
  Future<Result<ResolvedRef, AppFailure>> resolveRef(
    String projectId,
    int reference,
  );
}
