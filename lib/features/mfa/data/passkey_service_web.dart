// Web-only implementation of [PasskeyService]. Uses `dart:js_interop` + the
// `web` package to drive `navigator.credentials.{create,get}()`.
//
// The wire format mirrors `webauthn-rs` JSON: every `ArrayBuffer` field is
// transported as base64url (no padding). We translate between Dart maps and
// JS `ArrayBuffer`s at the field positions WebAuthn specifies.
//
// Browser compatibility: Chrome 67+, Firefox 60+, Safari 14+, Edge 18+. We
// do *not* rely on `parseCreationOptionsFromJSON` so we run on older browsers.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:web/web.dart' as web;

class _WebPasskeyService implements PasskeyService {
  const _WebPasskeyService();

  @override
  bool get isSupported {
    // The constructors we use exist whenever `package:web` does, so success
    // is the meaningful runtime check we can do here. Older browsers will
    // throw in `register`/`authenticate` and that's surfaced as a ceremony
    // error by the cubits.
    return true;
  }

  @override
  Future<Map<String, dynamic>> register(
    Map<String, dynamic> creationOptions,
  ) async {
    final inner = _innerPublicKey(creationOptions);
    final jsOpts = _creationOptionsToJs(inner);
    final init = web.CredentialCreationOptions(publicKey: jsOpts);
    final cred = await web.window.navigator.credentials.create(init).toDart;
    if (cred == null) {
      throw PasskeyCeremonyError('No credential returned by the browser.');
    }
    return _serializeAttestation(cred as web.PublicKeyCredential);
  }

  @override
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> requestOptions,
  ) async {
    final inner = _innerPublicKey(requestOptions);
    final jsOpts = _requestOptionsToJs(inner);
    final init = web.CredentialRequestOptions(publicKey: jsOpts);
    final cred = await web.window.navigator.credentials.get(init).toDart;
    if (cred == null) {
      throw PasskeyCeremonyError('No credential returned by the browser.');
    }
    return _serializeAssertion(cred as web.PublicKeyCredential);
  }

  /// `webauthn-rs` wraps options under `publicKey`; if the caller passes the
  /// raw inner options, take them as-is.
  Map<String, dynamic> _innerPublicKey(Map<String, dynamic> options) {
    final inner = options['publicKey'];
    return inner is Map<String, dynamic>
        ? inner
        : Map<String, dynamic>.from(options);
  }
}

PasskeyService createPasskeyService() => const _WebPasskeyService();

// ---------------------------------------------------------------------------
// Base64url helpers
// ---------------------------------------------------------------------------

Uint8List _b64uDecode(String input) {
  final padded = input.padRight((input.length + 3) & ~3, '=');
  return base64Url.decode(padded);
}

String _b64uEncode(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

JSArrayBuffer _toJsBuffer(String b64u) => _b64uDecode(b64u).buffer.toJS;

String _jsBufferToB64u(JSArrayBuffer buf) =>
    _b64uEncode(buf.toDart.asUint8List());

// ---------------------------------------------------------------------------
// JS-shaped option builders
// ---------------------------------------------------------------------------

web.PublicKeyCredentialCreationOptions _creationOptionsToJs(
  Map<String, dynamic> opts,
) {
  final rp = opts['rp'] as Map<String, dynamic>;
  final user = opts['user'] as Map<String, dynamic>;
  final pubKeyCredParams =
      (opts['pubKeyCredParams'] as List<dynamic>? ?? const []).map((p) {
        final m = p as Map<String, dynamic>;
        return web.PublicKeyCredentialParameters(
          type: m['type'] as String,
          alg: (m['alg'] as num).toInt(),
        );
      }).toList();
  final exclude =
      (opts['excludeCredentials'] as List<dynamic>? ?? const []).map((c) {
        final m = c as Map<String, dynamic>;
        final tx =
            (m['transports'] as List<dynamic>? ?? const [])
                .map((t) => (t as String).toJS)
                .toList();
        return web.PublicKeyCredentialDescriptor(
          type: m['type'] as String,
          id: _toJsBuffer(m['id'] as String),
          transports: tx.toJS,
        );
      }).toList();

  return web.PublicKeyCredentialCreationOptions(
    rp: web.PublicKeyCredentialRpEntity(
      name: rp['name'] as String,
      id: (rp['id'] as String?) ?? '',
    ),
    user: web.PublicKeyCredentialUserEntity(
      id: _toJsBuffer(user['id'] as String),
      name: user['name'] as String,
      displayName: user['displayName'] as String,
    ),
    challenge: _toJsBuffer(opts['challenge'] as String),
    pubKeyCredParams: pubKeyCredParams.toJS,
    timeout: (opts['timeout'] as num?)?.toInt() ?? 60000,
    excludeCredentials: exclude.toJS,
    attestation: (opts['attestation'] as String?) ?? 'none',
  );
}

web.PublicKeyCredentialRequestOptions _requestOptionsToJs(
  Map<String, dynamic> opts,
) {
  final allow =
      (opts['allowCredentials'] as List<dynamic>? ?? const []).map((c) {
        final m = c as Map<String, dynamic>;
        final tx =
            (m['transports'] as List<dynamic>? ?? const [])
                .map((t) => (t as String).toJS)
                .toList();
        return web.PublicKeyCredentialDescriptor(
          type: m['type'] as String,
          id: _toJsBuffer(m['id'] as String),
          transports: tx.toJS,
        );
      }).toList();

  return web.PublicKeyCredentialRequestOptions(
    challenge: _toJsBuffer(opts['challenge'] as String),
    timeout: (opts['timeout'] as num?)?.toInt() ?? 60000,
    rpId: (opts['rpId'] as String?) ?? '',
    allowCredentials: allow.toJS,
    userVerification:
        (opts['userVerification'] as String?) ?? 'preferred',
  );
}

// ---------------------------------------------------------------------------
// Response serializers
// ---------------------------------------------------------------------------

Map<String, dynamic> _serializeAttestation(web.PublicKeyCredential cred) {
  final response = cred.response as web.AuthenticatorAttestationResponse;
  final transports =
      response.getTransports().toDart.map((s) => s.toDart).toList();
  return {
    'id': cred.id,
    'rawId': _jsBufferToB64u(cred.rawId),
    'type': cred.type,
    'response': {
      'clientDataJSON': _jsBufferToB64u(response.clientDataJSON),
      'attestationObject': _jsBufferToB64u(response.attestationObject),
      if (transports.isNotEmpty) 'transports': transports,
    },
    'clientExtensionResults': <String, dynamic>{},
  };
}

Map<String, dynamic> _serializeAssertion(web.PublicKeyCredential cred) {
  final response = cred.response as web.AuthenticatorAssertionResponse;
  final userHandle = response.userHandle;
  return {
    'id': cred.id,
    'rawId': _jsBufferToB64u(cred.rawId),
    'type': cred.type,
    'response': {
      'clientDataJSON': _jsBufferToB64u(response.clientDataJSON),
      'authenticatorData': _jsBufferToB64u(response.authenticatorData),
      'signature': _jsBufferToB64u(response.signature),
      if (userHandle != null) 'userHandle': _jsBufferToB64u(userHandle),
    },
    'clientExtensionResults': <String, dynamic>{},
  };
}
