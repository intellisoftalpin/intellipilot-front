import 'package:flutter/foundation.dart';

/// An issue created away from the page that lists it.
///
/// A fresh instance per creation, so listeners fire even when the same
/// project gets two issues in a row.
class IssueCreatedSignal {
  IssueCreatedSignal(this.projectId);
  final String projectId;
}

/// Raised by the global Create flow (top-bar button, `c` shortcut) — which no
/// page awaits — so the Issues and Backlog lists underneath can reload.
///
/// The board and the rail counts don't need this: they follow the project's
/// live event feed, where the creation arrives as `issue.created`. The plain
/// lists have no live subscription and would otherwise stay stale until
/// revisited.
final ValueNotifier<IssueCreatedSignal?> issueCreatedSignal =
    ValueNotifier<IssueCreatedSignal?>(null);

void notifyIssueCreated(String projectId) =>
    issueCreatedSignal.value = IssueCreatedSignal(projectId);
