// `_repo` is intentionally kept as a private field for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_gantt.dart';

export 'package:intellipilot/features/milestones/presentation/widgets/milestone_gantt.dart'
    show effectiveRange, isAtRisk;

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
    required this.completedCount,
    this.completedExpanded = false,
    this.completedLoading = false,
    this.busy = false,
  });

  /// The open milestones, plus the completed ones once the user expanded
  /// their band — they are not fetched before that.
  final List<Milestone> milestones;

  /// Every epic in the project. A milestone's readiness is rolled up from the
  /// epics pointing at it, so one fetch covers every card on the page.
  final List<Epic> epics;

  /// How many completed milestones exist, loaded or not.
  final int completedCount;
  final bool completedExpanded;
  final bool completedLoading;

  final bool busy;

  MilestonesListLoaded copyWith({
    List<Milestone>? milestones,
    List<Epic>? epics,
    int? completedCount,
    bool? completedExpanded,
    bool? completedLoading,
    bool? busy,
  }) => MilestonesListLoaded(
    milestones: milestones ?? this.milestones,
    epics: epics ?? this.epics,
    completedCount: completedCount ?? this.completedCount,
    completedExpanded: completedExpanded ?? this.completedExpanded,
    completedLoading: completedLoading ?? this.completedLoading,
    busy: busy ?? this.busy,
  );

  List<Milestone> get inProgress => _byEndDate(
    milestones.where((m) => !m.closed).toList(),
  );

  /// Completed milestones loaded so far, ordered exactly like the in-progress
  /// ones so the two read the same way: earliest end date first.
  List<Milestone> get completed =>
      _byEndDate(milestones.where((m) => m.closed).toList());

  /// Done and total issues across a milestone's epics.
  ({int closed, int total}) tasksFor(String milestoneId) {
    var total = 0;
    var closed = 0;
    for (final e in epics) {
      if (e.milestoneId != milestoneId) continue;
      total += e.taskTotal;
      closed += e.taskClosed;
    }
    return (closed: closed, total: total);
  }

  /// Completed issues over total across a milestone's epics; `null` when the
  /// milestone has no measurable work yet.
  double? progressFor(String milestoneId) {
    final t = tasksFor(milestoneId);
    return t.total <= 0 ? null : t.closed / t.total;
  }

  int epicCountFor(String milestoneId) =>
      epics.where((e) => e.milestoneId == milestoneId).length;

  @override
  List<Object?> get props => [
    milestones,
    epics,
    completedCount,
    completedExpanded,
    completedLoading,
    busy,
  ];
}

/// Nearest deadline first, so what is due next sits on top. Keyed on the end
/// that really happened, so a slipped milestone moves to where its bar sits on
/// the gantt rather than staying where it was planned.
List<Milestone> _byEndDate(List<Milestone> items) =>
    items
      ..sort((a, b) => effectiveRange(a).end.compareTo(effectiveRange(b).end));

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

  /// Load the open milestones — and the completed ones too when their band is
  /// already expanded, so a reload after an edit keeps what the user sees.
  Future<void> load() async {
    final prev = state;
    final expanded = prev is MilestonesListLoaded && prev.completedExpanded;
    if (prev is! MilestonesListLoaded && !isClosed) {
      emit(const MilestonesListLoading());
    }
    final res = await _repo.listPage(
      projectId,
      state: expanded ? MilestoneStateFilter.all : MilestoneStateFilter.open,
    );
    final page = res.valueOrNull;
    if (page == null) {
      if (!isClosed) emit(const MilestonesListFailed());
      return;
    }
    final epics = await _backlog.listEpics(projectId);
    if (!isClosed) {
      emit(
        MilestonesListLoaded(
          milestones: page.milestones,
          epics: epics.valueOrNull ?? const [],
          completedCount: page.completedCount,
          completedExpanded: expanded,
        ),
      );
    }
  }

  /// Expand or collapse the completed band, fetching its milestones the first
  /// time it opens.
  Future<void> toggleCompleted() async {
    final s = state;
    if (s is! MilestonesListLoaded) return;
    if (s.completedExpanded) {
      emit(s.copyWith(completedExpanded: false));
      return;
    }
    if (s.completed.length >= s.completedCount) {
      emit(s.copyWith(completedExpanded: true));
      return;
    }
    emit(s.copyWith(completedExpanded: true, completedLoading: true));
    final res = await _repo.listPage(
      projectId,
      state: MilestoneStateFilter.completed,
    );
    if (isClosed) return;
    final cur = state;
    if (cur is! MilestonesListLoaded) return;
    final page = res.valueOrNull;
    if (page == null) {
      emit(cur.copyWith(completedExpanded: false, completedLoading: false));
      return;
    }
    emit(
      cur.copyWith(
        milestones: [
          ...cur.milestones.where((m) => !m.closed),
          ...page.milestones,
        ],
        completedCount: page.completedCount,
        completedLoading: false,
      ),
    );
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
    final gone = s.milestones.where((x) => x.id == id).firstOrNull;
    if (!isClosed) {
      emit(
        s.copyWith(
          milestones: s.milestones.where((x) => x.id != id).toList(),
          completedCount: (gone?.closed ?? false)
              ? s.completedCount - 1
              : s.completedCount,
        ),
      );
    }
  }
}
