// `_api` is intentionally a private field behind a public parameter.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/app/build_info.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/features/compatibility/domain/server_compatibility.dart';

class CompatibilityState extends Equatable {
  const CompatibilityState({
    this.status = CompatibilityStatus.unknown,
    this.serverVersion,
  });

  final CompatibilityStatus status;
  final String? serverVersion;

  bool get isBlocked => status == CompatibilityStatus.clientTooOld;

  @override
  List<Object?> get props => [status, serverVersion];
}

/// Checks the client build against the server's and blocks the app when the
/// client is behind.
///
/// Reads the public, unauthenticated, never-rate-limited `/api/v1/version`, so
/// the check works before sign-in and cannot be thwarted by an expired session.
/// A failed probe stays [CompatibilityStatus.unknown] and the app runs — a
/// network blip must not lock anyone out of a working install.
class CompatibilityCubit extends Cubit<CompatibilityState> {
  CompatibilityCubit({required ApiClient api, String? clientVersion})
    : _api = api,
      _clientVersion = clientVersion ?? BuildInfo.version,
      super(const CompatibilityState());

  final ApiClient _api;
  final String _clientVersion;

  /// Probe the server and publish a verdict. Safe to call repeatedly — after
  /// connecting to a server, after sign-in, on resume.
  Future<void> check() async {
    final res = await _api.get('/api/v1/version');
    final body = res.valueOrNull?.data;
    final serverVersion = body is Map ? body['version'] as String? : null;
    if (isClosed) return;
    emit(
      CompatibilityState(
        status: judge(
          clientVersion: _clientVersion,
          serverVersion: serverVersion,
        ),
        serverVersion: serverVersion,
      ),
    );
  }

  /// Forget the verdict — used when the app points at a different server, whose
  /// version has not been established yet.
  void reset() {
    if (!isClosed) emit(const CompatibilityState());
  }
}
