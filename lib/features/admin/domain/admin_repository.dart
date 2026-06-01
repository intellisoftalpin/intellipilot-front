import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';

/// Domain contract for `/api/v1/admin/*` (V011 — platform admin).
abstract interface class AdminRepository {
  Future<Result<AdminUserList, AppFailure>> listUsers({
    String? q,
    int limit = 50,
    int offset = 0,
  });

  Future<Result<CreateUserResponse, AppFailure>> createUser(
    CreateUserRequest body,
  );

  Future<Result<UserProfile, AppFailure>> updateUser(
    String id,
    UpdateUserRequest patch,
  );

  Future<Result<Unit, AppFailure>> deleteUser(String id);

  Future<Result<PasswordResetIssued, AppFailure>> resetPassword(String id);

  Future<Result<CreateInvitationResponse, AppFailure>> createInvitation(
    CreateInvitationRequest body,
  );

  Future<Result<List<PendingInvitation>, AppFailure>> listInvitations();

  Future<Result<Unit, AppFailure>> revokeInvitation(String id);

  Future<Result<PlatformSettings, AppFailure>> getSettings();

  Future<Result<PlatformSettings, AppFailure>> updateOpenRegistration(
    bool value,
  );
}
