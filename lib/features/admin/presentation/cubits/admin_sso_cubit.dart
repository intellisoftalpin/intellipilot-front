import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/admin/data/dtos/sso_admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';

sealed class AdminSsoState extends Equatable {
  const AdminSsoState();
  @override
  List<Object?> get props => const [];
}

final class AdminSsoLoading extends AdminSsoState {
  const AdminSsoLoading();
}

final class AdminSsoFailed extends AdminSsoState {
  const AdminSsoFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

final class AdminSsoLoaded extends AdminSsoState {
  const AdminSsoLoaded({required this.providers, this.busy = false});

  final List<OidcProviderConfig> providers;
  final bool busy;

  AdminSsoLoaded copyWith({
    List<OidcProviderConfig>? providers,
    bool? busy,
  }) => AdminSsoLoaded(
    providers: providers ?? this.providers,
    busy: busy ?? this.busy,
  );

  @override
  List<Object?> get props => [providers, busy];
}

/// Owns the list of configured identity providers.
///
/// Mutations return the failure rather than emitting an error state: a failed
/// save must leave the editor open with what the administrator typed still in
/// it, and replacing the list with an error page would throw that away.
class AdminSsoCubit extends Cubit<AdminSsoState> {
  AdminSsoCubit(this._repo) : super(const AdminSsoLoading());

  final AdminRepository _repo;

  Future<void> load() async {
    emit(const AdminSsoLoading());
    final res = await _repo.listOidcProviders();
    res.when(
      ok: (list) => emit(AdminSsoLoaded(providers: list)),
      err: (f) => emit(AdminSsoFailed(f)),
    );
  }

  /// Create or update. `null` [id] creates. Returns the failure, or null.
  Future<AppFailure?> save(String? id, UpsertOidcProviderRequest req) async {
    final cur = state;
    if (cur is AdminSsoLoaded) emit(cur.copyWith(busy: true));
    final res = id == null
        ? await _repo.createOidcProvider(req)
        : await _repo.updateOidcProvider(id, req);
    return res.when(
      ok: (_) async {
        await load();
        return null;
      },
      err: (f) {
        if (cur is AdminSsoLoaded) emit(cur.copyWith(busy: false));
        return Future.value(f);
      },
    );
  }

  Future<AppFailure?> delete(String id) async {
    final cur = state;
    if (cur is AdminSsoLoaded) emit(cur.copyWith(busy: true));
    final res = await _repo.deleteOidcProvider(id);
    return res.when(
      ok: (_) async {
        await load();
        return null;
      },
      err: (f) {
        if (cur is AdminSsoLoaded) emit(cur.copyWith(busy: false));
        return Future.value(f);
      },
    );
  }

  /// Ask the server what the provider currently publishes. A failure here is
  /// itself the answer, so it is surfaced rather than swallowed.
  Future<Result<OidcTestResult, AppFailure>> test(String id) =>
      _repo.testOidcProvider(id);
}
