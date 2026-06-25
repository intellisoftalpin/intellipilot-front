// `_repo` / `_catalog` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

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
    this.milestones = const [],
    this.milestoneFilter,
    this.busy = false,
    this.lastError,
  });

  final List<Epic> epics;

  /// `issue_status` taxonomy items — epics share the issue status taxonomy.
  final List<TaxonomyItem> statuses;

  /// Project milestones, for the filter dropdown.
  final List<Milestone> milestones;

  /// Selected milestone id to filter by; `null` shows all epics.
  final String? milestoneFilter;
  final bool busy;
  final AppFailure? lastError;

  /// Epics after applying the milestone filter (the board / breadcrumb count
  /// operate on this set).
  List<Epic> get visibleEpics => milestoneFilter == null
      ? epics
      : epics.where((e) => e.milestoneId == milestoneFilter).toList();

  EpicsLoaded copyWith({
    List<Epic>? epics,
    List<TaxonomyItem>? statuses,
    List<Milestone>? milestones,
    bool? busy,
    AppFailure? lastError,
  }) => EpicsLoaded(
    epics: epics ?? this.epics,
    statuses: statuses ?? this.statuses,
    milestones: milestones ?? this.milestones,
    milestoneFilter: milestoneFilter,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    epics
        .map((e) => '${e.id}:${e.version}:${e.statusId}:${e.milestoneId}')
        .toList(),
    statuses.map((s) => s.id).toList(),
    milestones.map((m) => m.id).toList(),
    milestoneFilter,
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
    required MilestonesRepository milestones,
    required this.projectId,
  }) : _repo = repo,
       _catalog = catalog,
       _milestones = milestones,
       super(const EpicsLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final MilestonesRepository _milestones;
  final String projectId;

  Future<void> load() async {
    // Preserve the milestone filter across reloads (create/update/delete all
    // reload), so an in-progress filter survives an edit.
    final prevFilter = state is EpicsLoaded
        ? (state as EpicsLoaded).milestoneFilter
        : null;
    if (!isClosed) emit(const EpicsLoading());
    final epicsRes = await _repo.listEpics(projectId);
    final statusRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueStatus,
    );
    final milestonesRes = await _milestones.list(projectId);
    final epics = epicsRes.valueOrNull;
    if (epics == null) {
      if (!isClosed) emit(const EpicsFailed());
      return;
    }
    epics.sort((a, b) => a.reference.compareTo(b.reference));
    final milestones = milestonesRes.valueOrNull ?? const <Milestone>[];
    // Drop a stale filter if its milestone no longer exists.
    final filter = milestones.any((m) => m.id == prevFilter)
        ? prevFilter
        : null;
    if (!isClosed) {
      emit(
        EpicsLoaded(
          epics: epics,
          statuses: statusRes.valueOrNull ?? const [],
          milestones: milestones,
          milestoneFilter: filter,
        ),
      );
    }
  }

  /// Handle a board drag-and-drop: move [epic] into a column (setting
  /// [newStatusId] — null for "All", a closed status for "Done", the mapped
  /// status for "In Progress") and reorder it between [afterId] and [beforeId].
  /// The status PATCH (etag-guarded) runs first so history is recorded, then
  /// the fractional reorder, then a single reload.
  Future<void> dropEpic({
    required Epic epic,
    required Object? newStatusId,
    String? beforeId,
    String? afterId,
  }) async {
    final s = state;
    if (s is! EpicsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    if (epic.statusId != newStatusId) {
      final got = await _repo.getEpic(projectId, epic.id);
      final fresh = got.valueOrNull;
      if (fresh?.etag != null) {
        final res = await _repo.updateEpic(
          projectId,
          epic.id,
          body: UpdateEpicRequest(statusId: newStatusId),
          etag: fresh!.etag!,
        );
        if (res.isErr) {
          emit(s.copyWith(busy: false, lastError: res.failureOrNull));
          await load();
          return;
        }
      }
    }
    if (beforeId != null || afterId != null) {
      await _repo.moveEpic(
        projectId,
        epic.id,
        ReorderRequest(beforeId: beforeId, afterId: afterId),
      );
    }
    await load();
  }

  /// Set (or clear, with `null`) the milestone filter.
  void setMilestoneFilter(String? milestoneId) {
    final s = state;
    if (s is! EpicsLoaded) return;
    emit(
      EpicsLoaded(
        epics: s.epics,
        statuses: s.statuses,
        milestones: s.milestones,
        milestoneFilter: milestoneId,
        busy: s.busy,
        lastError: s.lastError,
      ),
    );
  }

  /// Create an epic and reload. Returns the created epic (so the caller can
  /// immediately open its sidebar), or null on failure.
  Future<Epic?> createEpic(CreateEpicRequest body) async {
    final s = state;
    if (s is! EpicsLoaded) return null;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createEpic(projectId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return null;
    }
    await load();
    return res.valueOrNull;
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
