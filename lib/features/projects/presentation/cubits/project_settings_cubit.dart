// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

sealed class ProjectSettingsState extends Equatable {
  const ProjectSettingsState();
  @override
  List<Object?> get props => const [];
}

final class ProjectSettingsIdle extends ProjectSettingsState {
  const ProjectSettingsIdle();
}

final class ProjectSettingsSaving extends ProjectSettingsState {
  const ProjectSettingsSaving();
}

final class ProjectSettingsSaved extends ProjectSettingsState {
  const ProjectSettingsSaved(this.project);
  final Project project;
  @override
  List<Object?> get props => [project.id];
}

final class ProjectSettingsDeleting extends ProjectSettingsState {
  const ProjectSettingsDeleting();
}

final class ProjectSettingsDeleted extends ProjectSettingsState {
  const ProjectSettingsDeleted();
}

final class ProjectSettingsFailed extends ProjectSettingsState {
  const ProjectSettingsFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ProjectSettingsCubit extends Cubit<ProjectSettingsState> {
  ProjectSettingsCubit({
    required ProjectsRepository repo,
    required this.projectId,
  }) : _repo = repo,
       super(const ProjectSettingsIdle());

  final ProjectsRepository _repo;
  final String projectId;

  Future<Project?> save(UpdateProjectRequest patch) async {
    emit(const ProjectSettingsSaving());
    final res = await _repo.updateProject(projectId, patch);
    return res.when(
      ok: (p) {
        emit(ProjectSettingsSaved(p));
        return p;
      },
      err: (f) {
        emit(ProjectSettingsFailed(f));
        return null;
      },
    );
  }

  Future<bool> deleteWithConfirmation({
    required String typedConfirmation,
    required String expectedName,
  }) async {
    if (typedConfirmation.trim() != expectedName) {
      emit(
        const ProjectSettingsFailed(ValidationFailure(fieldErrors: [])),
      );
      return false;
    }
    emit(const ProjectSettingsDeleting());
    final res = await _repo.deleteProject(projectId);
    return res.when(
      ok: (_) {
        emit(const ProjectSettingsDeleted());
        return true;
      },
      err: (f) {
        emit(ProjectSettingsFailed(f));
        return false;
      },
    );
  }

  void reset() => emit(const ProjectSettingsIdle());
}
