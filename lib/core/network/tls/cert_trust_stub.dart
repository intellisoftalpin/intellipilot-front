import 'package:dio/dio.dart';
import 'package:intellipilot/core/network/tls/cert_pin_store.dart';
import 'package:intellipilot/core/network/tls/cert_trust_types.dart';

/// Web build: the browser owns TLS. There is no `HttpClient` to configure and
/// no way (nor any need) for the app to override certificate validation.
Future<CertProbeOutcome> probeTls(Uri uri) async =>
    CertProbeOutcome.notApplicable;

void installCertPinning(Dio dio, CertPinStore store) {
  // No-op on web.
}
