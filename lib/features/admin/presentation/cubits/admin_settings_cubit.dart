import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';

sealed class AdminSettingsState extends Equatable {
  const AdminSettingsState();
  @override
  List<Object?> get props => const [];
}

final class AdminSettingsLoading extends AdminSettingsState {
  const AdminSettingsLoading();
}

final class AdminSettingsLoaded extends AdminSettingsState {
  const AdminSettingsLoaded({required this.settings, this.lastError});

  final PlatformSettings settings;
  final AppFailure? lastError;

  AdminSettingsLoaded copyWith({
    PlatformSettings? settings,
    AppFailure? lastError,
    bool clearError = false,
  }) => AdminSettingsLoaded(
    settings: settings ?? this.settings,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  @override
  List<Object?> get props => [settings, lastError];
}

final class AdminSettingsFailed extends AdminSettingsState {
  const AdminSettingsFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class AdminSettingsCubit extends Cubit<AdminSettingsState> {
  AdminSettingsCubit(this._repo) : super(const AdminSettingsLoading());
  final AdminRepository _repo;

  Future<void> load() async {
    emit(const AdminSettingsLoading());
    final res = await _repo.getSettings();
    res.when(
      ok: (s) => emit(AdminSettingsLoaded(settings: s)),
      err: (f) => emit(AdminSettingsFailed(f)),
    );
  }

  Future<void> setOpenRegistration(bool value) async {
    final res = await _repo.updateOpenRegistration(value);
    res.when(
      ok: (s) => emit(AdminSettingsLoaded(settings: s)),
      err: (f) {
        final cur = state;
        if (cur is AdminSettingsLoaded) {
          emit(cur.copyWith(lastError: f));
        }
      },
    );
  }
}
