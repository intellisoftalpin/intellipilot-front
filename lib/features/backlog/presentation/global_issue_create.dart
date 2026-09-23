import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/short_links.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/data/project_lookups_cache.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_sheet.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/issue_created_signal.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/issue_edit_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The navigator the global create dialog (or its follow-up sheet) is up on,
/// so a second `c` press or button tap doesn't stack another one. Tied to the
/// navigator rather than a plain flag: if that navigator goes away mid-flow
/// (sign-out, account switch) the pending futures never complete, and a flag
/// would lock the button for good.
NavigatorState? _openOn;

/// Create an issue from anywhere: pick a project (the current one, if any,
/// preselected), a subject and a type, then land in the new issue's detail
/// sheet — the same second step as creating from the Issues page or a board.
Future<void> openGlobalIssueCreate(
  BuildContext context, {
  String? activeProjectRef,
}) async {
  if (_openOn?.mounted ?? false) return;
  final navigator = Navigator.of(context);
  _openOn = navigator;
  try {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Callers hand over the URL's project segment — the project's prefix
    // under short links (`/projects/ps/board`). The dialog preselects by id,
    // so a prefix would silently match nothing and leave the picker empty.
    final initialProjectId = activeProjectRef == null
        ? null
        : await getIt<ShortLinkResolver>().projectId(activeProjectRef);
    if (!context.mounted) return;
    final result = await showIssueCreateWithProjectDialog(
      context,
      loadProjects: _loadProjects,
      loadTarget: loadIssueCreateTarget,
      initialProjectId: initialProjectId,
    );
    final projectId = result?.projectId;
    if (result == null || projectId == null) return;
    final created = (await getIt<BacklogRepository>().createIssue(
      projectId,
      result.request,
    )).valueOrNull;
    if (created == null) {
      messenger?.showSnackBar(SnackBar(content: Text(t.ttActionFailed)));
      return;
    }
    notifyIssueCreated(projectId);
    if (!context.mounted) return;
    await showEntityDetailSheet(
      context,
      projectId: projectId,
      kind: EntityKind.issue,
      entityId: created.id,
    );
    // Whatever was filled in on the sheet should show on the list too.
    notifyIssueCreated(projectId);
  } finally {
    if (identical(_openOn, navigator)) _openOn = null;
  }
}

Future<List<Project>?> _loadProjects() async {
  final projects =
      (await getIt<ProjectsRepository>().listProjects()).valueOrNull;
  if (projects == null) return null;
  return [...projects]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// The picked project's issue types and whether the caller may create there,
/// resolved the same way the project pages gate their own create buttons.
Future<IssueCreateTarget?> loadIssueCreateTarget(String projectId) async {
  final profile = await getIt<ProjectLookupsCache>().currentProfile();
  if (profile == null) return null;
  // Both in flight at once; awaited separately to keep their types.
  final accessFuture = resolveProjectAccess(
    getIt<ProjectsRepository>(),
    projectId: projectId,
    userId: profile.id,
  );
  final typesFuture = getIt<CatalogRepository>().listTaxonomy(
    projectId,
    TaxonomyKind.issueType,
  );
  final access = await accessFuture;
  final types = (await typesFuture).valueOrNull;
  if (types == null) return null;
  return IssueCreateTarget(
    types: types,
    canCreate: access.has(Permission.issueCreate),
  );
}
