// Underscore-prefixed fields read clearer than initializing formals in the
// public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class ReleasesState extends Equatable {
  const ReleasesState();
  @override
  List<Object?> get props => const [];
}

final class ReleasesLoading extends ReleasesState {
  const ReleasesLoading();
}

final class ReleasesLoaded extends ReleasesState {
  const ReleasesLoaded({
    required this.releases,
    this.versionsByRelease = const {},
    this.busy = false,
    this.lastError,
  });
  final List<Release> releases;

  /// Versions per release id; populated lazily when a release is expanded.
  final Map<String, List<ReleaseVersion>> versionsByRelease;
  final bool busy;
  final AppFailure? lastError;

  ReleasesLoaded copyWith({
    List<Release>? releases,
    Map<String, List<ReleaseVersion>>? versionsByRelease,
    bool? busy,
    AppFailure? lastError,
  }) => ReleasesLoaded(
    releases: releases ?? this.releases,
    versionsByRelease: versionsByRelease ?? this.versionsByRelease,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    releases.map((r) => r.id).toList(),
    {
      for (final e in versionsByRelease.entries)
        e.key: e.value.map((v) => '${v.id}:${v.version}').toList(),
    },
    busy,
    lastError,
  ];
}

final class ReleasesLoadFailed extends ReleasesState {
  const ReleasesLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ReleasesCubit extends Cubit<ReleasesState> {
  ReleasesCubit({required CatalogRepository repo, required this.projectId})
    : _repo = repo,
      super(const ReleasesLoading());

  final CatalogRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const ReleasesLoading());
    final res = await _repo.listReleases(projectId);
    res.when(
      ok: (r) => emit(ReleasesLoaded(releases: r)),
      err: (f) => emit(ReleasesLoadFailed(f)),
    );
  }

  Future<void> loadVersions(String releaseId) async {
    final s = state;
    if (s is! ReleasesLoaded) return;
    final res = await _repo.listReleaseVersions(projectId, releaseId);
    final list = res.valueOrNull;
    if (list == null) {
      emit(s.copyWith(lastError: res.failureOrNull));
      return;
    }
    emit(
      s.copyWith(
        versionsByRelease: {...s.versionsByRelease, releaseId: list},
      ),
    );
  }

  Future<bool> create(CreateReleaseRequest body) async {
    final s = state;
    if (s is! ReleasesLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createRelease(projectId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<bool> update(String releaseId, UpdateReleaseRequest body) async {
    final s = state;
    if (s is! ReleasesLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateRelease(projectId, releaseId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<void> delete(String releaseId) async {
    final s = state;
    if (s is! ReleasesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteRelease(projectId, releaseId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<bool> createVersion(
    String releaseId,
    CreateReleaseVersionRequest body,
  ) async {
    final s = state;
    if (s is! ReleasesLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createReleaseVersion(projectId, releaseId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    emit(s.copyWith(busy: false));
    await loadVersions(releaseId);
    return true;
  }

  Future<bool> updateVersion(
    String releaseId,
    String versionId,
    UpdateReleaseVersionRequest body,
  ) async {
    final s = state;
    if (s is! ReleasesLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateReleaseVersion(
      projectId,
      releaseId,
      versionId,
      body,
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    emit(s.copyWith(busy: false));
    await loadVersions(releaseId);
    return true;
  }

  Future<void> deleteVersion(String releaseId, String versionId) async {
    final s = state;
    if (s is! ReleasesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteReleaseVersion(
      projectId,
      releaseId,
      versionId,
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    emit(s.copyWith(busy: false));
    await loadVersions(releaseId);
  }
}
