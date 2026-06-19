// Underscore-prefixed fields read clearer than initializing formals in the
// public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class RepositoriesState extends Equatable {
  const RepositoriesState();
  @override
  List<Object?> get props => const [];
}

final class RepositoriesLoading extends RepositoriesState {
  const RepositoriesLoading();
}

final class RepositoriesLoaded extends RepositoriesState {
  const RepositoriesLoaded({
    required this.repositories,
    this.busy = false,
    this.lastError,
  });
  final List<Repository> repositories;
  final bool busy;
  final AppFailure? lastError;

  RepositoriesLoaded copyWith({
    List<Repository>? repositories,
    bool? busy,
    AppFailure? lastError,
  }) => RepositoriesLoaded(
    repositories: repositories ?? this.repositories,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    repositories.map((r) => r.id).toList(),
    busy,
    lastError,
  ];
}

final class RepositoriesLoadFailed extends RepositoriesState {
  const RepositoriesLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class RepositoriesCubit extends Cubit<RepositoriesState> {
  RepositoriesCubit({required CatalogRepository repo, required this.projectId})
    : _repo = repo,
      super(const RepositoriesLoading());

  final CatalogRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const RepositoriesLoading());
    final res = await _repo.listRepositories(projectId);
    res.when(
      ok: (r) => emit(RepositoriesLoaded(repositories: r)),
      err: (f) => emit(RepositoriesLoadFailed(f)),
    );
  }

  Future<bool> create(CreateRepositoryRequest body) async {
    final s = state;
    if (s is! RepositoriesLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createRepository(projectId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<bool> update(String repositoryId, UpdateRepositoryRequest body) async {
    final s = state;
    if (s is! RepositoriesLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateRepository(projectId, repositoryId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<void> delete(String repositoryId) async {
    final s = state;
    if (s is! RepositoriesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteRepository(projectId, repositoryId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  /// Stateless passthroughs used by dialogs to populate branch pickers.
  Future<Result<RemoteBranches, AppFailure>> previewBranches(
    String sshUrl,
    String sshKeyId,
  ) => _repo.previewBranches(projectId, sshUrl, sshKeyId);

  Future<Result<RemoteBranches, AppFailure>> fetchBranches(
    String repositoryId,
  ) => _repo.repositoryBranches(projectId, repositoryId);
}
