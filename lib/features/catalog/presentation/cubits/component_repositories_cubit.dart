// Underscore-prefixed fields read clearer than initializing formals in the
// public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class ComponentReposState extends Equatable {
  const ComponentReposState();
  @override
  List<Object?> get props => const [];
}

final class ComponentReposLoading extends ComponentReposState {
  const ComponentReposLoading();
}

final class ComponentReposLoaded extends ComponentReposState {
  const ComponentReposLoaded({
    required this.links,
    this.busy = false,
    this.lastError,
  });
  final List<ComponentRepositoryLink> links;
  final bool busy;
  final AppFailure? lastError;

  ComponentReposLoaded copyWith({
    List<ComponentRepositoryLink>? links,
    bool? busy,
    AppFailure? lastError,
  }) => ComponentReposLoaded(
    links: links ?? this.links,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    links.map((l) => '${l.repositoryId}:${l.branch}').toList(),
    busy,
    lastError,
  ];
}

final class ComponentReposLoadFailed extends ComponentReposState {
  const ComponentReposLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ComponentReposCubit extends Cubit<ComponentReposState> {
  ComponentReposCubit({
    required CatalogRepository repo,
    required this.projectId,
    required this.componentId,
  }) : _repo = repo,
       super(const ComponentReposLoading());

  final CatalogRepository _repo;
  final String projectId;
  final String componentId;

  Future<void> load() async {
    emit(const ComponentReposLoading());
    final res = await _repo.listComponentRepositories(projectId, componentId);
    res.when(
      ok: (l) => emit(ComponentReposLoaded(links: l)),
      err: (f) => emit(ComponentReposLoadFailed(f)),
    );
  }

  Future<bool> link(String repositoryId, String branch) async {
    final s = state;
    if (s is! ComponentReposLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.linkComponentRepository(
      projectId,
      componentId,
      repositoryId,
      branch,
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<bool> updateBranch(String repositoryId, String branch) async {
    final s = state;
    if (s is! ComponentReposLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateComponentRepositoryBranch(
      projectId,
      componentId,
      repositoryId,
      branch,
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<void> unlink(String repositoryId) async {
    final s = state;
    if (s is! ComponentReposLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.unlinkComponentRepository(
      projectId,
      componentId,
      repositoryId,
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
