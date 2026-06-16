import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';

sealed class AdminNotificationsState extends Equatable {
  const AdminNotificationsState();
  @override
  List<Object?> get props => const [];
}

final class AdminNotificationsLoading extends AdminNotificationsState {
  const AdminNotificationsLoading();
}

final class AdminNotificationsFailed extends AdminNotificationsState {
  const AdminNotificationsFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

final class AdminNotificationsLoaded extends AdminNotificationsState {
  const AdminNotificationsLoaded({required this.settings, this.saving = false});
  final NotificationSettings settings;
  final bool saving;

  AdminNotificationsLoaded copyWith({
    NotificationSettings? settings,
    bool? saving,
  }) => AdminNotificationsLoaded(
    settings: settings ?? this.settings,
    saving: saving ?? this.saving,
  );

  @override
  List<Object?> get props => [settings, saving];
}

class AdminNotificationsCubit extends Cubit<AdminNotificationsState> {
  AdminNotificationsCubit(this._repo)
    : super(const AdminNotificationsLoading());
  final AdminRepository _repo;

  Future<void> load() async {
    emit(const AdminNotificationsLoading());
    final res = await _repo.getNotificationSettings();
    res.when(
      ok: (s) => emit(AdminNotificationsLoaded(settings: s)),
      err: (f) => emit(AdminNotificationsFailed(f)),
    );
  }

  /// Persist config. Returns the failure on error, or `null` on success.
  Future<AppFailure?> save(NotificationSettingsUpdate req) async {
    final cur = state;
    if (cur is AdminNotificationsLoaded) emit(cur.copyWith(saving: true));
    final res = await _repo.updateNotificationSettings(req);
    return res.when(
      ok: (s) {
        emit(AdminNotificationsLoaded(settings: s));
        return null;
      },
      err: (f) {
        if (cur is AdminNotificationsLoaded) emit(cur.copyWith(saving: false));
        return f;
      },
    );
  }

  Future<NotificationTestResult?> test({
    required String channel,
    String? to,
  }) async {
    final res = await _repo.testNotification(channel: channel, to: to);
    return res.valueOrNull;
  }
}
