import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

sealed class ProjectsListState extends Equatable {
  const ProjectsListState();
  @override
  List<Object?> get props => const [];
}

final class ProjectsListLoading extends ProjectsListState {
  const ProjectsListLoading();
}

final class ProjectsListLoaded extends ProjectsListState {
  const ProjectsListLoaded({
    required this.projects,
    this.search = '',
    this.creating = false,
    this.lastError,
  });
  final List<Project> projects;
  final String search;
  final bool creating;
  final AppFailure? lastError;

  List<Project> get visible {
    if (search.trim().isEmpty) return projects;
    final q = search.toLowerCase();
    return projects
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.slug.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q),
        )
        .toList();
  }

  ProjectsListLoaded copyWith({
    List<Project>? projects,
    String? search,
    bool? creating,
    AppFailure? lastError,
  }) => ProjectsListLoaded(
    projects: projects ?? this.projects,
    search: search ?? this.search,
    creating: creating ?? this.creating,
    lastError: lastError,
  );

  @override
  List<Object?> get props =>
      [projects.map((p) => p.id).toList(), search, creating, lastError];
}

final class ProjectsListLoadFailed extends ProjectsListState {
  const ProjectsListLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ProjectsListCubit extends Cubit<ProjectsListState> {
  ProjectsListCubit(this._repo) : super(const ProjectsListLoading());
  final ProjectsRepository _repo;

  Future<void> load() async {
    emit(const ProjectsListLoading());
    final res = await _repo.listProjects();
    res.when(
      ok: (list) => emit(ProjectsListLoaded(projects: list)),
      err: (f) => emit(ProjectsListLoadFailed(f)),
    );
  }

  void setSearch(String query) {
    final s = state;
    if (s is ProjectsListLoaded) {
      emit(s.copyWith(search: query, lastError: null));
    }
  }

  /// Returns the new Project on success so callers can navigate to it.
  Future<Project?> create(CreateProjectRequest body) async {
    final s = state;
    if (s is! ProjectsListLoaded) return null;
    emit(s.copyWith(creating: true, lastError: null));
    final res = await _repo.createProject(body);
    return res.when(
      ok: (p) {
        emit(
          ProjectsListLoaded(
            projects: [p, ...s.projects],
            search: s.search,
          ),
        );
        return p;
      },
      err: (f) {
        emit(s.copyWith(creating: false, lastError: f));
        return null;
      },
    );
  }
}
