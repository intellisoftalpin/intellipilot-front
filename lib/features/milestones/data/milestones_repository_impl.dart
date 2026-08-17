import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

const _base = '/api/v1/projects';

class MilestonesRepositoryImpl implements MilestonesRepository {
  MilestonesRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<List<Milestone>, AppFailure>> list(String projectId) async {
    final res = await _api.get('$_base/$projectId/milestones');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['milestones'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => Milestone.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Milestone, AppFailure>> get(
    String projectId,
    String id,
  ) async {
    final res = await _api.get('$_base/$projectId/milestones/$id');
    return res.when(
      ok: (r) => Ok(Milestone.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Milestone, AppFailure>> create(
    String projectId,
    CreateMilestoneRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/milestones',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(Milestone.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Milestone, AppFailure>> update(
    String projectId,
    String id, {
    required UpdateMilestoneRequest body,
    required String etag,
  }) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/milestones/$id',
        data: body.toJson(),
        options: Options(headers: {'If-Match': etag}),
      );
      return Ok(Milestone.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> delete(
    String projectId,
    String id,
  ) async {
    try {
      await _api.dio.delete<dynamic>('$_base/$projectId/milestones/$id');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Milestone, AppFailure>> setCompleted(
    String projectId,
    String id, {
    required bool completed,
  }) async {
    final action = completed ? 'close' : 'reopen';
    final res = await _api.post('$_base/$projectId/milestones/$id/$action');
    return res.when(
      ok: (r) => Ok(Milestone.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<MilestoneStats, AppFailure>> stats(
    String projectId,
    String id,
  ) async {
    final res = await _api.get('$_base/$projectId/milestones/$id/stats');
    return res.when(
      ok: (r) => Ok(MilestoneStats.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<List<Epic>, AppFailure>> epics(
    String projectId,
    String milestoneId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/milestones/$milestoneId/epics',
    );
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
  Future<Result<Unit, AppFailure>> setEpics(
    String projectId,
    String milestoneId,
    List<String> epicIds,
  ) async {
    try {
      await _api.dio.put<dynamic>(
        '$_base/$projectId/milestones/$milestoneId/epics',
        data: {'epic_ids': epicIds},
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
