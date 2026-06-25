// `_repo` fields are intentionally kept as private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

sealed class MilestoneDetailState extends Equatable {
  const MilestoneDetailState();
  @override
  List<Object?> get props => [];
}

class MilestoneDetailLoading extends MilestoneDetailState {
  const MilestoneDetailLoading();
}

class MilestoneDetailFailed extends MilestoneDetailState {
  const MilestoneDetailFailed();
}

class MilestoneDetailLoaded extends MilestoneDetailState {
  const MilestoneDetailLoaded({
    required this.milestone,
    required this.stats,
    required this.scope,
    required this.backlog,
    required this.epics,
    this.busy = false,
  });

  final Milestone milestone;
  final MilestoneStats stats;

  /// User stories already assigned to this milestone.
  final List<Issue> scope;

  /// User stories from the project backlog not assigned to any milestone
  /// (candidates for adding to this sprint's scope).
  final List<Issue> backlog;

  /// All project epics. The milestone is composed of the subset whose
  /// `milestoneId` matches this milestone.
  final List<Epic> epics;

  final bool busy;

  List<Epic> get epicsInMilestone =>
      epics.where((e) => e.milestoneId == milestone.id).toList();

  MilestoneDetailLoaded copyWith({
    Milestone? milestone,
    MilestoneStats? stats,
    List<Issue>? scope,
    List<Issue>? backlog,
    List<Epic>? epics,
    bool? busy,
  }) => MilestoneDetailLoaded(
    milestone: milestone ?? this.milestone,
    stats: stats ?? this.stats,
    scope: scope ?? this.scope,
    backlog: backlog ?? this.backlog,
    epics: epics ?? this.epics,
    busy: busy ?? this.busy,
  );

  /// Open stories in scope — used by the close-sprint disposition flow.
  List<Issue> get openInScope => scope
      .where((s) => s.statusId == null) // best-effort: no status = open
      .toList();

  @override
  List<Object?> get props => [milestone, stats, scope, backlog, epics, busy];
}

class MilestoneDetailCubit extends Cubit<MilestoneDetailState> {
  MilestoneDetailCubit({
    required MilestonesRepository milestones,
    required BacklogRepository backlog,
    required this.projectId,
    required this.milestoneId,
  }) : _milestones = milestones,
       _backlog = backlog,
       super(const MilestoneDetailLoading());

  final MilestonesRepository _milestones;
  final BacklogRepository _backlog;
  final String projectId;
  final String milestoneId;

  Future<void> load() async {
    if (!isClosed) emit(const MilestoneDetailLoading());
    final ms = await _milestones.get(projectId, milestoneId);
    final st = await _milestones.stats(projectId, milestoneId);
    final us = await _backlog.listIssues(projectId);
    final ep = await _backlog.listEpics(projectId);
    final m = ms.valueOrNull;
    final s = st.valueOrNull;
    final stories = us.valueOrNull;
    final epics = ep.valueOrNull;
    if (m == null || s == null || stories == null || epics == null) {
      if (!isClosed) emit(const MilestoneDetailFailed());
      return;
    }
    final scope = stories.where((u) => u.milestoneId == milestoneId).toList();
    final backlog = stories.where((u) => u.milestoneId == null).toList();
    if (!isClosed) {
      emit(
        MilestoneDetailLoaded(
          milestone: m,
          stats: s,
          scope: scope,
          backlog: backlog,
          epics: epics,
        ),
      );
    }
  }

  /// Replace the set of epics composing this milestone, then reload.
  Future<bool> setEpics(List<String> epicIds) async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    if (!isClosed) emit(s.copyWith(busy: true));
    final res = await _milestones.setEpics(projectId, milestoneId, epicIds);
    if (res.isErr) {
      if (!isClosed) emit(s.copyWith(busy: false));
      return false;
    }
    await load();
    return true;
  }

  Future<bool> rename(String name) async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    final res = await _milestones.update(
      projectId,
      milestoneId,
      body: UpdateMilestoneRequest(name: name),
    );
    final m = res.valueOrNull;
    if (m == null) return false;
    if (!isClosed) emit(s.copyWith(milestone: m));
    return true;
  }

  /// Adds a story to the sprint (sets `milestone_id`). The PATCH carries
  /// the story's current ETag.
  Future<bool> addToScope(String storyId) async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    final fresh = await _backlog.getIssue(projectId, storyId);
    final us = fresh.valueOrNull;
    if (us?.etag == null) return false;
    final res = await _backlog.updateIssue(
      projectId,
      storyId,
      body: UpdateIssueRequest(milestoneId: milestoneId),
      etag: us!.etag!,
    );
    if (res.valueOrNull == null) return false;
    await load();
    return true;
  }

  /// Removes a story from the sprint by clearing its `milestone_id`.
  Future<bool> removeFromScope(String storyId) async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    final fresh = await _backlog.getIssue(projectId, storyId);
    final us = fresh.valueOrNull;
    if (us?.etag == null) return false;
    final res = await _backlog.updateIssue(
      projectId,
      storyId,
      body: const UpdateIssueRequest(milestoneId: null),
      etag: us!.etag!,
    );
    if (res.valueOrNull == null) return false;
    await load();
    return true;
  }

  /// Closes the sprint. Optional [moveUnfinishedToBacklog] clears the
  /// `milestone_id` on each open story before the close call lands so
  /// they're back in the backlog rather than buried inside the closed
  /// sprint.
  Future<bool> closeSprint({
    required bool moveUnfinishedToBacklog,
  }) async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    emit(s.copyWith(busy: true));
    if (moveUnfinishedToBacklog) {
      for (final story in s.openInScope) {
        final fresh = await _backlog.getIssue(projectId, story.id);
        final us = fresh.valueOrNull;
        if (us?.etag == null) continue;
        await _backlog.updateIssue(
          projectId,
          story.id,
          body: const UpdateIssueRequest(milestoneId: null),
          etag: us!.etag!,
        );
      }
    }
    final res = await _milestones.close(projectId, milestoneId);
    if (res.valueOrNull == null) {
      if (!isClosed) emit(s.copyWith(busy: false));
      return false;
    }
    await load();
    return true;
  }
}
