// `_repo` / `_catalog` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

sealed class TaskBoardState extends Equatable {
  const TaskBoardState();
  @override
  List<Object?> get props => [];
}

class TaskBoardLoading extends TaskBoardState {
  const TaskBoardLoading();
}

class TaskBoardFailed extends TaskBoardState {
  const TaskBoardFailed();
}

class TaskBoardLoaded extends TaskBoardState {
  const TaskBoardLoaded({
    required this.statuses,
    required this.issues,
    required this.milestones,
    this.types = const [],
    this.priorities = const [],
    this.sizes = const [],
    this.epics = const [],
    this.labels = const [],
    this.components = const [],
    this.filter = const WorkItemFilter(),
    this.staleData = false,
  });

  /// The `issue_status` taxonomy items, ordered — these are the board columns.
  final List<TaxonomyItem> statuses;

  /// All issues for the project.
  final List<Issue> issues;

  /// Project milestones / types / priorities / sizes / epics / labels /
  /// components — populate the shared filter bar.
  final List<Milestone> milestones;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> sizes;
  final List<Epic> epics;
  final List<Label> labels;
  final List<Component> components;

  /// Shared work-item filter (identical model to the Issues list).
  final WorkItemFilter filter;

  /// Set to true on a 409 from a move — UI surfaces a banner.
  final bool staleData;

  TaskBoardLoaded copyWith({
    List<TaxonomyItem>? statuses,
    List<Issue>? issues,
    List<Milestone>? milestones,
    List<TaxonomyItem>? types,
    List<TaxonomyItem>? priorities,
    List<TaxonomyItem>? sizes,
    List<Epic>? epics,
    List<Label>? labels,
    List<Component>? components,
    WorkItemFilter? filter,
    bool? staleData,
  }) => TaskBoardLoaded(
    statuses: statuses ?? this.statuses,
    issues: issues ?? this.issues,
    milestones: milestones ?? this.milestones,
    types: types ?? this.types,
    priorities: priorities ?? this.priorities,
    sizes: sizes ?? this.sizes,
    epics: epics ?? this.epics,
    labels: labels ?? this.labels,
    components: components ?? this.components,
    filter: filter ?? this.filter,
    staleData: staleData ?? this.staleData,
  );

  /// Issues bucketed by `statusId`, after filters. Only top-level issues are
  /// cards (sub-tasks live under their parent). Columns always come from the
  /// status taxonomy so the board renders even with zero issues.
  Map<String?, List<Issue>> get bucketed {
    final closed = {
      for (final s in statuses)
        if (s.isClosed ?? false) s.id,
    };
    final out = <String?, List<Issue>>{null: []};
    for (final s in statuses) {
      out[s.id] = [];
    }
    for (final t in issues.where(
      (i) => i.parentId == null && filter.matches(i, closedStatusIds: closed),
    )) {
      out.putIfAbsent(t.statusId, () => []).add(t);
    }
    for (final list in out.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }
    return out;
  }

  @override
  List<Object?> get props => [
    statuses,
    issues,
    milestones,
    types,
    priorities,
    sizes,
    epics,
    labels,
    components,
    filter,
    staleData,
  ];
}

class TaskBoardCubit extends Cubit<TaskBoardState> {
  TaskBoardCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required MilestonesRepository milestones,
    required WorkItemFilterStore filterStore,
    required this.projectId,
  }) : _repo = repo,
       _catalog = catalog,
       _milestones = milestones,
       _filterStore = filterStore,
       _filter = filterStore.load(_view, projectId),
       super(const TaskBoardLoading());

  static const _view = 'board';

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final MilestonesRepository _milestones;
  final WorkItemFilterStore _filterStore;
  final String projectId;
  WorkItemFilter _filter;

  WorkItemFilter get filter => _filter;

  Future<void> load() async {
    if (!isClosed) emit(const TaskBoardLoading());
    final statusRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueStatus,
    );
    final issueRes = await _repo.listIssues(projectId);
    final msRes = await _milestones.list(projectId);
    final epicRes = await _repo.listEpics(projectId);
    final labelRes = await _catalog.listLabels(projectId);
    final compRes = await _catalog.listComponents(projectId);
    final typeRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueType,
    );
    final prioRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.priority,
    );
    final sizeRes = await _catalog.listTaxonomy(projectId, TaxonomyKind.size);
    final statuses = statusRes.valueOrNull;
    final issues = issueRes.valueOrNull;
    if (statuses == null || issues == null) {
      if (!isClosed) emit(const TaskBoardFailed());
      return;
    }
    if (!isClosed) {
      emit(
        TaskBoardLoaded(
          statuses: statuses,
          issues: issues,
          milestones: msRes.valueOrNull ?? const [],
          types: typeRes.valueOrNull ?? const [],
          priorities: prioRes.valueOrNull ?? const [],
          sizes: sizeRes.valueOrNull ?? const [],
          epics: epicRes.valueOrNull ?? const [],
          labels: labelRes.valueOrNull ?? const [],
          components: compRes.valueOrNull ?? const [],
          filter: _filter,
        ),
      );
    }
  }

  void setFilter(WorkItemFilter f) {
    _filter = f;
    unawaited(_filterStore.save(_view, projectId, f));
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(filter: f));
  }

  /// Optimistic move of an issue to a different `statusId`. On 409 we set
  /// `staleData = true` and reload to reconcile with the server.
  Future<void> moveTask({
    required String taskId,
    required String? targetStatusId,
  }) async {
    final s = state;
    if (s is! TaskBoardLoaded) return;
    final i = s.issues.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final cur = s.issues[i];
    if (cur.statusId == targetStatusId) return;

    // Optimistic local swap.
    final optimistic = [...s.issues];
    optimistic[i] = Issue(
      id: cur.id,
      projectId: cur.projectId,
      reference: cur.reference,
      subject: cur.subject,
      description: cur.description,
      labels: cur.labels,
      components: cur.components,
      statusId: targetStatusId,
      typeId: cur.typeId,
      priorityId: cur.priorityId,
      sizeId: cur.sizeId,
      epicId: cur.epicId,
      parentId: cur.parentId,
      milestoneId: cur.milestoneId,
      ownerId: cur.ownerId,
      assignedTo: cur.assignedTo,
      order: cur.order,
      version: cur.version,
      createdAt: cur.createdAt,
      modifiedAt: cur.modifiedAt,
      etag: cur.etag,
    );
    emit(s.copyWith(issues: optimistic, staleData: false));

    // Fetch fresh issue to get a current ETag before PATCH.
    final freshRes = await _repo.getIssue(projectId, taskId);
    final fresh = freshRes.valueOrNull;
    if (fresh == null || fresh.etag == null) {
      await load();
      return;
    }
    final patch = await _repo.updateIssue(
      projectId,
      taskId,
      body: UpdateIssueRequest(statusId: targetStatusId),
      etag: fresh.etag!,
    );
    final updated = patch.valueOrNull;
    if (updated == null) {
      if (!isClosed) emit(s.copyWith(staleData: true));
      await load();
      return;
    }
    final cur2 = state;
    if (cur2 is! TaskBoardLoaded) return;
    final j = cur2.issues.indexWhere((t) => t.id == taskId);
    if (j < 0) return;
    final next = [...cur2.issues];
    next[j] = updated;
    emit(cur2.copyWith(issues: next));
  }
}
