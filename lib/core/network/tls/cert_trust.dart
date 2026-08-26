import 'package:dio/dio.dart';
import 'package:intellipilot/core/network/tls/cert_pin_store.dart';
import 'package:intellipilot/core/network/tls/cert_trust_stub.dart'
    if (dart.library.io) 'package:intellipilot/core/network/tls/cert_trust_io.dart'
    as impl;
import 'package:intellipilot/core/network/tls/cert_trust_types.dart';

export 'package:intellipilot/core/network/tls/cert_pin_store.dart';
export 'package:intellipilot/core/network/tls/cert_trust_types.dart';

/// Probe a server's TLS certificate. Returns
/// [CertProbeStatus.notApplicable] on web, where the browser owns TLS.
Future<CertProbeOutcome> probeTls(Uri uri) => impl.probeTls(uri);

/// Make [dio] accept exactly the certificates the user has explicitly pinned.
/// No-op on web.
void installCertPinning(Dio dio, CertPinStore store) =>
    impl.installCertPinning(dio, store);
