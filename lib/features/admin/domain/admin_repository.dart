import 'dart:typed_data';

import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/app_token_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/security_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/sso_admin_dtos.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';

/// Domain contract for `/api/v1/admin/*` (V011 — platform admin).
abstract interface class AdminRepository {
  /// [status] filters the list: `active`, `inactive`, `banned` or `no_2fa`.
  /// Null means all.
  Future<Result<AdminUserList, AppFailure>> listUsers({
    String? q,
    String? status,
    int limit = 50,
    int offset = 0,
  });

  // ---- Account security (V018) ----

  /// Clears every second factor — TOTP, passkeys and recovery codes — and
  /// signs the user out everywhere.
  ///
  /// The recovery path for a user who lost their authenticator: clearing only
  /// TOTP would leave a passkey-only account just as locked out.
  Future<Result<TwoFactorResetResult, AppFailure>> resetTwoFactor(String id);

  /// Locks an account out. Distinct from deactivation, which an LDAP login
  /// silently undoes.
  Future<Result<UserProfile, AppFailure>> banUser(String id, {String? reason});

  Future<Result<UserProfile, AppFailure>> unbanUser(String id);

  Future<Result<List<SessionInfo>, AppFailure>> listUserSessions(String id);

  /// Signs the user out of every session. Returns how many were closed.
  Future<Result<int, AppFailure>> revokeUserSessions(String id);

  // ---- Geolocation (V018) ----

  Future<Result<GeoipStatus, AppFailure>> getGeoipStatus();

  Future<Result<GeoipStatus, AppFailure>> updateGeoipSettings({
    bool? enabled,
    String? variant,
    bool? autoUpdate,
  });

  /// Downloads the newest published database now, rather than waiting for the
  /// monthly refresh.
  Future<Result<GeoipUpdateResult, AppFailure>> updateGeoipDatabase();

  /// Erases stored session locations. Returns the number of sessions cleared.
  Future<Result<int, AppFailure>> purgeGeoipData();

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

  /// Switch the local password form on or off (V025).
  ///
  /// [openRegistration] must be passed through because the endpoint takes the
  /// whole settings object; omitting the SSO switch is what lets an older
  /// client patch open registration without touching it.
  Future<Result<PlatformSettings, AppFailure>> updateLoginPolicy({
    required bool openRegistration,
    required bool localPasswordLoginDisabled,
  });

  // ---- Single sign-on (OIDC) providers ----

  Future<Result<List<OidcProviderConfig>, AppFailure>> listOidcProviders();

  Future<Result<OidcProviderConfig, AppFailure>> createOidcProvider(
    UpsertOidcProviderRequest req,
  );

  Future<Result<OidcProviderConfig, AppFailure>> updateOidcProvider(
    String id,
    UpsertOidcProviderRequest req,
  );

  Future<Result<Unit, AppFailure>> deleteOidcProvider(String id);

  /// Fetch the provider's discovery document and report what it publishes.
  Future<Result<OidcTestResult, AppFailure>> testOidcProvider(String id);

  /// Open or close the one-shot window in which a user's next SSO sign-in may
  /// link to their existing account by verified email. The rescue route for
  /// someone who can no longer sign in to use the self-service option.
  Future<Result<Unit, AppFailure>> setOidcLinkArmed(String userId, bool armed);

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

  // ---- App tokens (V004) ----
  Future<Result<List<AppTokenDto>, AppFailure>> listAppTokens();

  /// Creates a token; the raw secret in the result is delivered only once.
  Future<Result<CreateAppTokenResult, AppFailure>> createAppToken(
    CreateAppTokenRequest body,
  );

  Future<Result<AppTokenDto, AppFailure>> updateAppToken(
    String id,
    UpdateAppTokenRequest body,
  );

  Future<Result<Unit, AppFailure>> revokeAppToken(String id);

  /// All remembered renamed-away project prefixes and board keys (the
  /// short-link redirect history).
  Future<Result<ShortLinkHistory, AppFailure>> shortLinkHistory();

  /// Prune history entries (single or bulk): the matching old short links
  /// stop resolving; UUID links are unaffected.
  Future<Result<Unit, AppFailure>> deleteShortLinkHistory({
    List<String> projectIds,
    List<String> boardIds,
  });
}
