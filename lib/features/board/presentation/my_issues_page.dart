import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/board/domain/board_source.dart';
import 'package:intellipilot/features/board/presentation/board_page.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The My Issues board: one swimlane per way the signed-in user is attached to
/// an issue — watching, assignee, QA, reviewer, requestor, mentioned.
///
/// This is a [BoardPage] over a synthetic board ([LocalBoardSource]): there is
/// no server-side board row to create, share or delete, so only the column
/// layout is configurable and it lives in local storage. Everything else — the
/// snapshot cache, delta sync, live events, drag-to-change-status, per-column
/// paging, the shared filter bar — is the ordinary board machinery.
class MyIssuesPage extends StatelessWidget {
  const MyIssuesPage({required this.projectId, super.key});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final title = AppLocalizations.of(context).myIssuesTitle;
    return BoardPage(
      projectId: projectId,
      boardId: LocalBoardSource.myIssuesBoardId,
      titleOverride: title,
      sourceBuilder: (profile) => LocalBoardSource(
        storage: getIt(instanceName: HiveBoxes.ui),
        projectId: projectId,
        userId: profile.id,
        name: title,
      ),
    );
  }
}
