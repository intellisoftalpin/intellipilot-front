// Underscore-prefixed fields read clearer than initializing formals in the
// public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class ComponentReleasesState extends Equatable {
  const ComponentReleasesState();
  @override
  List<Object?> get props => const [];
}

final class ComponentReleasesLoading extends ComponentReleasesState {
  const ComponentReleasesLoading();
}

final class ComponentReleasesLoaded extends ComponentReleasesState {
  const ComponentReleasesLoaded({
    required this.links,
    this.busy = false,
    this.lastError,
  });
  final List<ComponentReleaseLink> links;
  final bool busy;
  final AppFailure? lastError;

  ComponentReleasesLoaded copyWith({
    List<ComponentReleaseLink>? links,
    bool? busy,
    AppFailure? lastError,
  }) => ComponentReleasesLoaded(
    links: links ?? this.links,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    links.map((l) => l.releaseId).toList(),
    busy,
    lastError,
  ];
}

final class ComponentReleasesLoadFailed extends ComponentReleasesState {
  const ComponentReleasesLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ComponentReleasesCubit extends Cubit<ComponentReleasesState> {
  ComponentReleasesCubit({
    required CatalogRepository repo,
    required this.projectId,
    required this.componentId,
  }) : _repo = repo,
       super(const ComponentReleasesLoading());

  final CatalogRepository _repo;
  final String projectId;
  final String componentId;

  Future<void> load() async {
    emit(const ComponentReleasesLoading());
    final res = await _repo.listComponentReleases(projectId, componentId);
    res.when(
      ok: (l) => emit(ComponentReleasesLoaded(links: l)),
      err: (f) => emit(ComponentReleasesLoadFailed(f)),
    );
  }

  Future<bool> link(String releaseId) async {
    final s = state;
    if (s is! ComponentReleasesLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.linkComponentRelease(
      projectId,
      componentId,
      releaseId,
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<void> unlink(String releaseId) async {
    final s = state;
    if (s is! ComponentReleasesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.unlinkComponentRelease(
      projectId,
      componentId,
      releaseId,
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
