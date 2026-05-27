// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class TasksState extends Equatable {
  const TasksState();
  @override
  List<Object?> get props => const [];
}

final class TasksLoading extends TasksState {
  const TasksLoading();
}

final class TasksLoaded extends TasksState {
  const TasksLoaded({
    required this.tasks,
    required this.statuses,
    this.busy = false,
    this.lastError,
  });
  final List<Task> tasks;
  final List<TaxonomyItem> statuses;
  final bool busy;
  final AppFailure? lastError;

  TasksLoaded copyWith({
    List<Task>? tasks,
    bool? busy,
    AppFailure? lastError,
  }) => TasksLoaded(
    tasks: tasks ?? this.tasks,
    statuses: statuses,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props =>
      [tasks.map((t) => t.id).toList(), statuses.length, busy, lastError];
}

final class TasksFailed extends TasksState {
  const TasksFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

/// Tasks for one user story. Loads all project tasks once, filters in memory.
class TasksCubit extends Cubit<TasksState> {
  TasksCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required this.projectId,
    required this.userStoryId,
  }) : _repo = repo,
       _catalog = catalog,
       super(const TasksLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final String projectId;
  final String userStoryId;

  Future<void> load() async {
    emit(const TasksLoading());
    final ts = await _repo.listTasks(projectId);
    final st = await _catalog.listTaxonomy(projectId, TaxonomyKind.taskStatus);
    final fail = ts.failureOrNull ?? st.failureOrNull;
    if (fail != null) {
      emit(TasksFailed(fail));
      return;
    }
    final mine = ts.valueOrNull!
        .where((t) => t.userStoryId == userStoryId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    emit(TasksLoaded(tasks: mine, statuses: st.valueOrNull!));
  }

  Future<void> create(String subject) async {
    final s = state;
    if (s is! TasksLoaded || subject.trim().isEmpty) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createTask(
      projectId,
      CreateTaskRequest(subject: subject.trim(), userStoryId: userStoryId),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> setStatus(String taskId, String? statusId) async {
    final s = state;
    if (s is! TasksLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getTask(projectId, taskId);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.updateTask(
      projectId,
      taskId,
      body: UpdateTaskRequest(statusId: statusId),
      etag: fresh.etag ?? '',
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> delete(String taskId) async {
    final s = state;
    if (s is! TasksLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getTask(projectId, taskId);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res =
        await _repo.deleteTask(projectId, taskId, etag: fresh.etag ?? '');
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
