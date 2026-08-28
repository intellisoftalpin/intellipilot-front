import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/app_token_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/security_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/sso_admin_dtos.dart';
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
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (q != null && q.isNotEmpty) params['q'] = q;
    if (status != null && status.isNotEmpty) params['status'] = status;
    final res = await _api.get('$_base/users', query: params);
    return _mapOk(
      res,
      (r) => AdminUserList.fromJson(r.data as Map<String, dynamic>),
    );
  }

  // ---- Account security (V018) ----

  @override
  Future<Result<TwoFactorResetResult, AppFailure>> resetTwoFactor(
    String id,
  ) async {
    final res = await _api.post('$_base/users/$id/reset-2fa');
    return _mapOk(
      res,
      (r) => TwoFactorResetResult.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<UserProfile, AppFailure>> banUser(
    String id, {
    String? reason,
  }) async {
    final res = await _api.post(
      '$_base/users/$id/ban',
      body: <String, dynamic>{
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return _mapOk(
      res,
      (r) => UserProfile.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<UserProfile, AppFailure>> unbanUser(String id) async {
    final res = await _api.post('$_base/users/$id/unban');
    return _mapOk(
      res,
      (r) => UserProfile.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<List<SessionInfo>, AppFailure>> listUserSessions(
    String id,
  ) async {
    final res = await _api.get('$_base/users/$id/sessions');
    return _mapOk(res, (r) {
      final body = r.data as Map<String, dynamic>;
      return (body['items'] as List<dynamic>? ?? const [])
          .map((e) => SessionInfo.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  @override
  Future<Result<int, AppFailure>> revokeUserSessions(String id) async {
    try {
      final r = await _api.dio.delete<dynamic>('$_base/users/$id/sessions');
      final body = r.data as Map<String, dynamic>?;
      return Ok((body?['sessions_revoked'] as num?)?.toInt() ?? 0);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  // ---- Geolocation (V018) ----

  @override
  Future<Result<GeoipStatus, AppFailure>> getGeoipStatus() async {
    final res = await _api.get('$_base/geoip');
    return _mapOk(
      res,
      (r) => GeoipStatus.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<GeoipStatus, AppFailure>> updateGeoipSettings({
    bool? enabled,
    String? variant,
    bool? autoUpdate,
  }) async {
    try {
      final r = await _api.dio.patch<dynamic>(
        '$_base/geoip',
        // Null fields are omitted so the server leaves them unchanged.
        data: <String, dynamic>{
          'enabled': ?enabled,
          'variant': ?variant,
          'auto_update': ?autoUpdate,
        },
      );
      return Ok(GeoipStatus.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<GeoipUpdateResult, AppFailure>> updateGeoipDatabase() async {
    final res = await _api.post('$_base/geoip/update');
    return _mapOk(
      res,
      (r) => GeoipUpdateResult.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<int, AppFailure>> purgeGeoipData() async {
    final res = await _api.post('$_base/geoip/purge');
    return _mapOk(res, (r) {
      final body = r.data as Map<String, dynamic>?;
      return (body?['sessions_cleared'] as num?)?.toInt() ?? 0;
    });
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
  Future<Result<PlatformSettings, AppFailure>> updateLoginPolicy({
    required bool openRegistration,
    required bool localPasswordLoginDisabled,
  }) async {
    try {
      final r = await _api.dio.patch<dynamic>(
        '$_base/settings',
        data: {
          'open_registration': openRegistration,
          'local_password_login_disabled': localPasswordLoginDisabled,
        },
      );
      return Ok(PlatformSettings.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  // ---- Single sign-on (OIDC) providers ----

  @override
  Future<Result<List<OidcProviderConfig>, AppFailure>>
  listOidcProviders() async {
    final res = await _api.get('$_base/oidc-providers');
    return _mapOk(
      res,
      (r) => (r.data as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(OidcProviderConfig.fromJson)
          .toList(),
    );
  }

  @override
  Future<Result<OidcProviderConfig, AppFailure>> createOidcProvider(
    UpsertOidcProviderRequest req,
  ) async {
    final res = await _api.post('$_base/oidc-providers', body: req.toJson());
    return _mapOk(
      res,
      (r) => OidcProviderConfig.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<OidcProviderConfig, AppFailure>> updateOidcProvider(
    String id,
    UpsertOidcProviderRequest req,
  ) async {
    try {
      final r = await _api.dio.put<dynamic>(
        '$_base/oidc-providers/$id',
        data: req.toJson(),
      );
      return Ok(OidcProviderConfig.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteOidcProvider(String id) async {
    try {
      await _api.dio.delete<dynamic>('$_base/oidc-providers/$id');
      return const Ok(Unit.instance);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<OidcTestResult, AppFailure>> testOidcProvider(
    String id,
  ) async {
    final res = await _api.post('$_base/oidc-providers/$id/test');
    return _mapOk(
      res,
      (r) => OidcTestResult.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<Unit, AppFailure>> setOidcLinkArmed(
    String userId,
    bool armed,
  ) async {
    final path = '$_base/users/$userId/oidc-link-arm';
    if (armed) {
      final res = await _api.post(path);
      return res.when(
        ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
        err: Err.new,
      );
    }
    try {
      await _api.dio.delete<dynamic>(path);
      return const Ok(Unit.instance);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
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

  // ---- App tokens (V004) ----

  @override
  Future<Result<List<AppTokenDto>, AppFailure>> listAppTokens() async {
    final res = await _api.get('$_base/app-tokens');
    return _mapOk(
      res,
      (r) => ((r.data as List<dynamic>?) ?? const [])
          .map((e) => AppTokenDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<CreateAppTokenResult, AppFailure>> createAppToken(
    CreateAppTokenRequest body,
  ) async {
    final res = await _api.post('$_base/app-tokens', body: body.toJson());
    return _mapOk(
      res,
      (r) => CreateAppTokenResult.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<AppTokenDto, AppFailure>> updateAppToken(
    String id,
    UpdateAppTokenRequest body,
  ) async {
    try {
      final r = await _api.dio.patch<dynamic>(
        '$_base/app-tokens/$id',
        data: body.toJson(),
      );
      return Ok(AppTokenDto.fromJson(r.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    } on Object catch (e) {
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> revokeAppToken(String id) async {
    final res = await _api.post('$_base/app-tokens/$id/revoke');
    return res.when(
      ok: (_) => const Ok(Unit.instance),
      err: Err.new,
    );
  }

  @override
  Future<Result<ShortLinkHistory, AppFailure>> shortLinkHistory() async {
    final res = await _api.get('$_base/short-link-history');
    return _mapOk(
      res,
      (r) => ShortLinkHistory.fromJson(r.data as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<Unit, AppFailure>> deleteShortLinkHistory({
    List<String> projectIds = const [],
    List<String> boardIds = const [],
  }) async {
    final res = await _api.post(
      '$_base/short-link-history/delete',
      body: {'project_ids': projectIds, 'board_ids': boardIds},
    );
    return res.when(
      ok: (_) => const Ok(Unit.instance),
      err: Err.new,
    );
  }
}
