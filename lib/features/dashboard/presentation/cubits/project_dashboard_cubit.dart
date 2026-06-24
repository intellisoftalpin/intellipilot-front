// Underscore-prefixed `_repo` is clearer than the public name in this cubit.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';
import 'package:intellipilot/features/dashboard/domain/dashboard_repository.dart';

sealed class ProjectDashboardState extends Equatable {
  const ProjectDashboardState();
  @override
  List<Object?> get props => const [];
}

final class ProjectDashboardLoading extends ProjectDashboardState {
  const ProjectDashboardLoading();
}

final class ProjectDashboardLoaded extends ProjectDashboardState {
  const ProjectDashboardLoaded(this.data);
  final ProjectDashboard data;
  @override
  List<Object?> get props => [
    data.total,
    data.open,
    data.overdue,
    data.unassigned,
    data.bugsOpen,
    data.myAssigned,
    data.myOverdue,
    data.byStatus.length,
    data.epics.length,
    data.throughput.length,
  ];
}

final class ProjectDashboardFailed extends ProjectDashboardState {
  const ProjectDashboardFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ProjectDashboardCubit extends Cubit<ProjectDashboardState> {
  ProjectDashboardCubit({
    required DashboardRepository repo,
    required this.projectId,
  }) : _repo = repo,
       super(const ProjectDashboardLoading());

  final DashboardRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const ProjectDashboardLoading());
    final res = await _repo.getProject(projectId);
    emit(
      res.when(
        ok: ProjectDashboardLoaded.new,
        err: ProjectDashboardFailed.new,
      ),
    );
  }
}
