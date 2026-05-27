/// JSON shapes for the TOTP / recovery-code / passkey endpoints.
class TotpStartResponse {
  const TotpStartResponse({
    required this.secretBase32,
    required this.provisioningUri,
    required this.qrPngBase64,
  });

  factory TotpStartResponse.fromJson(Map<String, dynamic> json) {
    return TotpStartResponse(
      secretBase32: json['secret_base32'] as String,
      provisioningUri: json['provisioning_uri'] as String,
      qrPngBase64: json['qr_png_base64'] as String,
    );
  }

  final String secretBase32;
  final String provisioningUri;

  /// Raw base64-encoded PNG bytes (no `data:` prefix).
  final String qrPngBase64;
}

class RecoveryCodesResponse {
  const RecoveryCodesResponse({required this.codes});

  factory RecoveryCodesResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['recovery_codes'] as List<dynamic>? ?? const [];
    return RecoveryCodesResponse(
      codes: raw.map((c) => c as String).toList(),
    );
  }

  final List<String> codes;
}

class PasskeyListItem {
  const PasskeyListItem({
    required this.id,
    required this.nickname,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory PasskeyListItem.fromJson(Map<String, dynamic> json) {
    return PasskeyListItem(
      id: json['id'] as String,
      nickname: (json['nickname'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      lastUsedAt: json['last_used_at'] == null
          ? null
          : DateTime.parse(json['last_used_at'] as String),
    );
  }

  final String id;
  final String nickname;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// Output of the WebAuthn `start` ceremonies: opaque state-id the backend uses
/// to correlate `finish`, plus the browser-shaped `PublicKeyCredentialOptions`
/// JSON that gets handed straight to `navigator.credentials.{create,get}()`.
class PasskeyCeremony {
  const PasskeyCeremony({required this.stateId, required this.options});

  factory PasskeyCeremony.fromJson(
    Map<String, dynamic> json,
    String optionsKey,
  ) {
    return PasskeyCeremony(
      stateId: json['state_id'] as String,
      options: Map<String, dynamic>.from(json[optionsKey] as Map),
    );
  }

  final String stateId;
  final Map<String, dynamic> options;
}
