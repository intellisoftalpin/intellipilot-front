import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/mfa/data/dtos/mfa_dtos.dart';

/// Domain contract for TOTP / recovery / passkey endpoints. The MFA verify
/// step itself lives on [AuthRepository] since it's part of the password flow.
abstract interface class MfaRepository {
  // --- TOTP -----------------------------------------------------------
  Future<Result<TotpStartResponse, AppFailure>> startTotp();

  /// Confirm the 6-digit code; backend activates TOTP and returns the initial
  /// set of recovery codes.
  Future<Result<RecoveryCodesResponse, AppFailure>> confirmTotp(String code);

  Future<Result<Unit, AppFailure>> disableTotp();

  // --- Recovery codes -------------------------------------------------
  Future<Result<RecoveryCodesResponse, AppFailure>> regenerateRecoveryCodes();

  // --- Passkeys (authenticated) ---------------------------------------
  Future<Result<List<PasskeyListItem>, AppFailure>> listPasskeys();
  Future<Result<PasskeyCeremony, AppFailure>> startPasskeyRegistration();
  Future<Result<Unit, AppFailure>> finishPasskeyRegistration({
    required String stateId,
    required Map<String, dynamic> credential,
    String? nickname,
  });
  Future<Result<Unit, AppFailure>> deletePasskey(String id);

  // --- Passwordless sign-in -------------------------------------------
  Future<Result<PasskeyCeremony, AppFailure>> startPasskeyAuthentication(
    String email,
  );
  Future<Result<TokenResponse, AppFailure>> finishPasskeyAuthentication({
    required String stateId,
    required Map<String, dynamic> credential,
  });
}
