import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';

const _base = '/api/v1/admin';

class AdminRepositoryImpl implements AdminRepository {
  AdminRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<AdminUserList, AppFailure>> listUsers({
    String? q,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (q != null && q.isNotEmpty) params['q'] = q;
    final res = await _api.get('$_base/users', query: params);
    return res.when(
      ok: (r) => Ok(AdminUserList.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<CreateUserResponse, AppFailure>> createUser(
    CreateUserRequest body,
  ) async {
    final res = await _api.post('$_base/users', body: body.toJson());
    return res.when(
      ok: (r) =>
          Ok(CreateUserResponse.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<UserProfile, AppFailure>> updateUser(
    String id,
    UpdateUserRequest patch,
  ) async {
    try {
      final r = await _api.dio.patch<dynamic>(
        '$_base/users/$id',
        data: patch.toJson(),
      );
      return Ok(UserProfile.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteUser(String id) async {
    try {
      await _api.dio.delete<dynamic>('$_base/users/$id');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<PasswordResetIssued, AppFailure>> resetPassword(
    String id,
  ) async {
    final res = await _api.post('$_base/users/$id/reset-password');
    return res.when(
      ok: (r) =>
          Ok(PasswordResetIssued.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<CreateInvitationResponse, AppFailure>> createInvitation(
    CreateInvitationRequest body,
  ) async {
    final res = await _api.post('$_base/invitations', body: body.toJson());
    return res.when(
      ok: (r) => Ok(
        CreateInvitationResponse.fromJson(r.data as Map<String, dynamic>),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<List<PendingInvitation>, AppFailure>> listInvitations() async {
    final res = await _api.get('$_base/invitations');
    return res.when(
      ok: (r) {
        final list = (r.data as List<dynamic>? ?? const [])
            .map((e) => PendingInvitation.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
        return Ok(list);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> revokeInvitation(String id) async {
    try {
      await _api.dio.delete<dynamic>('$_base/invitations/$id');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> getSettings() async {
    final res = await _api.get('$_base/settings');
    return res.when(
      ok: (r) => Ok(PlatformSettings.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> updateOpenRegistration(
    bool value,
  ) async {
    try {
      final r = await _api.dio.patch<dynamic>(
        '$_base/settings',
        data: {'open_registration': value},
      );
      return Ok(PlatformSettings.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<LdapSettings, AppFailure>> getLdapSettings() async {
    final res = await _api.get('$_base/ldap-settings');
    return res.when(
      ok: (r) => Ok(LdapSettings.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<LdapSettings, AppFailure>> updateLdapSettings(
    UpdateLdapSettingsRequest req,
  ) async {
    try {
      final r = await _api.dio.put<dynamic>(
        '$_base/ldap-settings',
        data: req.toJson(),
      );
      return Ok(LdapSettings.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<LdapTestResult, AppFailure>> testLdapSettings({
    required UpdateLdapSettingsRequest settings,
    required String username,
    required String password,
  }) async {
    try {
      final r = await _api.dio.post<dynamic>(
        '$_base/ldap-settings/test',
        data: {
          'settings': settings.toJson(),
          'username': username,
          'password': password,
        },
      );
      return Ok(LdapTestResult.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
