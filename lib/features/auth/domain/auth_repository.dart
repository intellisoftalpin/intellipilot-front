import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';

/// Domain contract for the auth endpoints. The bloc/cubit layer talks only to
/// this interface; the data implementation owns the wire shape.
abstract interface class AuthRepository {
  Future<Result<LoginResult, AppFailure>> login({
    required String email,
    required String password,
  });

  Future<Result<Unit, AppFailure>> register({
    required String email,
    required String username,
    required String password,
    required String fullName,
  });

  Future<Result<TokenResponse, AppFailure>> refresh();

  Future<Result<Unit, AppFailure>> logout();

  Future<Result<PasswordResetRequestResponse, AppFailure>> requestPasswordReset(
    String email,
  );

  Future<Result<Unit, AppFailure>> confirmPasswordReset({
    required String token,
    required String newPassword,
  });

  Future<Result<TokenResponse, AppFailure>> verifyMfa({
    required String mfaToken,
    required String method,
    required String code,
  });
}
