import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_page.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Full-page issue view reached by a human-readable key URL
/// (`/projects/{id}/issues/PS-398`). Resolves the trailing numeric ref to the
/// issue id, then renders the same [EntityDetailPage] used by the side sheet.
class IssueKeyPage extends StatefulWidget {
  const IssueKeyPage({
    required this.projectId,
    required this.issueKey,
    super.key,
  });

  final String projectId;

  /// The key as it appears in the URL, e.g. `PS-398` (or just `398`).
  final String issueKey;

  @override
  State<IssueKeyPage> createState() => _IssueKeyPageState();
}

class _IssueKeyPageState extends State<IssueKeyPage> {
  late Future<Issue?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  /// Extract the trailing numeric ref from a key like `PS-398` / `398`.
  int? get _ref => int.tryParse(widget.issueKey.split('-').last.trim());

  Future<Issue?> _resolve() async {
    final ref = _ref;
    if (ref == null) return null;
    final res = await getIt<BacklogRepository>().getIssueByRef(
      widget.projectId,
      ref,
    );
    return res.valueOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Issue?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final issue = snapshot.data;
        if (issue == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(AppLocalizations.of(context).issueNotFound),
            ),
          );
        }
        return EntityDetailPage(
          projectId: widget.projectId,
          kind: EntityKind.issue,
          entityId: issue.id,
        );
      },
    );
  }
}
