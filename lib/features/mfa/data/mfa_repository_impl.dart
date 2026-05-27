import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/mfa/data/dtos/mfa_dtos.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';

const _me = '/api/v1/me';
const _auth = '/api/v1/auth';

class MfaRepositoryImpl implements MfaRepository {
  MfaRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<TotpStartResponse, AppFailure>> startTotp() async {
    final res = await _api.post('$_me/totp/start');
    return res.when(
      ok: (r) => Ok(TotpStartResponse.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<RecoveryCodesResponse, AppFailure>> confirmTotp(
    String code,
  ) async {
    final res = await _api.post(
      '$_me/totp/confirm',
      body: {'code': code},
    );
    return res.when(
      ok: (r) =>
          Ok(RecoveryCodesResponse.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> disableTotp() async {
    try {
      await _api.dio.delete<dynamic>('$_me/totp');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<RecoveryCodesResponse, AppFailure>>
  regenerateRecoveryCodes() async {
    final res = await _api.post('$_me/recovery-codes/regenerate');
    return res.when(
      ok: (r) =>
          Ok(RecoveryCodesResponse.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<List<PasskeyListItem>, AppFailure>> listPasskeys() async {
    final res = await _api.get('$_me/passkeys');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['passkeys'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => PasskeyListItem.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<PasskeyCeremony, AppFailure>> startPasskeyRegistration() async {
    final res = await _api.post('$_me/passkeys/register/start');
    return res.when(
      ok: (r) => Ok(
        PasskeyCeremony.fromJson(
          r.data as Map<String, dynamic>,
          'creation_options',
        ),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> finishPasskeyRegistration({
    required String stateId,
    required Map<String, dynamic> credential,
    String? nickname,
  }) async {
    final res = await _api.post(
      '$_me/passkeys/register/finish',
      body: {
        'state_id': stateId,
        'credential': credential,
        if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
      },
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> deletePasskey(String id) async {
    try {
      await _api.dio.delete<dynamic>('$_me/passkeys/$id');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      if (e.response?.statusCode == 404) {
        return Err(NotFoundFailure(cause: e));
      }
      return Err(UnknownFailure(cause: e));
    }
  }

  @override
  Future<Result<PasskeyCeremony, AppFailure>> startPasskeyAuthentication(
    String email,
  ) async {
    final res = await _api.post(
      '$_auth/passkeys/authenticate/start',
      body: {'email': email},
    );
    return res.when(
      ok: (r) => Ok(
        PasskeyCeremony.fromJson(
          r.data as Map<String, dynamic>,
          'request_options',
        ),
      ),
      err: Err.new,
    );
  }

  @override
  Future<Result<TokenResponse, AppFailure>> finishPasskeyAuthentication({
    required String stateId,
    required Map<String, dynamic> credential,
  }) async {
    final res = await _api.post(
      '$_auth/passkeys/authenticate/finish',
      body: {'state_id': stateId, 'credential': credential},
    );
    return res.when(
      ok: (r) => Ok(TokenResponse.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }
}
