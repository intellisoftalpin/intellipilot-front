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
    this.sprintFilter,
    this.search = '',
    this.staleData = false,
  });

  /// The `issue_status` taxonomy items, ordered — these are the board columns.
  final List<TaxonomyItem> statuses;

  /// All issues for the project.
  final List<Issue> issues;

  /// Project milestones — populate the optional Sprint filter.
  final List<Milestone> milestones;

  /// Optional sprint filter: when set, only issues in this milestone show.
  /// `null` = all sprints (the board needs no milestone to render).
  final String? sprintFilter;

  /// Free-text filter over subject / `#ref`.
  final String search;

  /// Set to true on a 409 from a move — UI surfaces a banner.
  final bool staleData;

  TaskBoardLoaded copyWith({
    List<TaxonomyItem>? statuses,
    List<Issue>? issues,
    List<Milestone>? milestones,
    Object? sprintFilter = _absent,
    String? search,
    bool? staleData,
  }) => TaskBoardLoaded(
    statuses: statuses ?? this.statuses,
    issues: issues ?? this.issues,
    milestones: milestones ?? this.milestones,
    sprintFilter:
        sprintFilter == _absent ? this.sprintFilter : sprintFilter as String?,
    search: search ?? this.search,
    staleData: staleData ?? this.staleData,
  );

  static const _absent = Object();

  bool _matches(Issue it) {
    // Only top-level issues are cards; sub-tasks live under their parent.
    if (it.parentId != null) return false;
    if (sprintFilter != null && it.milestoneId != sprintFilter) return false;
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
  List<Object?> get props =>
      [statuses, issues, milestones, sprintFilter, search, staleData];
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
        ),
      );
    }
  }

  void setSprintFilter(String? milestoneId) {
    final s = state;
    if (s is TaskBoardLoaded) emit(s.copyWith(sprintFilter: milestoneId));
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
      severityId: cur.severityId,
      pointsId: cur.pointsId,
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
