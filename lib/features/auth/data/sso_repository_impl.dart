import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/data/dtos/sso_dtos.dart';
import 'package:intellipilot/features/auth/domain/sso_repository.dart';

const _authBase = '/api/v1/auth/oidc';
const _meBase = '/api/v1/me/oidc';

class SsoRepositoryImpl implements SsoRepository {
  SsoRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<Result<SsoDeviceStart, AppFailure>> startDeviceSignIn(String slug) =>
      _startDevice('$_authBase/$slug/device/start');

  @override
  Future<Result<SsoDeviceStart, AppFailure>> startDeviceLink(String slug) =>
      _startDevice('$_meBase/$slug/device/link/start');

  Future<Result<SsoDeviceStart, AppFailure>> _startDevice(String path) async {
    final res = await _api.post(path);
    return res.when(
      ok: (r) {
        final data = r.data;
        if (data is Map<String, dynamic>) {
          return Ok(SsoDeviceStart.fromJson(data));
        }
        return const Err(
          UnknownFailure(cause: 'sso device start: unexpected body shape'),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<SsoDevicePoll, AppFailure>> pollDevice(String pollToken) async {
    // 202 is "still waiting" and 204 is "linked" — both are successes with a
    // meaning the body alone does not carry, so the status code is read here
    // rather than inferred from the payload.
    final res = await _api.post(
      '$_authBase/device/poll',
      body: {'poll_token': pollToken},
    );
    return res.when(
      ok: (r) {
        if (r.statusCode == 202) return const Ok(SsoDevicePending());
        if (r.statusCode == 204) return const Ok(SsoDeviceLinked());
        final data = r.data;
        if (data is Map<String, dynamic> && data['access_token'] != null) {
          return Ok(SsoDeviceSignedIn(TokenResponse.fromJson(data)));
        }
        return const Err(
          UnknownFailure(cause: 'sso device poll: unexpected body shape'),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<List<SsoIdentity>, AppFailure>> listIdentities() async {
    final res = await _api.get('$_meBase/identities');
    return res.when(
      ok: (r) {
        final data = r.data;
        if (data is List) {
          return Ok(
            data
                .whereType<Map<String, dynamic>>()
                .map(SsoIdentity.fromJson)
                .toList(),
          );
        }
        return const Err(
          UnknownFailure(cause: 'sso identities: unexpected body shape'),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> unlinkIdentity(String id) async {
    try {
      await _api.dio.delete<dynamic>('$_meBase/identities/$id');
      return const Ok(Unit.instance);
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
