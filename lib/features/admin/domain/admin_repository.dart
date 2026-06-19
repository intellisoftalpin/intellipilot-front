import 'dart:typed_data';

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

  /// Superadmin-only audit feed. `action` filters by event type when set.
  Future<Result<ActivityList, AppFailure>> listActivity({
    String? action,
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

  // ---- White-label branding ----

  /// Sets the custom name and/or login message. Pass `null` (or an empty
  /// string) for a field to clear it and revert to the bundled default.
  Future<Result<PlatformSettings, AppFailure>> updateBranding({
    String? appName,
    String? appMessage,
  });

  /// Uploads a custom app icon (an image). Replaces any existing one.
  Future<Result<PlatformSettings, AppFailure>> uploadBrandingIcon({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  });

  /// Removes the custom app icon, reverting to the bundled default.
  Future<Result<PlatformSettings, AppFailure>> deleteBrandingIcon();

  // ---- LDAP ----
  Future<Result<LdapSettings, AppFailure>> getLdapSettings();

  Future<Result<LdapSettings, AppFailure>> updateLdapSettings(
    UpdateLdapSettingsRequest req,
  );

  /// Attempt a real bind with the given (possibly unsaved) settings + creds.
  Future<Result<LdapTestResult, AppFailure>> testLdapSettings({
    required UpdateLdapSettingsRequest settings,
    required String username,
    required String password,
  });

  Future<Result<NotificationSettings, AppFailure>> getNotificationSettings();

  Future<Result<NotificationSettings, AppFailure>> updateNotificationSettings(
    NotificationSettingsUpdate req,
  );

  /// Send a test message over a channel using the saved configuration.
  /// `channel` is one of `mail` | `matrix` | `telegram`; `to` is the recipient
  /// for the mail channel (ignored otherwise).
  Future<Result<NotificationTestResult, AppFailure>> testNotification({
    required String channel,
    String? to,
  });
}
