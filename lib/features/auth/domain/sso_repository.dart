import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/data/dtos/sso_dtos.dart';

/// Outcome of one poll of a device-flow sign-in.
///
/// "Still waiting" is a normal state of this flow, not a failure, so it is a
/// variant here rather than an [AppFailure] — a caller that treated it as an
/// error would abandon the sign-in the moment it started.
sealed class SsoDevicePoll {
  const SsoDevicePoll();
}

/// The human has not finished at the identity provider yet.
final class SsoDevicePending extends SsoDevicePoll {
  const SsoDevicePending();
}

/// Signed in. The session is established; hand these to `SessionBloc`.
final class SsoDeviceSignedIn extends SsoDevicePoll {
  const SsoDeviceSignedIn(this.tokens);
  final TokenResponse tokens;
}

/// An identity was linked to the already-signed-in account. No new session.
final class SsoDeviceLinked extends SsoDevicePoll {
  const SsoDeviceLinked();
}

/// Single sign-on operations.
///
/// Kept apart from `AuthRepository` because the two halves have different
/// audiences: sign-in is called by an anonymous login screen, linking by a
/// signed-in user on their Security page. Mixing them into one interface would
/// make it impossible to tell at a glance which calls need a session.
abstract interface class SsoRepository {
  /// Begin a device-flow sign-in. Desktop and mobile only — the web client
  /// navigates to the server's redirect endpoint instead.
  Future<Result<SsoDeviceStart, AppFailure>> startDeviceSignIn(String slug);

  /// Begin a device-flow *link* against the signed-in account.
  Future<Result<SsoDeviceStart, AppFailure>> startDeviceLink(String slug);

  /// Poll a started device flow once. Respect the interval the server gave —
  /// it enforces it and answers 429 otherwise.
  Future<Result<SsoDevicePoll, AppFailure>> pollDevice(String pollToken);

  /// Providers the signed-in user has connected to their account.
  Future<Result<List<SsoIdentity>, AppFailure>> listIdentities();

  /// Disconnect one. Refused by the server when it is the only way the account
  /// can sign in.
  Future<Result<Unit, AppFailure>> unlinkIdentity(String id);
}
