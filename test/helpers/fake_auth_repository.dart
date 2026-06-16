import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

/// Configurable in-memory [AuthRepository] for tests. Default behavior makes
/// every method return [UnauthorizedFailure] so tests must opt-in to success
/// paths explicitly — keeps assumptions visible.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.loginHandler,
    this.registerHandler,
    this.refreshHandler,
    this.logoutHandler,
    this.requestResetHandler,
    this.confirmResetHandler,
    this.verifyMfaHandler,
    this.authConfigHandler,
  });

  Future<Result<AuthConfig, AppFailure>> Function()? authConfigHandler;

  Future<Result<LoginResult, AppFailure>> Function(String email, String pw)?
  loginHandler;
  Future<Result<Unit, AppFailure>> Function()? registerHandler;
  Future<Result<TokenResponse, AppFailure>> Function()? refreshHandler;
  Future<Result<Unit, AppFailure>> Function()? logoutHandler;
  Future<Result<PasswordResetRequestResponse, AppFailure>> Function(
    String email,
  )?
  requestResetHandler;
  Future<Result<Unit, AppFailure>> Function()? confirmResetHandler;
  Future<Result<TokenResponse, AppFailure>> Function()? verifyMfaHandler;

  int loginCalls = 0;
  int refreshCalls = 0;
  int logoutCalls = 0;

  @override
  Future<Result<AuthConfig, AppFailure>> authConfig() async =>
      authConfigHandler?.call() ??
      Future.value(
        const Ok<AuthConfig, AppFailure>(
          AuthConfig(openRegistration: true, passwordResetEnabled: true),
        ),
      );

  @override
  Future<Result<LoginResult, AppFailure>> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    return loginHandler?.call(email, password) ??
        Future.value(const Err<LoginResult, AppFailure>(UnauthorizedFailure()));
  }

  @override
  Future<Result<Unit, AppFailure>> register({
    required String email,
    required String username,
    required String password,
    required String fullName,
    String? invitationToken,
  }) async =>
      registerHandler?.call() ??
      Future.value(const Err<Unit, AppFailure>(UnknownFailure()));

  @override
  Future<Result<TokenResponse, AppFailure>> refresh() async {
    refreshCalls++;
    return refreshHandler?.call() ??
        Future.value(
          const Err<TokenResponse, AppFailure>(UnauthorizedFailure()),
        );
  }

  @override
  Future<Result<Unit, AppFailure>> logout() async {
    logoutCalls++;
    return logoutHandler?.call() ??
        Future.value(const Ok<Unit, AppFailure>(Unit.instance));
  }

  @override
  Future<Result<PasswordResetRequestResponse, AppFailure>> requestPasswordReset(
    String email,
  ) async =>
      requestResetHandler?.call(email) ??
      Future.value(
        const Ok<PasswordResetRequestResponse, AppFailure>(
          PasswordResetRequestResponse(status: 'ok'),
        ),
      );

  @override
  Future<Result<Unit, AppFailure>> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async =>
      confirmResetHandler?.call() ??
      Future.value(const Ok<Unit, AppFailure>(Unit.instance));

  @override
  Future<Result<TokenResponse, AppFailure>> verifyMfa({
    required String mfaToken,
    required String method,
    required String code,
  }) async =>
      verifyMfaHandler?.call() ??
      Future.value(const Err<TokenResponse, AppFailure>(UnauthorizedFailure()));
}
