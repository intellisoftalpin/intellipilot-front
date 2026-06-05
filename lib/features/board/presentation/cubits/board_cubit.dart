// `_repos` are kept as private fields for clarity; the lint flagging this
// would prefer initialising-formals which obscure their role.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/dtos/board_dtos.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

class BoardFilter extends Equatable {
  const BoardFilter({this.search = '', this.assignee});
  final String search;
  final String? assignee;

  BoardFilter copyWith({String? search, Object? assignee = _sentinel}) =>
      BoardFilter(
        search: search ?? this.search,
        assignee: identical(assignee, _sentinel)
            ? this.assignee
            : assignee as String?,
      );

  static const _sentinel = Object();

  bool matches(Issue s) {
    if (search.isNotEmpty) {
      final needle = search.toLowerCase();
      if (!s.subject.toLowerCase().contains(needle) &&
          !'#${s.reference}'.contains(needle)) {
        return false;
      }
    }
    if (assignee != null && s.assignedTo != assignee) return false;
    return true;
  }

  @override
  List<Object?> get props => [search, assignee];
}

sealed class BoardState extends Equatable {
  const BoardState();
  @override
  List<Object?> get props => [];
}

class BoardLoading extends BoardState {
  const BoardLoading();
}

/// No milestones in this project yet — board can't render. The UI nudges the
/// user toward creating one.
class BoardEmpty extends BoardState {
  const BoardEmpty();
}

class BoardFailed extends BoardState {
  const BoardFailed();
}

class BoardLoaded extends BoardState {
  const BoardLoaded({
    required this.milestones,
    required this.milestoneId,
    required this.snapshot,
    required this.filter,
    this.staleData = false,
  });

  final List<Milestone> milestones;
  final String milestoneId;
  final BoardSnapshot snapshot;
  final BoardFilter filter;
  final bool staleData;

  BoardLoaded copyWith({
    List<Milestone>? milestones,
    String? milestoneId,
    BoardSnapshot? snapshot,
    BoardFilter? filter,
    bool? staleData,
  }) => BoardLoaded(
    milestones: milestones ?? this.milestones,
    milestoneId: milestoneId ?? this.milestoneId,
    snapshot: snapshot ?? this.snapshot,
    filter: filter ?? this.filter,
    staleData: staleData ?? this.staleData,
  );

  /// Filtered view of the columns (each column keeps only the cards that
  /// pass the active [BoardFilter]).
  List<BoardColumn> get visibleColumns => snapshot.columns
      .map(
        (col) => BoardColumn(
          status: col.status,
          issues: col.issues.where((c) => filter.matches(c.issue)).toList(),
        ),
      )
      .toList();

  /// Distinct non-null assignees across the snapshot — used to populate the
  /// filter dropdown.
  List<String> get knownAssignees {
    final set = <String>{};
    for (final col in snapshot.columns) {
      for (final c in col.issues) {
        final a = c.issue.assignedTo;
        if (a != null) set.add(a);
      }
    }
    return set.toList()..sort();
  }

  @override
  List<Object?> get props => [
    milestones,
    milestoneId,
    snapshot,
    filter,
    staleData,
  ];
}

class BoardCubit extends Cubit<BoardState> {
  BoardCubit({
    required MilestonesRepository milestones,
    required BoardRepository board,
    required BacklogRepository backlog,
    required this.projectId,
  }) : _milestones = milestones,
       _board = board,
       _backlog = backlog,
       super(const BoardLoading());

  final MilestonesRepository _milestones;
  final BoardRepository _board;
  final BacklogRepository _backlog;
  final String projectId;

  Future<void> load({String? preferredMilestoneId}) async {
    if (!isClosed) emit(const BoardLoading());
    final msRes = await _milestones.list(projectId);
    final ms = msRes.valueOrNull;
    if (ms == null) {
      if (!isClosed) emit(const BoardFailed());
      return;
    }
    if (ms.isEmpty) {
      if (!isClosed) emit(const BoardEmpty());
      return;
    }
    final pick = preferredMilestoneId != null &&
            ms.any((m) => m.id == preferredMilestoneId)
        ? preferredMilestoneId
        : _defaultMilestoneId(ms);
    final boardRes = await _board.load(projectId, pick);
    final snapshot = boardRes.valueOrNull;
    if (snapshot == null) {
      if (!isClosed) emit(const BoardFailed());
      return;
    }
    if (!isClosed) {
      emit(
        BoardLoaded(
          milestones: ms,
          milestoneId: pick,
          snapshot: snapshot,
          filter: const BoardFilter(),
        ),
      );
    }
  }

  Future<void> switchMilestone(String milestoneId) async {
    final s = state;
    if (s is! BoardLoaded) return;
    if (s.milestoneId == milestoneId) return;
    emit(const BoardLoading());
    final res = await _board.load(projectId, milestoneId);
    final snapshot = res.valueOrNull;
    if (snapshot == null) {
      if (!isClosed) emit(const BoardFailed());
      return;
    }
    if (!isClosed) {
      emit(s.copyWith(milestoneId: milestoneId, snapshot: snapshot));
    }
  }

  void setFilter(BoardFilter filter) {
    final s = state;
    if (s is! BoardLoaded) return;
    emit(s.copyWith(filter: filter));
  }

  /// Optimistic move of an issue card to a different column (status).
  /// On 409 we set [BoardLoaded.staleData] = true and reload the board.
  Future<void> moveCard({
    required String storyId,
    required String? targetStatusId,
  }) async {
    final s = state;
    if (s is! BoardLoaded) return;
    final origin = _findColumnOf(s, storyId);
    if (origin == null) return;
    if (origin.status?.id == targetStatusId ||
        (origin.status == null && targetStatusId == null)) {
      return;
    }

    // Optimistic reorder: pull the card out of its column, push into the
    // target column at the head.
    final card = origin.issues.firstWhere((c) => c.issue.id == storyId);
    final newCols = s.snapshot.columns.map((col) {
      final isOrigin = col.id == origin.id;
      final isTarget = col.status?.id == targetStatusId ||
          (col.status == null && targetStatusId == null);
      if (isOrigin && isTarget) return col;
      if (isOrigin) {
        return BoardColumn(
          status: col.status,
          issues: col.issues.where((c) => c.issue.id != storyId).toList(),
        );
      }
      if (isTarget) {
        return BoardColumn(
          status: col.status,
          issues: [card, ...col.issues],
        );
      }
      return col;
    }).toList();
    emit(
      s.copyWith(
        snapshot:
            BoardSnapshot(milestoneId: s.milestoneId, columns: newCols),
        staleData: false,
      ),
    );

    // Fetch fresh issue to get the etag, then PATCH the status.
    final usRes = await _backlog.getIssue(projectId, storyId);
    final fresh = usRes.valueOrNull;
    if (fresh == null || fresh.etag == null) {
      await load(preferredMilestoneId: s.milestoneId);
      return;
    }
    final patch = await _backlog.updateIssue(
      projectId,
      storyId,
      body: UpdateIssueRequest(statusId: targetStatusId),
      etag: fresh.etag!,
    );
    if (patch.valueOrNull == null) {
      if (!isClosed) emit(s.copyWith(staleData: true));
      await load(preferredMilestoneId: s.milestoneId);
    }
  }

  BoardColumn? _findColumnOf(BoardLoaded s, String storyId) {
    for (final col in s.snapshot.columns) {
      if (col.issues.any((c) => c.issue.id == storyId)) return col;
    }
    return null;
  }

  /// Pick the first open milestone, falling back to the first one if all are
  /// closed.
  String _defaultMilestoneId(List<Milestone> ms) {
    final open = ms.where((m) => !m.closed);
    if (open.isNotEmpty) return open.first.id;
    return ms.first.id;
  }
}
