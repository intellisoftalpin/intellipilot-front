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
}
