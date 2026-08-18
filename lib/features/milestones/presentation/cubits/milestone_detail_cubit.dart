// `_repo` fields are intentionally kept as private fields for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/error/app_failure.dart';
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

/// Why the last write failed, when the sidebar should say something specific
/// rather than a generic "couldn't save".
enum MilestoneDetailError {
  /// Someone else saved first; the sidebar must reload before retrying.
  conflict,

  /// Delete refused because epics still compose the milestone.
  hasEpics,

  /// Anything else.
  generic,
}

class MilestoneDetailLoaded extends MilestoneDetailState {
  const MilestoneDetailLoaded({
    required this.milestone,
    required this.stats,
    required this.epicsInMilestone,
    required this.allEpics,
    this.busy = false,
    this.error,
  });

  final Milestone milestone;
  final MilestoneStats stats;

  /// The epics composing this milestone, with readiness counts hydrated.
  final List<Epic> epicsInMilestone;

  /// Every epic in the project — the candidate set for the epic picker.
  final List<Epic> allEpics;

  final bool busy;

  /// Set for one emission after a failed write; cleared on the next action.
  final MilestoneDetailError? error;

  /// Completed issues over total, across the milestone's epics. `null` when
  /// there is nothing to measure.
  double? get epicProgress {
    var total = 0;
    var closed = 0;
    for (final e in epicsInMilestone) {
      total += e.taskTotal;
      closed += e.taskClosed;
    }
    return total <= 0 ? null : closed / total;
  }

  MilestoneDetailLoaded copyWith({
    Milestone? milestone,
    MilestoneStats? stats,
    List<Epic>? epicsInMilestone,
    List<Epic>? allEpics,
    bool? busy,
    MilestoneDetailError? error,
    bool clearError = false,
  }) => MilestoneDetailLoaded(
    milestone: milestone ?? this.milestone,
    stats: stats ?? this.stats,
    epicsInMilestone: epicsInMilestone ?? this.epicsInMilestone,
    allEpics: allEpics ?? this.allEpics,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    milestone,
    stats,
    epicsInMilestone,
    allEpics,
    busy,
    error,
  ];
}

/// Drives the milestone sidebar: loads everything it shows and owns every
/// write it can make.
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

  /// Whether anything was written since the sidebar opened. The list/gantt
  /// underneath reloads on dismiss only when this is true, so merely peeking
  /// at a milestone costs no round-trip.
  bool get dirty => _dirty;
  bool _dirty = false;

  /// Record that something outside this cubit's own writes may have changed
  /// the milestone — currently a nested epic sheet, whose edits can move this
  /// milestone's progress. Deliberately pessimistic: there is no way to tell
  /// from here whether the nested sheet actually wrote anything, and the cost
  /// of being wrong is one reload of the list underneath.
  void markDirty() => _dirty = true;

  /// Set when the milestone was deleted from the sidebar, so the caller can
  /// drop it from the list without a reload.
  bool get deleted => _deleted;
  bool _deleted = false;

  Future<void> load() async {
    if (!isClosed) emit(const MilestoneDetailLoading());
    final ms = await _milestones.get(projectId, milestoneId);
    final m = ms.valueOrNull;
    if (m == null) {
      if (!isClosed) emit(const MilestoneDetailFailed());
      return;
    }
    final st = await _milestones.stats(projectId, milestoneId);
    final mine = await _milestones.epics(projectId, milestoneId);
    final all = await _backlog.listEpics(projectId);
    if (!isClosed) {
      emit(
        MilestoneDetailLoaded(
          milestone: m,
          stats: st.valueOrNull ?? MilestoneStats.empty,
          epicsInMilestone: mine.valueOrNull ?? const [],
          allEpics: all.valueOrNull ?? const [],
        ),
      );
    }
  }

  /// Apply a partial edit. Returns false and flags [MilestoneDetailError] on
  /// failure; the caller keeps the sidebar open so nothing typed is lost.
  Future<bool> save(UpdateMilestoneRequest body) async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    if (body.isEmpty) return true;
    final tag = s.milestone.etag;
    if (tag == null) return false;
    if (!isClosed) emit(s.copyWith(busy: true, clearError: true));
    final res = await _milestones.update(
      projectId,
      milestoneId,
      body: body,
      etag: tag,
    );
    return res.when(
      ok: (m) {
        _dirty = true;
        if (!isClosed) {
          emit(s.copyWith(milestone: m, busy: false, clearError: true));
        }
        return true;
      },
      err: (f) {
        if (!isClosed) {
          emit(s.copyWith(busy: false, error: _classify(f)));
        }
        return false;
      },
    );
  }

  /// Mark completed or move back to in progress.
  Future<bool> setCompleted({required bool completed}) async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    if (!isClosed) emit(s.copyWith(busy: true, clearError: true));
    final res = await _milestones.setCompleted(
      projectId,
      milestoneId,
      completed: completed,
    );
    return res.when(
      ok: (m) {
        _dirty = true;
        if (!isClosed) {
          emit(s.copyWith(milestone: m, busy: false, clearError: true));
        }
        return true;
      },
      err: (f) {
        if (!isClosed) emit(s.copyWith(busy: false, error: _classify(f)));
        return false;
      },
    );
  }

  /// Replace the set of epics composing this milestone, then reload so the
  /// readiness rings and rollup reflect the new scope.
  Future<bool> setEpics(List<String> epicIds) async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    if (!isClosed) emit(s.copyWith(busy: true, clearError: true));
    final res = await _milestones.setEpics(projectId, milestoneId, epicIds);
    if (res.isErr) {
      if (!isClosed) {
        emit(s.copyWith(busy: false, error: _classify(res.failureOrNull)));
      }
      return false;
    }
    _dirty = true;
    await load();
    return true;
  }

  /// Delete the milestone. Refused by the backend while epics remain, which
  /// surfaces as [MilestoneDetailError.hasEpics].
  Future<bool> delete() async {
    final s = state;
    if (s is! MilestoneDetailLoaded) return false;
    if (!isClosed) emit(s.copyWith(busy: true, clearError: true));
    final res = await _milestones.delete(projectId, milestoneId);
    if (res.isErr) {
      final failure = res.failureOrNull;
      if (!isClosed) {
        emit(
          s.copyWith(
            busy: false,
            error: failure is ConflictFailure
                ? MilestoneDetailError.hasEpics
                : _classify(failure),
          ),
        );
      }
      return false;
    }
    _dirty = true;
    _deleted = true;
    return true;
  }

  /// Both 409 and 412 arrive as [ConflictFailure]; for a save either one means
  /// the same thing to the user — someone else got there first.
  static MilestoneDetailError _classify(AppFailure? f) => switch (f) {
    ConflictFailure() => MilestoneDetailError.conflict,
    _ => MilestoneDetailError.generic,
  };
}
