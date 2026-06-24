import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';
import 'package:intellipilot/features/dashboard/domain/dashboard_repository.dart';

sealed class GlobalDashboardState extends Equatable {
  const GlobalDashboardState();
  @override
  List<Object?> get props => const [];
}

final class GlobalDashboardLoading extends GlobalDashboardState {
  const GlobalDashboardLoading();
}

final class GlobalDashboardLoaded extends GlobalDashboardState {
  const GlobalDashboardLoaded(this.data);
  final HomeDashboard data;
  @override
  List<Object?> get props => [
    data.assignedTotal,
    data.overdue,
    data.dueSoon,
    data.vacationDaysLeft,
    data.byStatus.length,
    data.byProject.length,
    data.attention.length,
  ];
}

final class GlobalDashboardFailed extends GlobalDashboardState {
  const GlobalDashboardFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class GlobalDashboardCubit extends Cubit<GlobalDashboardState> {
  GlobalDashboardCubit(this._repo) : super(const GlobalDashboardLoading());

  final DashboardRepository _repo;

  Future<void> load() async {
    emit(const GlobalDashboardLoading());
    final res = await _repo.getHome();
    emit(
      res.when(
        ok: GlobalDashboardLoaded.new,
        err: GlobalDashboardFailed.new,
      ),
    );
  }
}
