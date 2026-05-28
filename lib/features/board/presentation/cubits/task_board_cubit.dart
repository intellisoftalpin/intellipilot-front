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
    required this.tasks,
    this.staleData = false,
  });

  /// The `task_status` taxonomy items, ordered.
  final List<TaxonomyItem> statuses;

  /// All tasks for the project (no milestone filtering in v1).
  final List<Task> tasks;

  /// Set to true on a 409 from a move — UI surfaces a banner.
  final bool staleData;

  TaskBoardLoaded copyWith({
    List<TaxonomyItem>? statuses,
    List<Task>? tasks,
    bool? staleData,
  }) => TaskBoardLoaded(
    statuses: statuses ?? this.statuses,
    tasks: tasks ?? this.tasks,
    staleData: staleData ?? this.staleData,
  );

  /// Tasks bucketed by `statusId`. Tasks with no status fall into the
  /// trailing `null` bucket.
  Map<String?, List<Task>> get bucketed {
    final out = <String?, List<Task>>{null: []};
    for (final s in statuses) {
      out[s.id] = [];
    }
    for (final t in tasks) {
      out.putIfAbsent(t.statusId, () => []).add(t);
    }
    return out;
  }

  @override
  List<Object?> get props => [statuses, tasks, staleData];
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
      TaxonomyKind.taskStatus,
    );
    final taskRes = await _repo.listTasks(projectId);
    final statuses = statusRes.valueOrNull;
    final tasks = taskRes.valueOrNull;
    if (statuses == null || tasks == null) {
      if (!isClosed) emit(const TaskBoardFailed());
      return;
    }
    if (!isClosed) {
      emit(TaskBoardLoaded(statuses: statuses, tasks: tasks));
    }
  }

  /// Optimistic move of a task to a different `statusId`. On 409 we set
  /// `staleData = true` and reload to reconcile with the server.
  Future<void> moveTask({
    required String taskId,
    required String? targetStatusId,
  }) async {
    final s = state;
    if (s is! TaskBoardLoaded) return;
    final i = s.tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final cur = s.tasks[i];
    if (cur.statusId == targetStatusId) return;

    // Optimistic local swap.
    final optimistic = [...s.tasks];
    optimistic[i] = Task(
      id: cur.id,
      projectId: cur.projectId,
      reference: cur.reference,
      subject: cur.subject,
      description: cur.description,
      statusId: targetStatusId,
      userStoryId: cur.userStoryId,
      ownerId: cur.ownerId,
      assignedTo: cur.assignedTo,
      order: cur.order,
      version: cur.version,
      createdAt: cur.createdAt,
      modifiedAt: cur.modifiedAt,
      etag: cur.etag,
    );
    emit(s.copyWith(tasks: optimistic, staleData: false));

    // Fetch fresh task to get a current ETag before PATCH.
    final freshRes = await _repo.getTask(projectId, taskId);
    final fresh = freshRes.valueOrNull;
    if (fresh == null || fresh.etag == null) {
      await load();
      return;
    }
    final patch = await _repo.updateTask(
      projectId,
      taskId,
      body: UpdateTaskRequest(statusId: targetStatusId),
      etag: fresh.etag!,
    );
    final updated = patch.valueOrNull;
    if (updated == null) {
      if (!isClosed) emit(s.copyWith(staleData: true));
      await load();
      return;
    }
    // Refresh just this task with the server-confirmed version.
    final cur2 = state;
    if (cur2 is! TaskBoardLoaded) return;
    final j = cur2.tasks.indexWhere((t) => t.id == taskId);
    if (j < 0) return;
    final next = [...cur2.tasks];
    next[j] = updated;
    emit(cur2.copyWith(tasks: next));
  }
}
