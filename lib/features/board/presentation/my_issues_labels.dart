import 'package:flutter/widgets.dart';
import 'package:intellipilot/features/board/domain/my_issues_lanes.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Localised label for a My Issues swimlane. Falls back to the raw key if the
/// server ever sends a lane the client doesn't know.
String myIssuesLaneLabel(BuildContext context, String wire) {
  final t = AppLocalizations.of(context);
  return switch (MyIssuesLane.fromWire(wire)) {
    MyIssuesLane.watching => t.myIssuesLaneWatching,
    MyIssuesLane.assignee => t.myIssuesLaneAssignee,
    MyIssuesLane.qa => t.myIssuesLaneQa,
    MyIssuesLane.reviewer => t.myIssuesLaneReviewer,
    MyIssuesLane.reporter => t.myIssuesLaneReporter,
    MyIssuesLane.mentioned => t.myIssuesLaneMentioned,
    null => wire,
  };
}
