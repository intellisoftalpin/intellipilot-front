/// JSON DTOs for the auth endpoints. Hand-written rather than freezed/json:
/// the surface is small and changes touch the API contract, so a single edit
/// site is preferable to a codegen step here.
class RegisterRequest {
  const RegisterRequest({
    required this.email,
    required this.username,
    required this.password,
    this.fullName = '',
  });

  final String email;
  final String username;
  final String password;
  final String fullName;

  Map<String, dynamic> toJson() => {
    'email': email,
    'username': username,
    'password': password,
    'full_name': fullName,
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
