import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/security_dtos.dart';
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
    this.statusFilter,
    this.lastError,
  });

  final List<AdminUserRow> items;
  final int total;

  /// Active filter chip: `active`, `inactive`, `banned`, `no_2fa`, or null for
  /// all.
  final String? statusFilter;
  final AppFailure? lastError;

  AdminUsersLoaded copyWith({
    List<AdminUserRow>? items,
    int? total,
    String? statusFilter,
    AppFailure? lastError,
    bool clearError = false,
  }) => AdminUsersLoaded(
    items: items ?? this.items,
    total: total ?? this.total,
    statusFilter: statusFilter ?? this.statusFilter,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  @override
  List<Object?> get props => [items, total, statusFilter, lastError];
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
  String? _status;

  /// Reloads the list. Pass [clearStatus] to drop the status filter entirely —
  /// a null [status] means "unchanged", not "all".
  Future<void> load({
    String? q,
    String? status,
    bool clearStatus = false,
  }) async {
    if (q != null) _q = q;
    if (clearStatus) {
      _status = null;
    } else if (status != null) {
      _status = status;
    }
    emit(const AdminUsersLoading());
    final res = await _repo.listUsers(
      q: _q.isEmpty ? null : _q,
      status: _status,
      limit: 200,
    );
    res.when(
      ok: (l) {
        String key(AdminUserRow u) =>
            (u.user.fullName.isNotEmpty ? u.user.fullName : u.user.username)
                .toLowerCase();
        final sorted = l.items.toList()
          ..sort((a, b) => key(a).compareTo(key(b)));
        emit(
          AdminUsersLoaded(
            items: sorted,
            total: l.total,
            statusFilter: _status,
          ),
        );
      },
      err: (f) => emit(AdminUsersFailed(f)),
    );
  }

  Future<UserProfile?> patch(String id, UpdateUserRequest patch) async {
    final current = state;
    final res = await _repo.updateUser(id, patch);
    return res.when(
      ok: (u) {
        _replaceUser(current, u);
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

  /// Swap in an updated [UserProfile] while keeping the row's security fields.
  ///
  /// The ban/unban and patch endpoints return the plain user, not the enriched
  /// admin row, so the surrounding security data has to be preserved rather
  /// than dropped. Ban state is derived locally so the row reflects the change
  /// immediately; a later reload re-reads it from the server.
  void _replaceUser(AdminUsersState current, UserProfile u, {bool? banned}) {
    if (current is! AdminUsersLoaded) return;
    final updated = [
      for (final row in current.items)
        if (row.id == u.id)
          AdminUserRow(
            user: u,
            status: banned == null
                ? (u.isActive ? 'active' : 'inactive')
                : (banned ? 'banned' : (u.isActive ? 'active' : 'inactive')),
            twoFactor: row.twoFactor,
            activeSessions: banned ?? false ? 0 : row.activeSessions,
            lastSession: row.lastSession,
            lastSeenAt: row.lastSeenAt,
            lastLoginAt: row.lastLoginAt,
            bannedAt: banned == null
                ? row.bannedAt
                : (banned ? DateTime.now().toUtc() : null),
            banReason: banned == null
                ? row.banReason
                : (banned ? row.banReason : null),
          )
        else
          row,
    ];
    emit(current.copyWith(items: updated, clearError: true));
  }

  /// Clears every second factor and signs the user out everywhere.
  Future<TwoFactorResetResult?> resetTwoFactor(String id) async {
    final current = state;
    final res = await _repo.resetTwoFactor(id);
    return res.when(
      ok: (r) {
        if (current is AdminUsersLoaded) {
          final updated = [
            for (final row in current.items)
              if (row.id == id)
                AdminUserRow(
                  user: row.user,
                  status: row.status,
                  twoFactor: const TwoFactorStatus(),
                  lastSeenAt: row.lastSeenAt,
                  lastLoginAt: row.lastLoginAt,
                  bannedAt: row.bannedAt,
                  banReason: row.banReason,
                )
              else
                row,
          ];
          emit(current.copyWith(items: updated, clearError: true));
        }
        return r;
      },
      err: (f) {
        if (current is AdminUsersLoaded) {
          emit(current.copyWith(lastError: f));
        }
        return null;
      },
    );
  }

  Future<bool> ban(String id, {String? reason}) async {
    final current = state;
    final res = await _repo.banUser(id, reason: reason);
    return res.when(
      ok: (u) {
        _replaceUser(current, u, banned: true);
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

  Future<bool> unban(String id) async {
    final current = state;
    final res = await _repo.unbanUser(id);
    return res.when(
      ok: (u) {
        _replaceUser(current, u, banned: false);
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

  Future<int?> revokeSessions(String id) async {
    final current = state;
    final res = await _repo.revokeUserSessions(id);
    return res.when(
      ok: (n) {
        if (current is AdminUsersLoaded) {
          final updated = [
            for (final row in current.items)
              if (row.id == id)
                AdminUserRow(
                  user: row.user,
                  status: row.status,
                  twoFactor: row.twoFactor,
                  lastSeenAt: row.lastSeenAt,
                  lastLoginAt: row.lastLoginAt,
                  bannedAt: row.bannedAt,
                  banReason: row.banReason,
                )
              else
                row,
          ];
          emit(current.copyWith(items: updated, clearError: true));
        }
        return n;
      },
      err: (f) {
        if (current is AdminUsersLoaded) {
          emit(current.copyWith(lastError: f));
        }
        return null;
      },
    );
  }

  Future<List<SessionInfo>?> sessionsFor(String id) async {
    final res = await _repo.listUserSessions(id);
    return res.when(ok: (s) => s, err: (_) => null);
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
          // A brand-new account: no factors, no sessions, never logged in.
          final row = AdminUserRow(
            user: r.user,
            status: r.user.isActive ? 'active' : 'inactive',
            twoFactor: const TwoFactorStatus(),
          );
          emit(
            current.copyWith(
              items: [row, ...current.items],
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
