// `_repo` / `_catalog` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
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
    this.epics = const [],
    this.labels = const [],
    this.components = const [],
    this.sprintFilter,
    this.assigneeFilter,
    this.epicFilter,
    this.labelFilter,
    this.componentFilter,
    this.categoryFilter,
    this.search = '',
    this.staleData = false,
  });

  /// The `issue_status` taxonomy items, ordered — these are the board columns.
  final List<TaxonomyItem> statuses;

  /// All issues for the project.
  final List<Issue> issues;

  /// Project milestones — populate the optional Sprint filter.
  final List<Milestone> milestones;

  /// Project epics / labels / components — populate the filter dropdowns.
  final List<Epic> epics;
  final List<Label> labels;
  final List<Component> components;

  /// Optional sprint filter: when set, only issues in this milestone show.
  /// `null` = all sprints (the board needs no milestone to render).
  final String? sprintFilter;

  /// Optional filters. `null` = no filter on that dimension.
  final String? assigneeFilter;
  final String? epicFilter;
  final String? labelFilter;
  final String? componentFilter;
  final String? categoryFilter;

  /// Free-text filter over subject / `#ref`.
  final String search;

  /// Set to true on a 409 from a move — UI surfaces a banner.
  final bool staleData;

  TaskBoardLoaded copyWith({
    List<TaxonomyItem>? statuses,
    List<Issue>? issues,
    List<Milestone>? milestones,
    List<Epic>? epics,
    List<Label>? labels,
    List<Component>? components,
    Object? sprintFilter = _absent,
    Object? assigneeFilter = _absent,
    Object? epicFilter = _absent,
    Object? labelFilter = _absent,
    Object? componentFilter = _absent,
    Object? categoryFilter = _absent,
    String? search,
    bool? staleData,
  }) => TaskBoardLoaded(
    statuses: statuses ?? this.statuses,
    issues: issues ?? this.issues,
    milestones: milestones ?? this.milestones,
    epics: epics ?? this.epics,
    labels: labels ?? this.labels,
    components: components ?? this.components,
    sprintFilter:
        sprintFilter == _absent ? this.sprintFilter : sprintFilter as String?,
    assigneeFilter: assigneeFilter == _absent
        ? this.assigneeFilter
        : assigneeFilter as String?,
    epicFilter: epicFilter == _absent ? this.epicFilter : epicFilter as String?,
    labelFilter:
        labelFilter == _absent ? this.labelFilter : labelFilter as String?,
    componentFilter: componentFilter == _absent
        ? this.componentFilter
        : componentFilter as String?,
    categoryFilter: categoryFilter == _absent
        ? this.categoryFilter
        : categoryFilter as String?,
    search: search ?? this.search,
    staleData: staleData ?? this.staleData,
  );

  static const _absent = Object();

  /// Distinct assignee user ids referenced by top-level issues — drives the
  /// assignee filter dropdown (names resolved via MembersScope in the UI).
  List<String> get assigneeIds {
    final ids = <String>{};
    for (final it in issues) {
      if (it.parentId == null && it.assignedTo != null) {
        ids.add(it.assignedTo!);
      }
    }
    return ids.toList();
  }

  bool _matches(Issue it) {
    // Only top-level issues are cards; sub-tasks live under their parent.
    if (it.parentId != null) return false;
    if (sprintFilter != null && it.milestoneId != sprintFilter) return false;
    if (assigneeFilter != null && it.assignedTo != assigneeFilter) return false;
    if (epicFilter != null && it.epicId != epicFilter) return false;
    if (labelFilter != null && !it.labels.contains(labelFilter)) return false;
    if (componentFilter != null && !it.components.contains(componentFilter)) {
      return false;
    }
    if (categoryFilter != null && it.category != categoryFilter) return false;
    if (search.trim().isEmpty) return true;
    final q = search.toLowerCase();
    return it.subject.toLowerCase().contains(q) ||
        '#${it.reference}'.contains(q);
  }

  /// Issues bucketed by `statusId`, after filters. Columns always come from the
  /// status taxonomy (so the board renders even with zero issues). Issues with
  /// no status fall into the trailing `null` bucket.
  Map<String?, List<Issue>> get bucketed {
    final out = <String?, List<Issue>>{null: []};
    for (final s in statuses) {
      out[s.id] = [];
    }
    for (final t in issues.where(_matches)) {
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
    epics,
    labels,
    components,
    sprintFilter,
    assigneeFilter,
    epicFilter,
    labelFilter,
    componentFilter,
    categoryFilter,
    search,
    staleData,
  ];
}

class TaskBoardCubit extends Cubit<TaskBoardState> {
  TaskBoardCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required MilestonesRepository milestones,
    required this.projectId,
  }) : _repo = repo,
       _catalog = catalog,
       _milestones = milestones,
       super(const TaskBoardLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final MilestonesRepository _milestones;
  final String projectId;

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
          epics: epicRes.valueOrNull ?? const [],
          labels: labelRes.valueOrNull ?? const [],
          components: compRes.valueOrNull ?? const [],
        ),
      );
    }
  }

  void setSprintFilter(String? milestoneId) {
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(sprintFilter: milestoneId));
  }

  void setAssigneeFilter(String? userId) {
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(assigneeFilter: userId));
  }

  void setEpicFilter(String? epicId) {
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(epicFilter: epicId));
  }

  void setLabelFilter(String? labelId) {
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(labelFilter: labelId));
  }

  void setComponentFilter(String? componentId) {
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(componentFilter: componentId));
  }

  void setCategoryFilter(String? category) {
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(categoryFilter: category));
  }

  void setSearch(String q) {
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(search: q));
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
