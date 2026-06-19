import 'dart:typed_data';

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

  /// Maps a successful response body, converting ANY parse error (e.g. a
  /// malformed/non-RFC3339 date the DTO can't decode) into an [AppFailure]
  /// instead of letting it throw. A throw here would propagate out of the
  /// awaiting cubit and leave its loading state stuck forever (infinite
  /// spinner) rather than surfacing an error to the user.
  Result<T, AppFailure> _mapOk<T>(
    Result<Response<dynamic>, AppFailure> res,
    T Function(Response<dynamic> r) parse,
  ) => res.when(
    ok: (r) {
      try {
        return Ok(parse(r));
      } on Object catch (e) {
        return Err(UnknownFailure(cause: e));
      }
    },
    err: Err.new,
  );

  @override
  Future<Result<AdminUserList, AppFailure>> listUsers({
    String? q,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (q != null && q.isNotEmpty) params['q'] = q;
    final res = await _api.get('$_base/users', query: params);
    return _mapOk(
      res,
      (r) => AdminUserList.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<ActivityList, AppFailure>> listActivity({
    String? action,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (action != null && action.isNotEmpty) params['action'] = action;
    final res = await _api.get('$_base/activity', query: params);
    return _mapOk(
      res,
      (r) => ActivityList.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<CreateUserResponse, AppFailure>> createUser(
    CreateUserRequest body,
  ) async {
    final res = await _api.post('$_base/users', body: body.toJson());
    return _mapOk(
      res,
      (r) => CreateUserResponse.fromJson(r.data as Map<String, dynamic>),
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
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
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
    return _mapOk(
      res,
      (r) => PasswordResetIssued.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<CreateInvitationResponse, AppFailure>> createInvitation(
    CreateInvitationRequest body,
  ) async {
    final res = await _api.post('$_base/invitations', body: body.toJson());
    return _mapOk(
      res,
      (r) => CreateInvitationResponse.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<List<PendingInvitation>, AppFailure>> listInvitations() async {
    final res = await _api.get('$_base/invitations');
    return _mapOk(
      res,
      (r) => (r.data as List<dynamic>? ?? const [])
          .map((e) => PendingInvitation.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
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
    return _mapOk(
      res,
      (r) => PlatformSettings.fromJson(r.data as Map<String, dynamic>),
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
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> updateBranding({
    String? appName,
    String? appMessage,
  }) async {
    try {
      final r = await _api.dio.patch<dynamic>(
        '$_base/branding',
        data: {'app_name': appName, 'app_message': appMessage},
      );
      return Ok(PlatformSettings.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> uploadBrandingIcon({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: contentType == null
              ? null
              : DioMediaType.parse(contentType),
        ),
      });
      final r = await _api.dio.put<dynamic>(
        '$_base/branding/icon',
        data: form,
        // Let dio compute the multipart boundary; otherwise ApiClient's default
        // application/json header would clobber it.
        options: Options(contentType: 'multipart/form-data'),
      );
      return Ok(PlatformSettings.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> deleteBrandingIcon() async {
    try {
      final r = await _api.dio.delete<dynamic>('$_base/branding/icon');
      return Ok(PlatformSettings.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<LdapSettings, AppFailure>> getLdapSettings() async {
    final res = await _api.get('$_base/ldap-settings');
    return _mapOk(
      res,
      (r) => LdapSettings.fromJson(r.data as Map<String, dynamic>),
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
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
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
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  static const _notif = '$_base/notification-settings';

  @override
  Future<Result<NotificationSettings, AppFailure>>
  getNotificationSettings() async {
    final res = await _api.get(_notif);
    return _mapOk(
      res,
      (r) => NotificationSettings.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<NotificationSettings, AppFailure>> updateNotificationSettings(
    NotificationSettingsUpdate req,
  ) async {
    try {
      final r = await _api.dio.put<dynamic>(_notif, data: req.toJson());
      return Ok(NotificationSettings.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<NotificationTestResult, AppFailure>> testNotification({
    required String channel,
    String? to,
  }) async {
    try {
      final r = await _api.dio.post<dynamic>(
        '$_notif/test-$channel',
        data: channel == 'mail' ? {'to': to ?? ''} : null,
      );
      return Ok(
        NotificationTestResult.fromJson(r.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }
}
