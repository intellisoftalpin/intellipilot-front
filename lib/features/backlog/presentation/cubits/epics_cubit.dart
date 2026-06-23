// `_repo` / `_catalog` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class EpicsState extends Equatable {
  const EpicsState();
  @override
  List<Object?> get props => [];
}

class EpicsLoading extends EpicsState {
  const EpicsLoading();
}

class EpicsFailed extends EpicsState {
  const EpicsFailed();
}

class EpicsLoaded extends EpicsState {
  const EpicsLoaded({
    required this.epics,
    required this.statuses,
    this.busy = false,
    this.lastError,
  });

  final List<Epic> epics;

  /// `issue_status` taxonomy items — epics share the issue status taxonomy.
  final List<TaxonomyItem> statuses;
  final bool busy;
  final AppFailure? lastError;

  EpicsLoaded copyWith({
    List<Epic>? epics,
    List<TaxonomyItem>? statuses,
    bool? busy,
    AppFailure? lastError,
  }) => EpicsLoaded(
    epics: epics ?? this.epics,
    statuses: statuses ?? this.statuses,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    epics.map((e) => e.id).toList(),
    statuses.map((s) => s.id).toList(),
    busy,
    lastError,
  ];
}

/// Standalone CRUD for the project Epics page. Mirrors the etag-aware
/// create/update/delete flow used by the backlog, but scoped to epics only.
class EpicsCubit extends Cubit<EpicsState> {
  EpicsCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required this.projectId,
  }) : _repo = repo,
       _catalog = catalog,
       super(const EpicsLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final String projectId;

  Future<void> load() async {
    if (!isClosed) emit(const EpicsLoading());
    final epicsRes = await _repo.listEpics(projectId);
    final statusRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueStatus,
    );
    final epics = epicsRes.valueOrNull;
    if (epics == null) {
      if (!isClosed) emit(const EpicsFailed());
      return;
    }
    epics.sort((a, b) => a.reference.compareTo(b.reference));
    if (!isClosed) {
      emit(
        EpicsLoaded(epics: epics, statuses: statusRes.valueOrNull ?? const []),
      );
    }
  }

  Future<void> createEpic(CreateEpicRequest body) async {
    final s = state;
    if (s is! EpicsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createEpic(projectId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> updateEpic(String id, UpdateEpicRequest body) async {
    final s = state;
    if (s is! EpicsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getEpic(projectId, id);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.updateEpic(
      projectId,
      id,
      body: body,
      etag: fresh.etag ?? '',
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> deleteEpic(String id) async {
    final s = state;
    if (s is! EpicsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getEpic(projectId, id);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.deleteEpic(projectId, id, etag: fresh.etag ?? '');
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
