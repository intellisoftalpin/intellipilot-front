// `_repo` / `_catalog` are intentionally private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

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
    this.staleData = false,
  });

  /// The `issue_status` taxonomy items, ordered.
  final List<TaxonomyItem> statuses;

  /// All issues for the project (no milestone filtering on this view).
  final List<Issue> issues;

  /// Set to true on a 409 from a move — UI surfaces a banner.
  final bool staleData;

  TaskBoardLoaded copyWith({
    List<TaxonomyItem>? statuses,
    List<Issue>? issues,
    bool? staleData,
  }) => TaskBoardLoaded(
    statuses: statuses ?? this.statuses,
    issues: issues ?? this.issues,
    staleData: staleData ?? this.staleData,
  );

  /// Issues bucketed by `statusId`. Issues with no status fall into the
  /// trailing `null` bucket.
  Map<String?, List<Issue>> get bucketed {
    final out = <String?, List<Issue>>{null: []};
    for (final s in statuses) {
      out[s.id] = [];
    }
    for (final t in issues) {
      out.putIfAbsent(t.statusId, () => []).add(t);
    }
    return out;
  }

  @override
  List<Object?> get props => [statuses, issues, staleData];
}

class TaskBoardCubit extends Cubit<TaskBoardState> {
  TaskBoardCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required this.projectId,
  }) : _repo = repo,
       _catalog = catalog,
       super(const TaskBoardLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final String projectId;

  Future<void> load() async {
    if (!isClosed) emit(const TaskBoardLoading());
    final statusRes = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueStatus,
    );
    final issueRes = await _repo.listIssues(projectId);
    final statuses = statusRes.valueOrNull;
    final issues = issueRes.valueOrNull;
    if (statuses == null || issues == null) {
      if (!isClosed) emit(const TaskBoardFailed());
      return;
    }
    if (!isClosed) {
      emit(TaskBoardLoaded(statuses: statuses, issues: issues));
    }
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
    // Refresh just this issue with the server-confirmed version.
    final cur2 = state;
    if (cur2 is! TaskBoardLoaded) return;
    final j = cur2.issues.indexWhere((t) => t.id == taskId);
    if (j < 0) return;
    final next = [...cur2.issues];
    next[j] = updated;
    emit(cur2.copyWith(issues: next));
  }
}
