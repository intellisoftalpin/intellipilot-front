/// Admin-side wire shapes for OIDC provider configuration (server V025).
///
/// Mirrors `crate::admin::oidc::*`. The client secret follows the same
/// write-only convention as the LDAP service password: the server never
/// returns it, only a [OidcProviderConfig.clientSecretSet] flag, and a blank
/// value in an update means "keep the stored one".
library;

class OidcProviderConfig {
  const OidcProviderConfig({
    required this.id,
    required this.slug,
    required this.displayName,
    required this.enabled,
    required this.issuerUrl,
    required this.clientId,
    required this.clientSecretSet,
    required this.scopes,
    required this.claimEmail,
    required this.claimUsername,
    required this.claimDisplayName,
    required this.claimGroups,
    required this.superadminGroup,
    required this.allowJitProvisioning,
    required this.requireEmailVerified,
    required this.deviceFlowEnabled,
    required this.sortOrder,
    required this.skipTlsVerify,
    required this.redirectUri,
    required this.backchannelLogoutUri,
  });

  factory OidcProviderConfig.fromJson(Map<String, dynamic> j) =>
      OidcProviderConfig(
        id: j['id'] as String? ?? '',
        slug: j['slug'] as String? ?? '',
        displayName: j['display_name'] as String? ?? '',
        enabled: j['enabled'] == true,
        issuerUrl: j['issuer_url'] as String? ?? '',
        clientId: j['client_id'] as String? ?? '',
        clientSecretSet: j['client_secret_set'] == true,
        scopes: j['scopes'] as String? ?? 'openid profile email',
        claimEmail: j['claim_email'] as String? ?? 'email',
        claimUsername: j['claim_username'] as String? ?? 'preferred_username',
        claimDisplayName: j['claim_display_name'] as String? ?? 'name',
        claimGroups: j['claim_groups'] as String? ?? 'groups',
        superadminGroup: j['superadmin_group'] as String? ?? '',
        allowJitProvisioning: j['allow_jit_provisioning'] == true,
        requireEmailVerified: j['require_email_verified'] == true,
        deviceFlowEnabled: j['device_flow_enabled'] == true,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        skipTlsVerify: j['skip_tls_verify'] == true,
        redirectUri: j['redirect_uri'] as String? ?? '',
        backchannelLogoutUri: j['backchannel_logout_uri'] as String? ?? '',
      );

  final String id;
  final String slug;
  final String displayName;
  final bool enabled;
  final String issuerUrl;
  final String clientId;

  /// Whether a secret is stored. The value itself is never sent to a client.
  final bool clientSecretSet;

  final String scopes;
  final String claimEmail;
  final String claimUsername;
  final String claimDisplayName;
  final String claimGroups;

  /// Membership grants platform superadmin and absence revokes it, on every
  /// sign-in. Empty leaves the flag managed inside IntelliPilot.
  final String superadminGroup;

  final bool allowJitProvisioning;
  final bool requireEmailVerified;
  final bool deviceFlowEnabled;
  final int sortOrder;
  final bool skipTlsVerify;

  /// What must be registered at the identity provider. Computed by the server
  /// from this deployment's public origin, so it is read-only here — the point
  /// is that an operator copies it rather than guessing.
  final String redirectUri;

  /// Where the provider should POST back-channel logout notifications.
  final String backchannelLogoutUri;

  UpsertOidcProviderRequest toUpdate() => UpsertOidcProviderRequest(
    slug: slug,
    displayName: displayName,
    enabled: enabled,
    issuerUrl: issuerUrl,
    clientId: clientId,
    scopes: scopes,
    claimEmail: claimEmail,
    claimUsername: claimUsername,
    claimDisplayName: claimDisplayName,
    claimGroups: claimGroups,
    superadminGroup: superadminGroup,
    allowJitProvisioning: allowJitProvisioning,
    requireEmailVerified: requireEmailVerified,
    deviceFlowEnabled: deviceFlowEnabled,
    sortOrder: sortOrder,
    skipTlsVerify: skipTlsVerify,
  );
}

class UpsertOidcProviderRequest {
  const UpsertOidcProviderRequest({
    required this.slug,
    required this.displayName,
    required this.enabled,
    required this.issuerUrl,
    required this.clientId,
    required this.scopes,
    required this.claimEmail,
    required this.claimUsername,
    required this.claimDisplayName,
    required this.claimGroups,
    required this.superadminGroup,
    required this.allowJitProvisioning,
    required this.requireEmailVerified,
    required this.deviceFlowEnabled,
    required this.sortOrder,
    required this.skipTlsVerify,
    this.clientSecret,
  });

  /// Sensible starting point for a new provider: everything off until it has
  /// been tested, and the standard OIDC claim names, which Authentik,
  /// Keycloak, Entra and Google all honour.
  factory UpsertOidcProviderRequest.blank() => const UpsertOidcProviderRequest(
    slug: '',
    displayName: '',
    enabled: false,
    issuerUrl: '',
    clientId: '',
    scopes: 'openid profile email',
    claimEmail: 'email',
    claimUsername: 'preferred_username',
    claimDisplayName: 'name',
    claimGroups: 'groups',
    superadminGroup: '',
    allowJitProvisioning: true,
    requireEmailVerified: true,
    deviceFlowEnabled: true,
    sortOrder: 0,
    skipTlsVerify: false,
  );

  final String slug;
  final String displayName;
  final bool enabled;
  final String issuerUrl;
  final String clientId;

  /// Null or blank keeps whatever is stored.
  final String? clientSecret;

  final String scopes;
  final String claimEmail;
  final String claimUsername;
  final String claimDisplayName;
  final String claimGroups;
  final String superadminGroup;
  final bool allowJitProvisioning;
  final bool requireEmailVerified;
  final bool deviceFlowEnabled;
  final int sortOrder;
  final bool skipTlsVerify;

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'display_name': displayName,
    'enabled': enabled,
    'issuer_url': issuerUrl,
    'client_id': clientId,
    'client_secret': clientSecret,
    'scopes': scopes,
    'claim_email': claimEmail,
    'claim_username': claimUsername,
    'claim_display_name': claimDisplayName,
    'claim_groups': claimGroups,
    'superadmin_group': superadminGroup,
    'allow_jit_provisioning': allowJitProvisioning,
    'require_email_verified': requireEmailVerified,
    'device_flow_enabled': deviceFlowEnabled,
    'sort_order': sortOrder,
    'skip_tls_verify': skipTlsVerify,
  };

  UpsertOidcProviderRequest copyWith({
    String? slug,
    String? displayName,
    bool? enabled,
    String? issuerUrl,
    String? clientId,
    String? clientSecret,
    String? scopes,
    String? claimEmail,
    String? claimUsername,
    String? claimDisplayName,
    String? claimGroups,
    String? superadminGroup,
    bool? allowJitProvisioning,
    bool? requireEmailVerified,
    bool? deviceFlowEnabled,
    int? sortOrder,
    bool? skipTlsVerify,
  }) => UpsertOidcProviderRequest(
    slug: slug ?? this.slug,
    displayName: displayName ?? this.displayName,
    enabled: enabled ?? this.enabled,
    issuerUrl: issuerUrl ?? this.issuerUrl,
    clientId: clientId ?? this.clientId,
    clientSecret: clientSecret ?? this.clientSecret,
    scopes: scopes ?? this.scopes,
    claimEmail: claimEmail ?? this.claimEmail,
    claimUsername: claimUsername ?? this.claimUsername,
    claimDisplayName: claimDisplayName ?? this.claimDisplayName,
    claimGroups: claimGroups ?? this.claimGroups,
    superadminGroup: superadminGroup ?? this.superadminGroup,
    allowJitProvisioning: allowJitProvisioning ?? this.allowJitProvisioning,
    requireEmailVerified: requireEmailVerified ?? this.requireEmailVerified,
    deviceFlowEnabled: deviceFlowEnabled ?? this.deviceFlowEnabled,
    sortOrder: sortOrder ?? this.sortOrder,
    skipTlsVerify: skipTlsVerify ?? this.skipTlsVerify,
  );
}

/// What the "Test" button learned. Never an error — an unreachable provider is
/// a finding to display, which is exactly what an administrator pressed the
/// button to discover.
class OidcTestResult {
  const OidcTestResult({
    required this.ok,
    required this.message,
    required this.supportsDeviceFlow,
    required this.jwksKeys,
    required this.redirectUri,
    this.issuer,
    this.authorizationEndpoint,
    this.tokenEndpoint,
    this.userinfoEndpoint,
  });

  factory OidcTestResult.fromJson(Map<String, dynamic> j) => OidcTestResult(
    ok: j['ok'] == true,
    message: j['message'] as String? ?? '',
    supportsDeviceFlow: j['supports_device_flow'] == true,
    jwksKeys: (j['jwks_keys'] as num?)?.toInt() ?? 0,
    redirectUri: j['redirect_uri'] as String? ?? '',
    issuer: j['issuer'] as String?,
    authorizationEndpoint: j['authorization_endpoint'] as String?,
    tokenEndpoint: j['token_endpoint'] as String?,
    userinfoEndpoint: j['userinfo_endpoint'] as String?,
  );

  final bool ok;
  final String message;
  final bool supportsDeviceFlow;
  final int jwksKeys;
  final String redirectUri;
  final String? issuer;
  final String? authorizationEndpoint;
  final String? tokenEndpoint;
  final String? userinfoEndpoint;
}
