// `_repo` is intentionally kept as a private field for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

sealed class MilestonesListState extends Equatable {
  const MilestonesListState();
  @override
  List<Object?> get props => [];
}

class MilestonesListLoading extends MilestonesListState {
  const MilestonesListLoading();
}

class MilestonesListFailed extends MilestonesListState {
  const MilestonesListFailed();
}

class MilestonesListLoaded extends MilestonesListState {
  const MilestonesListLoaded({
    required this.milestones,
    required this.epics,
    this.busy = false,
  });

  final List<Milestone> milestones;

  /// Every epic in the project. A milestone's readiness is rolled up from the
  /// epics pointing at it, so one fetch covers every card on the page.
  final List<Epic> epics;

  final bool busy;

  MilestonesListLoaded copyWith({
    List<Milestone>? milestones,
    List<Epic>? epics,
    bool? busy,
  }) => MilestonesListLoaded(
    milestones: milestones ?? this.milestones,
    epics: epics ?? this.epics,
    busy: busy ?? this.busy,
  );

  List<Milestone> get inProgress => _byEndDate(
    milestones.where((m) => !m.closed).toList(),
  );

  /// Completed milestones, most recently completed first.
  List<Milestone> get completed =>
      milestones.where((m) => m.closed).toList()..sort((a, b) {
        final ac = a.closedAt ?? a.modifiedAt;
        final bc = b.closedAt ?? b.modifiedAt;
        return bc.compareTo(ac);
      });

  /// Completed issues over total across a milestone's epics; `null` when the
  /// milestone has no measurable work yet.
  double? progressFor(String milestoneId) {
    var total = 0;
    var closed = 0;
    for (final e in epics) {
      if (e.milestoneId != milestoneId) continue;
      total += e.taskTotal;
      closed += e.taskClosed;
    }
    return total <= 0 ? null : closed / total;
  }

  int epicCountFor(String milestoneId) =>
      epics.where((e) => e.milestoneId == milestoneId).length;

  @override
  List<Object?> get props => [milestones, epics, busy];
}

/// Nearest deadline first, so what is due next sits on top.
List<Milestone> _byEndDate(List<Milestone> items) =>
    items
      ..sort((a, b) => effectiveRange(a).end.compareTo(effectiveRange(b).end));

/// Effective schedule of a milestone for display: a missing start defaults to
/// today, a missing end to start + 7 days. [estimated] marks defaulted values
/// so views can render them as tentative.
({DateTime start, DateTime end, bool estimated}) effectiveRange(Milestone m) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = m.startDate ?? today;
  final end = m.endDate ?? start.add(const Duration(days: 7));
  return (
    start: start,
    end: end.isBefore(start) ? start : end,
    estimated: m.startDate == null || m.endDate == null,
  );
}

class MilestonesListCubit extends Cubit<MilestonesListState> {
  MilestonesListCubit({
    required MilestonesRepository repo,
    required BacklogRepository backlog,
    required this.projectId,
  }) : _repo = repo,
       _backlog = backlog,
       super(const MilestonesListLoading());

  final MilestonesRepository _repo;
  final BacklogRepository _backlog;
  final String projectId;

  Future<void> load() async {
    if (!isClosed) emit(const MilestonesListLoading());
    final res = await _repo.list(projectId);
    final items = res.valueOrNull;
    if (items == null) {
      if (!isClosed) emit(const MilestonesListFailed());
      return;
    }
    final epics = await _backlog.listEpics(projectId);
    if (!isClosed) {
      emit(
        MilestonesListLoaded(
          milestones: items,
          epics: epics.valueOrNull ?? const [],
        ),
      );
    }
  }

  Future<bool> create(CreateMilestoneRequest body) async {
    final s = state;
    if (s is! MilestonesListLoaded) return false;
    emit(s.copyWith(busy: true));
    final res = await _repo.create(projectId, body);
    final m = res.valueOrNull;
    if (m == null) {
      if (!isClosed) emit(s.copyWith(busy: false));
      return false;
    }
    if (!isClosed) {
      emit(s.copyWith(milestones: [...s.milestones, m], busy: false));
    }
    return true;
  }

  /// Drop a milestone the sidebar deleted, without a round-trip.
  void forget(String id) {
    final s = state;
    if (s is! MilestonesListLoaded) return;
    if (!isClosed) {
      emit(
        s.copyWith(
          milestones: s.milestones.where((x) => x.id != id).toList(),
        ),
      );
    }
  }
}
