import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:intellipilot/core/network/tls/cert_pin_store.dart';
import 'package:intellipilot/core/network/tls/cert_trust_types.dart';

/// Colon-grouped lowercase hex SHA-256 of a certificate's DER encoding — the
/// same form `openssl x509 -fingerprint -sha256` prints, so an admin can
/// compare the two directly.
String fingerprintOf(X509Certificate cert) {
  final digest = sha256.convert(cert.der);
  final hex = digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .toList();
  return hex.join(':');
}

CertInfo _infoOf(X509Certificate cert) => CertInfo(
  subject: cert.subject,
  issuer: cert.issuer,
  validFrom: cert.startValidity,
  validTo: cert.endValidity,
  sha256: fingerprintOf(cert),
);

/// Attempt a TLS handshake with [uri] and report what the platform made of the
/// certificate.
///
/// When the certificate is rejected we capture it and **still fail the
/// handshake** — the probe never completes a request over a connection the
/// platform distrusts. The captured details exist purely so the user can be
/// asked an informed question.
Future<CertProbeOutcome> probeTls(Uri uri) async {
  if (uri.scheme != 'https') {
    return const CertProbeOutcome(status: CertProbeStatus.trusted);
  }
  X509Certificate? rejected;
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..badCertificateCallback = (cert, host, port) {
      rejected = cert;
      return false; // never proceed insecurely, even to probe
    };
  try {
    final req = await client.getUrl(uri);
    final res = await req.close();
    await res.drain<void>();
    return const CertProbeOutcome(status: CertProbeStatus.trusted);
  } on HandshakeException catch (e) {
    final cert = rejected;
    if (cert != null) {
      return CertProbeOutcome(
        status: CertProbeStatus.untrusted,
        cert: _infoOf(cert),
      );
    }
    return CertProbeOutcome(
      status: CertProbeStatus.unreachable,
      message: e.message,
    );
  } on SocketException catch (e) {
    return CertProbeOutcome(
      status: CertProbeStatus.unreachable,
      message: e.message,
    );
  } on Object catch (e) {
    return CertProbeOutcome(
      status: CertProbeStatus.unreachable,
      message: e.toString(),
    );
  } finally {
    client.close(force: true);
  }
}

/// Teach [dio] to accept exactly the certificates the user has pinned.
///
/// `badCertificateCallback` fires *only* for certificates the platform has
/// already rejected, so normal TLS is untouched by this. An unpinned host, or a
/// pinned host presenting a different certificate, still fails.
void installCertPinning(Dio dio, CertPinStore store) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      return HttpClient()
        ..badCertificateCallback = (cert, host, port) =>
            store.isTrusted(host, port, fingerprintOf(cert));
    },
  );
}
