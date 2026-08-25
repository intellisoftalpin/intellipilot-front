import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

class ProjectCountsState extends Equatable {
  const ProjectCountsState({this.counts});

  /// Null until the first fetch lands (and after a failure), which renders as
  /// no badges rather than as zeros.
  final ProjectCounts? counts;

  @override
  List<Object?> get props => [
    counts?.myIssues,
    counts?.issues,
    counts?.epics,
    counts?.milestones,
  ];
}

/// Keeps the project rail's count badges current.
///
/// Fetches once on creation, then refreshes on the project's live event feed.
/// Refreshes are coalesced: a bulk edit or a busy discussion would otherwise
/// fire one count query per event, and the My Issues count is the expensive
/// one (it scans for `@handle` mentions).
class ProjectCountsCubit extends Cubit<ProjectCountsState> {
  ProjectCountsCubit({
    required ProjectsRepository repo,
    required this.projectId,
    ProjectEventsService? events,
  }) : _repo = repo,
       _events = events,
       super(const ProjectCountsState()) {
    // `watch` hands out a shared, ref-counted broadcast stream per project, so
    // listening here costs no extra connection when a board is already open.
    _sub = _events?.watch(projectId).listen(_onEvent);
    unawaited(refresh());
  }

  final ProjectsRepository _repo;
  final ProjectEventsService? _events;
  final String projectId;

  static const Duration _debounce = Duration(seconds: 4);

  StreamSubscription<LiveEvent>? _sub;
  Timer? _timer;

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _timer?.cancel();
    await super.close();
  }

  Future<void> refresh() async {
    final res = await _repo.getProjectCounts(projectId);
    final counts = res.valueOrNull;
    if (counts == null || isClosed) return;
    emit(ProjectCountsState(counts: counts));
  }

  void _onEvent(LiveEvent e) {
    if (e.isControl) {
      // Reconnected or resynced: whatever we missed may have changed a count.
      _schedule();
      return;
    }
    final event = e.payload['event'];
    if (event is! String) return;
    // A comment can only move the My Issues count, via the mention role — but
    // it can, so it counts.
    if (event.startsWith('issue.') ||
        event.startsWith('epic.') ||
        event.startsWith('milestone.') ||
        event.startsWith('comment.')) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (!isClosed) unawaited(refresh());
    });
  }
}
