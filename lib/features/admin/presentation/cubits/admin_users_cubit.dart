import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';

sealed class AdminUsersState extends Equatable {
  const AdminUsersState();
  @override
  List<Object?> get props => const [];
}

final class AdminUsersLoading extends AdminUsersState {
  const AdminUsersLoading();
}

final class AdminUsersLoaded extends AdminUsersState {
  const AdminUsersLoaded({
    required this.items,
    required this.total,
    this.lastError,
  });

  final List<UserProfile> items;
  final int total;
  final AppFailure? lastError;

  AdminUsersLoaded copyWith({
    List<UserProfile>? items,
    int? total,
    AppFailure? lastError,
    bool clearError = false,
  }) => AdminUsersLoaded(
    items: items ?? this.items,
    total: total ?? this.total,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  @override
  List<Object?> get props => [items, total, lastError];
}

final class AdminUsersFailed extends AdminUsersState {
  const AdminUsersFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class AdminUsersCubit extends Cubit<AdminUsersState> {
  AdminUsersCubit(this._repo) : super(const AdminUsersLoading());
  final AdminRepository _repo;

  String _q = '';

  Future<void> load({String? q}) async {
    if (q != null) _q = q;
    emit(const AdminUsersLoading());
    final res = await _repo.listUsers(q: _q.isEmpty ? null : _q, limit: 200);
    res.when(
      ok: (l) => emit(AdminUsersLoaded(items: l.items, total: l.total)),
      err: (f) => emit(AdminUsersFailed(f)),
    );
  }

  Future<UserProfile?> patch(String id, UpdateUserRequest patch) async {
    final current = state;
    final res = await _repo.updateUser(id, patch);
    return res.when(
      ok: (u) {
        if (current is AdminUsersLoaded) {
          final updated = [
            for (final x in current.items) if (x.id == u.id) u else x,
          ];
          emit(current.copyWith(items: updated, clearError: true));
        }
        return u;
      },
      err: (f) {
        if (current is AdminUsersLoaded) {
          emit(current.copyWith(lastError: f));
        }
        return null;
      },
    );
  }

  Future<bool> remove(String id) async {
    final current = state;
    final res = await _repo.deleteUser(id);
    return res.when(
      ok: (_) {
        if (current is AdminUsersLoaded) {
          emit(
            current.copyWith(
              items: current.items.where((u) => u.id != id).toList(),
              total: current.total - 1,
              clearError: true,
            ),
          );
        }
        return true;
      },
      err: (f) {
        if (current is AdminUsersLoaded) {
          emit(current.copyWith(lastError: f));
        }
        return false;
      },
    );
  }

  Future<CreateUserResponse?> create(CreateUserRequest body) async {
    final res = await _repo.createUser(body);
    return res.when(
      ok: (r) {
        final current = state;
        if (current is AdminUsersLoaded) {
          emit(
            current.copyWith(
              items: [r.user, ...current.items],
              total: current.total + 1,
              clearError: true,
            ),
          );
        }
        return r;
      },
      err: (f) {
        final current = state;
        if (current is AdminUsersLoaded) {
          emit(current.copyWith(lastError: f));
        }
        return null;
      },
    );
  }

  Future<PasswordResetIssued?> resetPasswordFor(String id) async {
    final res = await _repo.resetPassword(id);
    return res.when(ok: (r) => r, err: (_) => null);
  }
}
