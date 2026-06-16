import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

const _basePath = '/api/v1/auth';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<Result<AuthConfig, AppFailure>> authConfig() async {
    final res = await _api.get('$_basePath/config');
    return res.when(
      ok: (r) {
        try {
          return Ok(AuthConfig.fromJson(r.data as Map<String, dynamic>));
        } on Object catch (e) {
          return Err(UnknownFailure(cause: e));
        }
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<LoginResult, AppFailure>> login({
    required String email,
    required String password,
  }) async {
    final res = await _api.post(
      '$_basePath/login',
      body: LoginRequest(email: email, password: password).toJson(),
    );
    return res.when(
      ok: (response) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          if (data['mfa_required'] == true) {
            return Ok(LoginMfaRequired.fromJson(data));
          }
          return Ok(LoginTokens(TokenResponse.fromJson(data)));
        }
        return const Err(UnknownFailure(cause: 'login: unexpected body shape'));
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> register({
    required String email,
    required String username,
    required String password,
    required String fullName,
    String? invitationToken,
  }) async {
    final res = await _api.post(
      '$_basePath/register',
      body: RegisterRequest(
        email: email,
        username: username,
        password: password,
        fullName: fullName,
        invitationToken: invitationToken,
      ).toJson(),
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  @override
  Future<Result<TokenResponse, AppFailure>> refresh() async {
    final res = await _api.post('$_basePath/refresh');
    return res.when(
      ok: (response) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return Ok(TokenResponse.fromJson(data));
        }
        return const Err(
          UnknownFailure(cause: 'refresh: unexpected body shape'),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> logout() async {
    try {
      await _api.dio.post<dynamic>('$_basePath/logout');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<PasswordResetRequestResponse, AppFailure>> requestPasswordReset(
    String email,
  ) async {
    final res = await _api.post(
      '$_basePath/password/reset/request',
      body: PasswordResetRequestBody(email: email).toJson(),
    );
    return res.when(
      ok: (response) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return Ok(PasswordResetRequestResponse.fromJson(data));
        }
        return const Ok(PasswordResetRequestResponse(status: 'ok'));
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    final res = await _api.post(
      '$_basePath/password/reset/confirm',
      body: PasswordResetConfirmBody(
        token: token,
        newPassword: newPassword,
      ).toJson(),
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  @override
  Future<Result<TokenResponse, AppFailure>> verifyMfa({
    required String mfaToken,
    required String method,
    required String code,
  }) async {
    final res = await _api.post(
      '$_basePath/2fa/verify',
      body: TwoFactorVerifyRequest(
        mfaToken: mfaToken,
        method: method,
        code: code,
      ).toJson(),
    );
    return res.when(
      ok: (response) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return Ok(TokenResponse.fromJson(data));
        }
        return const Err(UnknownFailure(cause: '2fa: unexpected body shape'));
      },
      err: Err.new,
    );
  }
}
