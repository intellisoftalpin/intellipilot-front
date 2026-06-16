import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

/// Resolved white-label branding. All fields fall back to the bundled defaults
/// (the "IntelliPilot" name and the in-app logo asset) when null.
class Branding extends Equatable {
  const Branding({this.appName, this.appMessage, this.iconUrl});

  /// The defaults applied before [BrandingCubit.load] completes (and whenever
  /// the server reports no overrides).
  const Branding.defaults() : appName = null, appMessage = null, iconUrl = null;

  /// Custom application name, or null to use the bundled default.
  final String? appName;

  /// Optional login-screen notice.
  final String? appMessage;

  /// Absolute URL of the custom app icon, or null to use the bundled asset.
  final String? iconUrl;

  @override
  List<Object?> get props => [appName, appMessage, iconUrl];
}

/// App-lifetime holder for white-label branding. Loaded once from the public
/// `/auth/config` endpoint at startup; consumed by the browser tab title, the
/// top-bar brand mark and the login screen.
class BrandingCubit extends Cubit<Branding> {
  BrandingCubit(this._repo, this._config) : super(const Branding.defaults());

  final AuthRepository _repo;
  final ApiConfig _config;

  Future<void> load() async {
    final res = await _repo.authConfig();
    res.when(
      ok: (c) {
        final base = _config.baseUrl.replaceAll(RegExp(r'/+$'), '');
        // The timestamp is an opaque cache-busting token so the icon refreshes
        // when an admin replaces it.
        final v = Uri.encodeQueryComponent(c.appIconUpdatedAt ?? '');
        emit(
          Branding(
            appName: (c.appName?.trim().isEmpty ?? true)
                ? null
                : c.appName!.trim(),
            appMessage: (c.appMessage?.trim().isEmpty ?? true)
                ? null
                : c.appMessage!.trim(),
            iconUrl: c.hasCustomIcon ? '$base/api/v1/branding/icon?v=$v' : null,
          ),
        );
      },
      // Branding is best-effort chrome — on failure we silently keep defaults.
      err: (_) {},
    );
  }
}
