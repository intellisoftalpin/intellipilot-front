import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/interceptors/etag_interceptor.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';

const _base = '/api/v1/projects';

String? _etag(Response<dynamic> r) =>
    r.headers.value('etag') ?? r.headers.value('ETag');

class BacklogRepositoryImpl implements BacklogRepository {
  BacklogRepositoryImpl(this._api);
  final ApiClient _api;

  // ---- epics ----

  @override
  Future<Result<List<Epic>, AppFailure>> listEpics(String projectId) async {
    final res = await _api.get('$_base/$projectId/epics');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['epics'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => Epic.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Epic, AppFailure>> getEpic(String projectId, String id) async {
    final res = await _api.get('$_base/$projectId/epics/$id');
    return res.when(
      ok: (r) => Ok(
        Epic.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<Epic, AppFailure>> createEpic(
    String projectId,
    CreateEpicRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/epics',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(
        Epic.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<Epic, AppFailure>> updateEpic(
    String projectId,
    String id, {
    required UpdateEpicRequest body,
    required String etag,
  }) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/epics/$id',
        data: body.toJson(),
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return Ok(
        Epic.fromJson(
          response.data as Map<String, dynamic>,
          etag: _etag(response),
        ),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteEpic(
    String projectId,
    String id, {
    required String etag,
  }) async {
    try {
      await _api.dio.delete<dynamic>(
        '$_base/$projectId/epics/$id',
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> moveEpic(
    String projectId,
    String id,
    ReorderRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/epics/$id/move',
      body: body.toJson(),
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  // ---- user stories ----

  @override
  Future<Result<List<UserStory>, AppFailure>> listUserStories(
    String projectId,
  ) async {
    final res = await _api.get('$_base/$projectId/userstories');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['user_stories'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => UserStory.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<UserStory, AppFailure>> getUserStory(
    String projectId,
    String id,
  ) async {
    final res = await _api.get('$_base/$projectId/userstories/$id');
    return res.when(
      ok: (r) => Ok(
        UserStory.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<UserStory, AppFailure>> createUserStory(
    String projectId,
    CreateUserStoryRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/userstories',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(
        UserStory.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<UserStory, AppFailure>> updateUserStory(
    String projectId,
    String id, {
    required UpdateUserStoryRequest body,
    required String etag,
  }) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/userstories/$id',
        data: body.toJson(),
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return Ok(
        UserStory.fromJson(
          response.data as Map<String, dynamic>,
          etag: _etag(response),
        ),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteUserStory(
    String projectId,
    String id, {
    required String etag,
  }) async {
    try {
      await _api.dio.delete<dynamic>(
        '$_base/$projectId/userstories/$id',
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> moveUserStory(
    String projectId,
    String id,
    ReorderRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/userstories/$id/move',
      body: body.toJson(),
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  @override
  Future<Result<List<UserStory>, AppFailure>> bulkCreateUserStories(
    String projectId,
    BulkCreateUserStoriesRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/userstories/bulk',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) {
        final data = r.data as Map<String, dynamic>;
        final raw = data['user_stories'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => UserStory.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  // ---- tasks ----

  @override
  Future<Result<List<Task>, AppFailure>> listTasks(String projectId) async {
    final res = await _api.get('$_base/$projectId/tasks');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['tasks'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Task, AppFailure>> getTask(
    String projectId,
    String id,
  ) async {
    final res = await _api.get('$_base/$projectId/tasks/$id');
    return res.when(
      ok: (r) => Ok(
        Task.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<Task, AppFailure>> createTask(
    String projectId,
    CreateTaskRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/tasks',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(
        Task.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<Task, AppFailure>> updateTask(
    String projectId,
    String id, {
    required UpdateTaskRequest body,
    required String etag,
  }) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/tasks/$id',
        data: body.toJson(),
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return Ok(
        Task.fromJson(
          response.data as Map<String, dynamic>,
          etag: _etag(response),
        ),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteTask(
    String projectId,
    String id, {
    required String etag,
  }) async {
    try {
      await _api.dio.delete<dynamic>(
        '$_base/$projectId/tasks/$id',
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  // ---- issues ----

  @override
  Future<Result<List<Issue>, AppFailure>> listIssues(String projectId) async {
    final res = await _api.get('$_base/$projectId/issues');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['issues'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => Issue.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Issue, AppFailure>> getIssue(
    String projectId,
    String id,
  ) async {
    final res = await _api.get('$_base/$projectId/issues/$id');
    return res.when(
      ok: (r) => Ok(
        Issue.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<Issue, AppFailure>> createIssue(
    String projectId,
    CreateIssueRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/issues',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(
        Issue.fromJson(r.data as Map<String, dynamic>, etag: _etag(r)),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<Issue, AppFailure>> updateIssue(
    String projectId,
    String id, {
    required UpdateIssueRequest body,
    required String etag,
  }) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/issues/$id',
        data: body.toJson(),
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return Ok(
        Issue.fromJson(
          response.data as Map<String, dynamic>,
          etag: _etag(response),
        ),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteIssue(
    String projectId,
    String id, {
    required String etag,
  }) async {
    try {
      await _api.dio.delete<dynamic>(
        '$_base/$projectId/issues/$id',
        options: Options(
          extra: <String, dynamic>{EtagInterceptor.etagExtra: etag},
        ),
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<ResolvedRef, AppFailure>> resolveRef(
    String projectId,
    int reference,
  ) async {
    final res = await _api.get('$_base/$projectId/resolve/$reference');
    return res.when(
      ok: (r) => Ok(ResolvedRef.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }
}
