import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

const _basePath = '/api/v1/projects';
const _acceptPath = '/api/v1/invitations/accept';

class ProjectsRepositoryImpl implements ProjectsRepository {
  ProjectsRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<List<Project>, AppFailure>> listProjects() async {
    final res = await _api.get(_basePath);
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['projects'] as List<dynamic>? ?? const [])
            .map((e) => Project.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Project, AppFailure>> getProject(String id) async {
    final res = await _api.get('$_basePath/$id');
    return res.when(
      ok: (r) => Ok(Project.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Project, AppFailure>> createProject(
    CreateProjectRequest body,
  ) async {
    final res = await _api.post(_basePath, body: body.toJson());
    return res.when(
      ok: (r) => Ok(Project.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Project, AppFailure>> updateProject(
    String id,
    UpdateProjectRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_basePath/$id',
        data: body.toJson(),
      );
      return Ok(Project.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteProject(String id) async {
    try {
      await _api.dio.delete<dynamic>('$_basePath/$id');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<List<Role>, AppFailure>> listRoles(String projectId) async {
    final res = await _api.get('$_basePath/$projectId/roles');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['roles'] as List<dynamic>? ?? const [])
            .map((e) => Role.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Role, AppFailure>> createRole(
    String projectId,
    CreateRoleRequest body,
  ) async {
    final res = await _api.post(
      '$_basePath/$projectId/roles',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(Role.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Role, AppFailure>> updateRole(
    String projectId,
    String roleId,
    UpdateRoleRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_basePath/$projectId/roles/$roleId',
        data: body.toJson(),
      );
      return Ok(Role.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteRole(
    String projectId,
    String roleId,
  ) async {
    try {
      await _api.dio.delete<dynamic>('$_basePath/$projectId/roles/$roleId');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<List<Membership>, AppFailure>> listMembers(
    String projectId,
  ) async {
    final res = await _api.get('$_basePath/$projectId/members');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['members'] as List<dynamic>? ?? const [])
            .map((e) => Membership.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> changeMemberRole(
    String projectId,
    String userId,
    String roleSlug,
  ) async {
    try {
      await _api.dio.patch<dynamic>(
        '$_basePath/$projectId/members/$userId',
        data: ChangeMemberRoleRequest(roleSlug).toJson(),
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> addMember(
    String projectId, {
    required String roleSlug,
    String? userId,
    String? identifier,
  }) async {
    try {
      await _api.dio.post<dynamic>(
        '$_basePath/$projectId/members',
        data: {
          if (userId != null) 'user_id': userId,
          if (identifier != null) 'identifier': identifier,
          'role': roleSlug,
        },
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> removeMember(
    String projectId,
    String userId,
  ) async {
    try {
      await _api.dio.delete<dynamic>('$_basePath/$projectId/members/$userId');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<List<Invitation>, AppFailure>> listInvitations(
    String projectId,
  ) async {
    final res = await _api.get('$_basePath/$projectId/invitations');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final list = (body['invitations'] as List<dynamic>? ?? const [])
            .map((e) => Invitation.fromJson(e as Map<String, dynamic>))
            .toList();
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<InviteResponse, AppFailure>> invite(
    String projectId,
    InviteRequest body,
  ) async {
    final res = await _api.post(
      '$_basePath/$projectId/invitations',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(InviteResponse.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<String, AppFailure>> acceptInvitation(String token) async {
    final res = await _api.post(_acceptPath, body: {'token': token});
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        return Ok(body['project_id'] as String);
      },
      err: Err.new,
    );
  }
}
