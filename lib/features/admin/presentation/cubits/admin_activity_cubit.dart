import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';

sealed class AdminActivityState extends Equatable {
  const AdminActivityState();
  @override
  List<Object?> get props => const [];
}

final class AdminActivityLoading extends AdminActivityState {
  const AdminActivityLoading();
}

final class AdminActivityLoaded extends AdminActivityState {
  const AdminActivityLoaded({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
    this.actionFilter,
  });

  final List<ActivityEvent> items;
  final int total;
  final int offset;
  final int limit;

  /// Currently applied `action` filter, or null for "All".
  final String? actionFilter;

  @override
  List<Object?> get props => [items, total, offset, limit, actionFilter];
}

final class AdminActivityFailed extends AdminActivityState {
  const AdminActivityFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class AdminActivityCubit extends Cubit<AdminActivityState> {
  AdminActivityCubit(this._repo) : super(const AdminActivityLoading());
  final AdminRepository _repo;

  static const _pageSize = 100;

  String? _action;

  Future<void> load() async {
    emit(const AdminActivityLoading());
    final res = await _repo.listActivity(action: _action, limit: _pageSize);
    res.when(
      ok: (l) => emit(
        AdminActivityLoaded(
          items: l.items,
          total: l.total,
          offset: l.offset,
          limit: l.limit,
          actionFilter: _action,
        ),
      ),
      err: (f) => emit(AdminActivityFailed(f)),
    );
  }

  /// Re-query with a new action filter (null = "All").
  Future<void> setFilter(String? action) async {
    _action = (action == null || action.isEmpty) ? null : action;
    await load();
  }
}
