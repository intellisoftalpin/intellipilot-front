import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';

sealed class AdminInvitationsState extends Equatable {
  const AdminInvitationsState();
  @override
  List<Object?> get props => const [];
}

final class AdminInvitationsLoading extends AdminInvitationsState {
  const AdminInvitationsLoading();
}

final class AdminInvitationsLoaded extends AdminInvitationsState {
  const AdminInvitationsLoaded({
    required this.items,
    this.lastCreated,
    this.lastError,
  });

  final List<PendingInvitation> items;
  /// Last invitation issued in this session — we keep it so the UI can show
  /// the dev token even after the list refreshes.
  final CreateInvitationResponse? lastCreated;
  final AppFailure? lastError;

  AdminInvitationsLoaded copyWith({
    List<PendingInvitation>? items,
    CreateInvitationResponse? lastCreated,
    AppFailure? lastError,
    bool clearError = false,
    bool clearLastCreated = false,
  }) => AdminInvitationsLoaded(
    items: items ?? this.items,
    lastCreated: clearLastCreated ? null : (lastCreated ?? this.lastCreated),
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  @override
  List<Object?> get props => [items, lastCreated, lastError];
}

final class AdminInvitationsFailed extends AdminInvitationsState {
  const AdminInvitationsFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class AdminInvitationsCubit extends Cubit<AdminInvitationsState> {
  AdminInvitationsCubit(this._repo) : super(const AdminInvitationsLoading());
  final AdminRepository _repo;

  Future<void> load() async {
    final prev = state;
    emit(const AdminInvitationsLoading());
    final res = await _repo.listInvitations();
    res.when(
      ok: (items) => emit(
        AdminInvitationsLoaded(
          items: items,
          lastCreated: prev is AdminInvitationsLoaded ? prev.lastCreated : null,
        ),
      ),
      err: (f) => emit(AdminInvitationsFailed(f)),
    );
  }

  Future<CreateInvitationResponse?> create(String email, String role) async {
    final res = await _repo.createInvitation(
      CreateInvitationRequest(email: email, role: role),
    );
    return res.when(
      ok: (created) {
        final cur = state;
        if (cur is AdminInvitationsLoaded) {
          emit(cur.copyWith(lastCreated: created, clearError: true));
        }
        // Refresh listing in background.
        unawaited(load());
        return created;
      },
      err: (f) {
        final cur = state;
        if (cur is AdminInvitationsLoaded) {
          emit(cur.copyWith(lastError: f));
        }
        return null;
      },
    );
  }

  Future<bool> revoke(String id) async {
    final res = await _repo.revokeInvitation(id);
    return res.when(
      ok: (_) {
        final cur = state;
        if (cur is AdminInvitationsLoaded) {
          emit(
            cur.copyWith(
              items: cur.items.where((i) => i.id != id).toList(),
              clearError: true,
            ),
          );
        }
        return true;
      },
      err: (f) {
        final cur = state;
        if (cur is AdminInvitationsLoaded) {
          emit(cur.copyWith(lastError: f));
        }
        return false;
      },
    );
  }
}

void unawaited(Future<void> _) {}
