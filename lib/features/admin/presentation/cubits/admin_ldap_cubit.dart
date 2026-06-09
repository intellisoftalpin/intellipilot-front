import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';

sealed class AdminLdapState extends Equatable {
  const AdminLdapState();
  @override
  List<Object?> get props => const [];
}

final class AdminLdapLoading extends AdminLdapState {
  const AdminLdapLoading();
}

final class AdminLdapFailed extends AdminLdapState {
  const AdminLdapFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

final class AdminLdapLoaded extends AdminLdapState {
  const AdminLdapLoaded({required this.settings, this.saving = false});
  final LdapSettings settings;
  final bool saving;

  AdminLdapLoaded copyWith({LdapSettings? settings, bool? saving}) =>
      AdminLdapLoaded(
        settings: settings ?? this.settings,
        saving: saving ?? this.saving,
      );

  @override
  List<Object?> get props => [settings, saving];
}

class AdminLdapCubit extends Cubit<AdminLdapState> {
  AdminLdapCubit(this._repo) : super(const AdminLdapLoading());
  final AdminRepository _repo;

  Future<void> load() async {
    emit(const AdminLdapLoading());
    final res = await _repo.getLdapSettings();
    res.when(
      ok: (s) => emit(AdminLdapLoaded(settings: s)),
      err: (f) => emit(AdminLdapFailed(f)),
    );
  }

  /// Persist the config. Returns the failure on error, or `null` on success.
  Future<AppFailure?> save(UpdateLdapSettingsRequest req) async {
    final cur = state;
    if (cur is AdminLdapLoaded) emit(cur.copyWith(saving: true));
    final res = await _repo.updateLdapSettings(req);
    return res.when(
      ok: (s) {
        emit(AdminLdapLoaded(settings: s));
        return null;
      },
      err: (f) {
        if (cur is AdminLdapLoaded) emit(cur.copyWith(saving: false));
        return f;
      },
    );
  }

  Future<LdapTestResult?> test({
    required UpdateLdapSettingsRequest settings,
    required String username,
    required String password,
  }) async {
    final res = await _repo.testLdapSettings(
      settings: settings,
      username: username,
      password: password,
    );
    return res.valueOrNull;
  }
}
