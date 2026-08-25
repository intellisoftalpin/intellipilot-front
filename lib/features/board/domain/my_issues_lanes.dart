import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';

/// The fixed swimlanes of the My Issues board: the ways the current user can
/// be attached to an issue.
///
/// The order here IS the render order, and it mirrors `MY_ROLE_PREDICATES` on
/// the server, which produces these same [wire] keys as lane keys. All six
/// lanes always render, even when empty, so the board's layout is stable.
enum MyIssuesLane {
  watching('watching'),
  assignee('assignee'),
  qa('qa'),
  reviewer('reviewer'),
  reporter('reporter'),
  mentioned('mentioned');

  const MyIssuesLane(this.wire);

  /// Lane key on the wire — also the `my_role` filter value that pages it.
  final String wire;

  static MyIssuesLane? fromWire(String? wire) {
    if (wire == null) return null;
    for (final l in MyIssuesLane.values) {
      if (l.wire == wire) return l;
    }
    return null;
  }

  /// Every lane key, in render order.
  static List<String> get wireKeys => [for (final l in values) l.wire];

  /// The lanes [issue] belongs in for [userId], derived from fields present on
  /// every issue payload — list, delta sync and SSE alike.
  ///
  /// [mentioned] is deliberately absent: it is text-derived and the server
  /// resolves it over comment bodies the client never receives. The cubit
  /// keeps that lane's membership sticky and refetches on comment events
  /// instead — see `TaskBoardCubit._laneKeysFor`.
  static Set<String> structuralKeysFor(Issue issue, String userId) {
    if (userId.isEmpty) return const {};
    return {
      if (issue.watchers.contains(userId)) watching.wire,
      if (issue.assignedTo == userId) assignee.wire,
      if (issue.qaAssigneeId == userId) qa.wire,
      if (issue.reviewerId == userId) reviewer.wire,
      if (issue.ownerId == userId) reporter.wire,
    };
  }
}
