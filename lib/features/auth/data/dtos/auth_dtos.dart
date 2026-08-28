import 'package:intellipilot/features/auth/data/dtos/sso_dtos.dart';

/// JSON DTOs for the auth endpoints. Hand-written rather than freezed/json:
/// the surface is small and changes touch the API contract, so a single edit
/// site is preferable to a codegen step here.
class RegisterRequest {
  const RegisterRequest({
    required this.email,
    required this.username,
    required this.password,
    this.fullName = '',
    this.invitationToken,
  });

  final String email;
  final String username;
  final String password;
  final String fullName;

  /// Platform-invitation token (V011). Required by the server when
  /// `open_registration=false`; ignored otherwise.
  final String? invitationToken;

  Map<String, dynamic> toJson() => {
    'email': email,
    'username': username,
    'password': password,
    'full_name': fullName,
    if (invitationToken != null && invitationToken!.isNotEmpty)
      'invitation_token': invitationToken,
  };
}

class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

class PasswordResetRequestBody {
  const PasswordResetRequestBody({required this.email});

  final String email;

  Map<String, dynamic> toJson() => {'email': email};
}

class PasswordResetRequestResponse {
  const PasswordResetRequestResponse({required this.status, this.resetToken});

  factory PasswordResetRequestResponse.fromJson(Map<String, dynamic> json) {
    return PasswordResetRequestResponse(
      status: json['status'] as String? ?? 'ok',
      resetToken: json['reset_token'] as String?,
    );
  }

  final String status;
  final String? resetToken;
}

class PasswordResetConfirmBody {
  const PasswordResetConfirmBody({
    required this.token,
    required this.newPassword,
  });

  final String token;
  final String newPassword;

  Map<String, dynamic> toJson() => {
    'token': token,
    'new_password': newPassword,
  };
}

/// Server response on a successful credential check (login / refresh / 2fa).
class TokenResponse {
  const TokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.refreshToken,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: (json['expires_in'] as num).toInt(),
      refreshToken: json['refresh_token'] as String?,
    );
  }

  final String accessToken;
  final String tokenType;

  /// Lifetime of the access token in seconds (server-issued).
  final int expiresIn;

  /// Dev-only refresh-token leak from the backend in non-production envs.
  /// In production we rely on the HttpOnly cookie instead.
  final String? refreshToken;
}

/// Login can return either a token pair or a 2FA challenge — they share the
/// same HTTP 200 status, so we sniff the body at the data-source boundary.
sealed class LoginResult {
  const LoginResult();
}

final class LoginTokens extends LoginResult {
  const LoginTokens(this.tokens);
  final TokenResponse tokens;
}

final class LoginMfaRequired extends LoginResult {
  const LoginMfaRequired({required this.mfaToken, required this.methods});

  factory LoginMfaRequired.fromJson(Map<String, dynamic> json) {
    final methods = (json['methods'] as List<dynamic>? ?? const [])
        .map((m) => m as String)
        .toList();
    return LoginMfaRequired(
      mfaToken: json['mfa_token'] as String,
      methods: methods,
    );
  }

  final String mfaToken;
  final List<String> methods;
}

/// Public auth configuration from `GET /api/v1/auth/config`. Drives which
/// unauthenticated entry points to show (self-service signup, email-based
/// password reset) and the white-label branding shown pre-login.
class AuthConfig {
  const AuthConfig({
    required this.openRegistration,
    required this.passwordResetEnabled,
    this.appName,
    this.appMessage,
    this.hasCustomIcon = false,
    this.appIconUpdatedAt,
    this.ssoProviders = const [],
    this.localPasswordLoginDisabled = false,
  });

  factory AuthConfig.fromJson(Map<String, dynamic> json) => AuthConfig(
    openRegistration: json['open_registration'] == true,
    passwordResetEnabled: json['password_reset_enabled'] == true,
    appName: json['app_name'] as String?,
    appMessage: json['app_message'] as String?,
    hasCustomIcon: json['has_custom_icon'] == true,
    appIconUpdatedAt: json['app_icon_updated_at'] as String?,
    // Both default safely when absent, so a client built after V025 still
    // works against a server from before it: no buttons, password form shown.
    ssoProviders:
        (json['sso_providers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SsoProvider.fromJson)
            .toList()
          ..sort((a, b) {
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            return byOrder != 0
                ? byOrder
                : a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  );
          }),
    localPasswordLoginDisabled: json['local_password_login_disabled'] == true,
  );

  final bool openRegistration;
  final bool passwordResetEnabled;

  /// White-label name override. `null` means the bundled default is in use.
  final String? appName;

  /// Optional notice shown to users on the login screen.
  final String? appMessage;

  /// Whether a custom app icon is served from `GET /api/v1/branding/icon`.
  final bool hasCustomIcon;

  /// Raw RFC3339 timestamp of the last icon change — used only as an opaque
  /// cache-busting token on the icon URL.
  final String? appIconUpdatedAt;

  /// Single sign-on buttons to offer, already in display order. Empty on every
  /// install where no administrator has configured a provider.
  final List<SsoProvider> ssoProviders;

  /// Whether this deployment has switched the password form off in favour of
  /// single sign-on.
  ///
  /// A hint for the UI only. The server refuses password logins independently,
  /// and always lets a superadmin holding a local password through — which is
  /// why the form is hidden behind a link rather than removed.
  final bool localPasswordLoginDisabled;
}

class TwoFactorVerifyRequest {
  const TwoFactorVerifyRequest({
    required this.mfaToken,
    required this.method,
    required this.code,
  });

  final String mfaToken;
  final String method;
  final String code;

  Map<String, dynamic> toJson() => {
    'mfa_token': mfaToken,
    'method': method,
    'code': code,
  };
}
