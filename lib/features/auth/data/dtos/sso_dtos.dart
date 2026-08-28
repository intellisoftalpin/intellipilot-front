/// Wire shapes for OpenID Connect single sign-on (server V025).
///
/// Two flows reach these types. The **web** client never touches them beyond
/// [SsoProvider]: it navigates the whole page to the server's start endpoint
/// and comes back with a session cookie already set, so there is no JSON to
/// parse. The **desktop and mobile** clients use the device flow, which is
/// where the rest of this file earns its keep.
library;

/// One sign-in button on the login screen.
///
/// Carries nothing about the identity provider itself — no issuer, no client
/// id. The server deliberately withholds those from an unauthenticated caller,
/// and the app has no use for them: every request goes to IntelliPilot, which
/// brokers the exchange.
class SsoProvider {
  const SsoProvider({
    required this.slug,
    required this.displayName,
    required this.deviceFlowEnabled,
    this.sortOrder = 0,
  });

  factory SsoProvider.fromJson(Map<String, dynamic> json) => SsoProvider(
    slug: (json['slug'] as String?) ?? '',
    displayName: (json['display_name'] as String?) ?? '',
    deviceFlowEnabled: json['device_flow_enabled'] == true,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );

  /// Route key used to build the server URLs for this provider.
  final String slug;

  /// Button label, chosen by the administrator.
  final String displayName;

  /// Whether the device flow is available. False means this provider is
  /// web-only and the native clients must not offer it — the alternative is a
  /// button that always fails.
  final bool deviceFlowEnabled;

  final int sortOrder;
}

/// A started device authorization: what to show the human, and what to poll
/// with.
class SsoDeviceStart {
  const SsoDeviceStart({
    required this.userCode,
    required this.verificationUri,
    required this.pollToken,
    required this.interval,
    required this.expiresIn,
    this.verificationUriComplete,
  });

  factory SsoDeviceStart.fromJson(Map<String, dynamic> json) => SsoDeviceStart(
    userCode: (json['user_code'] as String?) ?? '',
    verificationUri: (json['verification_uri'] as String?) ?? '',
    verificationUriComplete: json['verification_uri_complete'] as String?,
    pollToken: (json['poll_token'] as String?) ?? '',
    interval: (json['interval'] as num?)?.toInt() ?? 5,
    expiresIn: (json['expires_in'] as num?)?.toInt() ?? 600,
  );

  /// The code the human types at the provider.
  final String userCode;

  /// Where they type it.
  final String verificationUri;

  /// The same page with the code already filled in, when the provider offers
  /// one. Preferred for the "open browser" button; [verificationUri] is what
  /// gets shown as text, because a human retyping a URL wants the short one.
  final String? verificationUriComplete;

  /// Opaque token for [SsoRepository.pollDevice]. Not a credential at the
  /// identity provider — the server holds that and never hands it over.
  final String pollToken;

  /// Seconds the server requires between polls. It enforces this itself and
  /// answers 429 if ignored, so it is a floor, not a suggestion.
  final int interval;

  /// Seconds until the attempt expires at the provider.
  final int expiresIn;
}

/// An identity provider the signed-in user has connected to their account.
class SsoIdentity {
  const SsoIdentity({
    required this.id,
    required this.providerSlug,
    required this.providerDisplayName,
    required this.subject,
    required this.emailAtLink,
    this.createdAt,
    this.lastLoginAt,
  });

  factory SsoIdentity.fromJson(Map<String, dynamic> json) => SsoIdentity(
    id: (json['id'] as String?) ?? '',
    providerSlug: (json['provider_slug'] as String?) ?? '',
    providerDisplayName: (json['provider_display_name'] as String?) ?? '',
    subject: (json['subject'] as String?) ?? '',
    emailAtLink: (json['email_at_link'] as String?) ?? '',
    createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
    lastLoginAt: DateTime.tryParse((json['last_login_at'] as String?) ?? ''),
  );

  final String id;
  final String providerSlug;
  final String providerDisplayName;

  /// The provider's own identifier for this person. Shown so a user with two
  /// accounts at the same provider can tell the links apart.
  final String subject;

  /// The address the provider asserted when the link was made. Informational
  /// only — it is never what authenticates.
  final String emailAtLink;

  final DateTime? createdAt;
  final DateTime? lastLoginAt;
}
