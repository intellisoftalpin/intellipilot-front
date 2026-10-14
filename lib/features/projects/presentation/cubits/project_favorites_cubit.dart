import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

class ProjectFavoritesState extends Equatable {
  const ProjectFavoritesState({
    this.ids = const [],
    this.loaded = false,
    this.saveFailed = 0,
  });

  /// Starred project ids, in the order they were starred.
  final List<String> ids;

  /// Whether [ids] came from the server at least once this session.
  final bool loaded;

  /// Bumped on every failed save, so listeners can show one message per
  /// failure.
  final int saveFailed;

  bool contains(String projectId) => ids.contains(projectId);

  bool get isFull => ids.length >= maxFavoriteProjects;

  ProjectFavoritesState copyWith({
    List<String>? ids,
    bool? loaded,
    int? saveFailed,
  }) => ProjectFavoritesState(
    ids: ids ?? this.ids,
    loaded: loaded ?? this.loaded,
    saveFailed: saveFailed ?? this.saveFailed,
  );

  @override
  List<Object?> get props => [ids, loaded, saveFailed];
}

/// The user's starred projects, shared app-wide so the projects screen and
/// the top-bar projects menu always agree. Toggles apply at once and roll
/// back if the server rejects them.
class ProjectFavoritesCubit extends Cubit<ProjectFavoritesState> {
  ProjectFavoritesCubit(this._repo) : super(const ProjectFavoritesState());
  final ProjectsRepository _repo;

  Future<void> load() async {
    final res = await _repo.listFavoriteProjectIds();
    if (isClosed) return;
    res.when(
      ok: (ids) => emit(state.copyWith(ids: ids, loaded: true)),
      // Keep whatever was shown; a failed read only hides the stars' state.
      err: (_) {},
    );
  }

  /// Star or unstar [projectId]. Starring past the cap is ignored — the UI
  /// disables it.
  Future<void> toggle(String projectId) async {
    final before = state.ids;
    final List<String> next;
    if (before.contains(projectId)) {
      next = [...before]..remove(projectId);
    } else {
      if (state.isFull) return;
      next = [...before, projectId];
    }
    emit(state.copyWith(ids: next));
    final res = await _repo.setFavoriteProjectIds(next);
    if (isClosed) return;
    res.when(
      ok: (ids) => emit(state.copyWith(ids: ids, loaded: true)),
      err: (_) =>
          emit(state.copyWith(ids: before, saveFailed: state.saveFailed + 1)),
    );
  }

  /// Forget the set — the session that read it has ended.
  void clear() => emit(const ProjectFavoritesState());
}
