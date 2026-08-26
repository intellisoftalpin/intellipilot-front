import 'package:flutter/foundation.dart';

/// What a TLS probe found.
enum CertProbeStatus {
  /// The certificate chain validated normally. No user decision needed.
  trusted,

  /// The platform rejected the certificate (self-signed, unknown CA, expired,
  /// hostname mismatch). The user may choose to pin it.
  untrusted,

  /// Could not reach the host at all — DNS, refused, timeout.
  unreachable,

  /// Not applicable: on web the browser owns TLS entirely.
  notApplicable,
}

/// The details shown to a user being asked to trust a certificate.
///
/// Deliberately verbose: pinning bypasses CA validation for that host, so the
/// decision has to be an informed one. The fingerprint is what an admin can
/// actually compare against their server.
@immutable
class CertInfo {
  const CertInfo({
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.sha256,
  });

  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;

  /// Lowercase hex SHA-256 of the DER encoding, colon-grouped for reading.
  final String sha256;

  bool get isExpired => DateTime.now().isAfter(validTo);
  bool get isNotYetValid => DateTime.now().isBefore(validFrom);

  @override
  bool operator ==(Object other) =>
      other is CertInfo && other.sha256 == sha256 && other.subject == subject;

  @override
  int get hashCode => Object.hash(sha256, subject);
}

@immutable
class CertProbeOutcome {
  const CertProbeOutcome({required this.status, this.cert, this.message});

  final CertProbeStatus status;

  /// Present only for [CertProbeStatus.untrusted].
  final CertInfo? cert;

  /// Diagnostic detail for [CertProbeStatus.unreachable].
  final String? message;

  static const notApplicable = CertProbeOutcome(
    status: CertProbeStatus.notApplicable,
  );
}
