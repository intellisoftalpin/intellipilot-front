import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Loads the signed-in user's profile, then builds [builder] with it — a
/// spinner until then, an error if it cannot be had.
///
/// The load starts once, not on every build: pages used to start it inside
/// `build`, so each rebuild threw the page back to its spinner and fired
/// another `/me`. It starts again only when a different identity signs in
/// (an account switch). Key the gate by the page's route parameters so a new
/// project or page also starts afresh, with providers built for it.
class ProfileGate extends StatefulWidget {
  const ProfileGate({required this.builder, super.key});

  final Widget Function(BuildContext context, UserProfile profile) builder;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Future<UserProfile?> _profile;
  int? _identity;

  static int _currentIdentity() =>
      getIt.isRegistered<SessionBloc>() ? getIt<SessionBloc>().identity : 0;

  @override
  Widget build(BuildContext context) {
    final identity = _currentIdentity();
    if (identity != _identity) {
      _identity = identity;
      _profile = getIt<ProfileRepository>().getProfile().then(
        (r) => r.valueOrNull,
      );
    }
    return FutureBuilder<UserProfile?>(
      // A new identity gets a fresh subtree: providers below must not carry
      // over the previous user's id.
      key: ValueKey(identity),
      future: _profile,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) {
          return Scaffold(
            body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
          );
        }
        return widget.builder(context, profile);
      },
    );
  }
}
