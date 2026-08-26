import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';

/// Domain contract for the auth endpoints. The bloc/cubit layer talks only to
/// this interface; the data implementation owns the wire shape.
abstract interface class AuthRepository {
  /// Public config (no auth): whether self-service registration is open and
  /// whether email password reset is available. Drives unauthenticated UI.
  Future<Result<AuthConfig, AppFailure>> authConfig();

  Future<Result<LoginResult, AppFailure>> login({
    required String email,
    required String password,
  });

  Future<Result<Unit, AppFailure>> register({
    required String email,
    required String username,
    required String password,
    required String fullName,
    String? invitationToken,
  });

  /// Rotate the session.
  ///
  /// [refreshToken] is for clients with no cookie jar of their own to share —
  /// desktop and mobile hold several accounts at once, so each must present its
  /// own token. Web passes null and the HttpOnly cookie is used, exactly as
  /// before. The server reads the cookie first regardless.
  Future<Result<TokenResponse, AppFailure>> refresh({String? refreshToken});

  /// Revoke the session. [refreshToken] as per [refresh].
  Future<Result<Unit, AppFailure>> logout({String? refreshToken});

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
