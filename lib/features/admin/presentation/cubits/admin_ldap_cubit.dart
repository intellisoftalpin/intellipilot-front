import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

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
  const AdminLdapLoaded({
    required this.settings,
    this.saving = false,
    this.currentUserIsLdap = false,
  });
  final LdapSettings settings;
  final bool saving;

  /// The signed-in superadmin authenticates via LDAP — the LDAP settings are
  /// then read-only (they can't change them and risk locking themselves out).
  final bool currentUserIsLdap;

  AdminLdapLoaded copyWith({
    LdapSettings? settings,
    bool? saving,
    bool? currentUserIsLdap,
  }) => AdminLdapLoaded(
    settings: settings ?? this.settings,
    saving: saving ?? this.saving,
    currentUserIsLdap: currentUserIsLdap ?? this.currentUserIsLdap,
  );

  @override
  List<Object?> get props => [settings, saving, currentUserIsLdap];
}

class AdminLdapCubit extends Cubit<AdminLdapState> {
  AdminLdapCubit(this._repo, this._profile) : super(const AdminLdapLoading());
  final AdminRepository _repo;
  final ProfileRepository _profile;

  Future<void> load() async {
    emit(const AdminLdapLoading());
    final res = await _repo.getLdapSettings();
    // Read-only when the current superadmin signed in via LDAP. Best-effort:
    // default to editable if the profile can't be read (backend still guards).
    final me = await _profile.getProfile();
    final isLdap = me.valueOrNull?.isLdap ?? false;
    res.when(
      ok: (s) => emit(AdminLdapLoaded(settings: s, currentUserIsLdap: isLdap)),
      err: (f) => emit(AdminLdapFailed(f)),
    );
  }

  /// Persist the config. Returns the failure on error, or `null` on success.
  Future<AppFailure?> save(UpdateLdapSettingsRequest req) async {
    final cur = state;
    if (cur is AdminLdapLoaded) emit(cur.copyWith(saving: true));
    final res = await _repo.updateLdapSettings(req);
    final wasLdap = cur is AdminLdapLoaded && cur.currentUserIsLdap;
    return res.when(
      ok: (s) {
        emit(AdminLdapLoaded(settings: s, currentUserIsLdap: wasLdap));
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
