import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/mfa/data/dtos/mfa_dtos.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';

class FakeMfaRepository implements MfaRepository {
  FakeMfaRepository({
    this.startTotpHandler,
    this.confirmTotpHandler,
    this.disableTotpHandler,
    this.regenerateHandler,
    this.listPasskeysHandler,
    this.startPasskeyRegHandler,
    this.finishPasskeyRegHandler,
    this.deletePasskeyHandler,
    this.startPasskeyAuthHandler,
    this.finishPasskeyAuthHandler,
  });

  Future<Result<TotpStartResponse, AppFailure>> Function()? startTotpHandler;
  Future<Result<RecoveryCodesResponse, AppFailure>> Function(String code)?
  confirmTotpHandler;
  Future<Result<Unit, AppFailure>> Function()? disableTotpHandler;
  Future<Result<RecoveryCodesResponse, AppFailure>> Function()?
  regenerateHandler;
  Future<Result<List<PasskeyListItem>, AppFailure>> Function()?
  listPasskeysHandler;
  Future<Result<PasskeyCeremony, AppFailure>> Function()?
  startPasskeyRegHandler;
  Future<Result<Unit, AppFailure>> Function()? finishPasskeyRegHandler;
  Future<Result<Unit, AppFailure>> Function(String id)? deletePasskeyHandler;
  Future<Result<PasskeyCeremony, AppFailure>> Function(String email)?
  startPasskeyAuthHandler;
  Future<Result<TokenResponse, AppFailure>> Function()?
  finishPasskeyAuthHandler;

  int startTotpCalls = 0;
  int confirmTotpCalls = 0;
  int regenerateCalls = 0;

  @override
  Future<Result<TotpStartResponse, AppFailure>> startTotp() async {
    startTotpCalls++;
    return startTotpHandler?.call() ??
        Future.value(
          const Err<TotpStartResponse, AppFailure>(NetworkFailure()),
        );
  }

  @override
  Future<Result<RecoveryCodesResponse, AppFailure>> confirmTotp(
    String code,
  ) async {
    confirmTotpCalls++;
    return confirmTotpHandler?.call(code) ??
        Future.value(
          const Err<RecoveryCodesResponse, AppFailure>(NetworkFailure()),
        );
  }

  @override
  Future<Result<Unit, AppFailure>> disableTotp() async =>
      disableTotpHandler?.call() ??
      Future.value(const Ok<Unit, AppFailure>(Unit.instance));

  @override
  Future<Result<RecoveryCodesResponse, AppFailure>>
  regenerateRecoveryCodes() async {
    regenerateCalls++;
    return regenerateHandler?.call() ??
        Future.value(
          const Err<RecoveryCodesResponse, AppFailure>(NetworkFailure()),
        );
  }

  @override
  Future<Result<List<PasskeyListItem>, AppFailure>> listPasskeys() async =>
      listPasskeysHandler?.call() ??
      Future.value(const Ok<List<PasskeyListItem>, AppFailure>([]));

  @override
  Future<Result<PasskeyCeremony, AppFailure>>
  startPasskeyRegistration() async =>
      startPasskeyRegHandler?.call() ??
      Future.value(const Err<PasskeyCeremony, AppFailure>(NetworkFailure()));

  @override
  Future<Result<Unit, AppFailure>> finishPasskeyRegistration({
    required String stateId,
    required Map<String, dynamic> credential,
    String? nickname,
  }) async =>
      finishPasskeyRegHandler?.call() ??
      Future.value(const Ok<Unit, AppFailure>(Unit.instance));

  @override
  Future<Result<Unit, AppFailure>> deletePasskey(String id) async =>
      deletePasskeyHandler?.call(id) ??
      Future.value(const Ok<Unit, AppFailure>(Unit.instance));

  @override
  Future<Result<PasskeyCeremony, AppFailure>> startPasskeyAuthentication(
    String email,
  ) async =>
      startPasskeyAuthHandler?.call(email) ??
      Future.value(
        const Err<PasskeyCeremony, AppFailure>(UnauthorizedFailure()),
      );

  @override
  Future<Result<TokenResponse, AppFailure>> finishPasskeyAuthentication({
    required String stateId,
    required Map<String, dynamic> credential,
  }) async =>
      finishPasskeyAuthHandler?.call() ??
      Future.value(const Err<TokenResponse, AppFailure>(UnauthorizedFailure()));
}

class StubPasskeyService implements PasskeyService {
  StubPasskeyService({
    this.supported = true,
    this.registerResult,
    this.authResult,
    this.throwOnRegister = false,
    this.throwOnAuth = false,
  });
  bool supported;
  bool throwOnRegister;
  bool throwOnAuth;
  Map<String, dynamic>? registerResult;
  Map<String, dynamic>? authResult;

  @override
  bool get isSupported => supported;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> _) async {
    if (throwOnRegister) {
      throw PasskeyCeremonyError('user canceled');
    }
    return registerResult ?? const {'id': 'cred-1'};
  }

  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> _) async {
    if (throwOnAuth) {
      throw PasskeyCeremonyError('user canceled');
    }
    return authResult ?? const {'id': 'cred-1'};
  }
}
