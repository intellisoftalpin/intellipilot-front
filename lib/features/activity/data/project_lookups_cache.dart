// Private fields can't be named constructor parameters, so the initializing
// formal the linter wants isn't expressible here.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:intellipilot/core/models/intellibot.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

/// Every project-scoped reference collection the entity detail page needs to
/// render names, colours and picker candidates.
///
/// These change rarely (taxonomy, labels, components, members, milestones) or
/// only matter as a lookup table (epics, issues), so they are fetched once per
/// project and reused — rather than re-fetched on every field edit.
class ProjectLookups {
  ProjectLookups({
    required this.project,
    required this.taxonomyById,
    required this.labelsById,
    required this.componentsById,
    required this.epicsById,
    required this.milestonesById,
    required this.issuesById,
    required this.customersById,
    required this.membersById,
    required this.releaseVersionsById,
  });

  final Project project;
  final Map<String, TaxonomyItem> taxonomyById;
  final Map<String, Label> labelsById;
  final Map<String, Component> componentsById;
  final Map<String, Epic> epicsById;
  final Map<String, Milestone> milestonesById;
  final Map<String, Issue> issuesById;
  final Map<String, Customer> customersById;
  final Map<String, UserRef> membersById;
  final Map<String, ReleaseVersionRef> releaseVersionsById;
}

class _Entry {
  _Entry(this.value, this.fetchedAt);
  final ProjectLookups value;
  final DateTime fetchedAt;
}

/// Session cache for [ProjectLookups], keyed by project id.
///
/// Before this existed, every inline field edit on the detail page triggered a
/// full re-fetch of all of the above — including `listIssues`, i.e. every issue
/// in the project — just to redraw one changed value. Now a field edit costs
/// the PATCH alone; the lookups come from here.
///
/// Freshness is handled three ways, in order of preference:
///  * live SSE events patch individual entries in place ([applyIssue],
///    [applyEpic], [removeIssue]),
///  * an edit that provably changes a lookup invalidates that project,
///  * a [_ttl] backstop covers anything missed.
class ProjectLookupsCache {
  ProjectLookupsCache({
    required ProfileRepository profile,
    required ProjectsRepository projects,
    required CatalogRepository catalog,
    required BacklogRepository backlog,
    required MilestonesRepository milestones,
  }) : _profile = profile,
       _projects = projects,
       _catalog = catalog,
       _backlog = backlog,
       _milestones = milestones;

  static const _ttl = Duration(minutes: 5);

  final ProfileRepository _profile;
  final ProjectsRepository _projects;
  final CatalogRepository _catalog;
  final BacklogRepository _backlog;
  final MilestonesRepository _milestones;

  final Map<String, _Entry> _byProject = {};

  /// De-dupes concurrent misses: opening two issues at once must not fire two
  /// identical lookup storms.
  final Map<String, Future<ProjectLookups?>> _inflight = {};

  UserProfile? _cachedProfile;

  /// The signed-in user. Not project-scoped, but equally static for the
  /// session and fetched on the same code path, so it is memoised here too.
  Future<UserProfile?> currentProfile() async {
    final cached = _cachedProfile;
    if (cached != null) return cached;
    final res = await _profile.getProfile();
    return _cachedProfile = res.valueOrNull;
  }

  bool _isFresh(_Entry e) =>
      DateTime.now().difference(e.fetchedAt).compareTo(_ttl) < 0;

  /// Cached lookups for [projectId], fetching on a miss / staleness.
  Future<ProjectLookups?> get(
    String projectId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final hit = _byProject[projectId];
      if (hit != null && _isFresh(hit)) return hit.value;
      final pending = _inflight[projectId];
      if (pending != null) return pending;
    }
    final future = _fetch(projectId);
    _inflight[projectId] = future;
    try {
      final value = await future;
      if (value != null) {
        _byProject[projectId] = _Entry(value, DateTime.now());
      }
      return value;
    } finally {
      // Dropping the in-flight future, not awaiting it — it already completed.
      unawaited(_inflight.remove(projectId));
    }
  }

  /// Whatever is cached right now, without triggering a fetch. Used by live
  /// event handlers, which must not cause network traffic.
  ProjectLookups? peek(String projectId) => _byProject[projectId]?.value;

  void invalidate(String projectId) {
    _byProject.remove(projectId);
    unawaited(_inflight.remove(projectId));
  }

  void clear() {
    _byProject.clear();
    _inflight.clear();
    _cachedProfile = null;
  }

  /// Fold a live (or freshly saved) issue into the cached lookup table.
  void applyIssue(String projectId, Issue issue) {
    _byProject[projectId]?.value.issuesById[issue.id] = issue;
  }

  void removeIssue(String projectId, String issueId) {
    _byProject[projectId]?.value.issuesById.remove(issueId);
  }

  void applyEpic(String projectId, Epic epic) {
    _byProject[projectId]?.value.epicsById[epic.id] = epic;
  }

  void removeEpic(String projectId, String epicId) {
    _byProject[projectId]?.value.epicsById.remove(epicId);
  }

  Future<ProjectLookups?> _fetch(String projectId) async {
    final project = (await _projects.getProject(projectId)).valueOrNull;
    if (project == null) return null;

    final results = await Future.wait<dynamic>([
      _catalog.listTaxonomy(projectId, TaxonomyKind.issueStatus),
      _catalog.listTaxonomy(projectId, TaxonomyKind.issueType),
      _catalog.listTaxonomy(projectId, TaxonomyKind.priority),
      _catalog.listTaxonomy(projectId, TaxonomyKind.size),
      _catalog.listLabels(projectId),
      _catalog.listComponents(projectId),
      _backlog.listEpics(projectId),
      _milestones.list(projectId),
      _backlog.listIssues(projectId),
      _catalog.listCustomers(projectId),
      _projects.listMembers(projectId),
      _catalog.listAllReleaseVersions(projectId),
    ]);

    List<T> at<T>(int i) =>
        (results[i] as dynamic).valueOrNull as List<T>? ?? <T>[];

    return ProjectLookups(
      project: project,
      taxonomyById: {
        for (final t in [
          ...at<TaxonomyItem>(0),
          ...at<TaxonomyItem>(1),
          ...at<TaxonomyItem>(2),
          ...at<TaxonomyItem>(3),
        ])
          t.id: t,
      },
      labelsById: {for (final l in at<Label>(4)) l.id: l},
      componentsById: {for (final c in at<Component>(5)) c.id: c},
      epicsById: {for (final e in at<Epic>(6)) e.id: e},
      milestonesById: {for (final m in at<Milestone>(7)) m.id: m},
      issuesById: {for (final i in at<Issue>(8)) i.id: i},
      customersById: {for (final c in at<Customer>(9)) c.id: c},
      membersById: {
        for (final m in at<Membership>(10)) m.userId: m.toRef(),
        // INTELLIBOT is the actor for app-token actions but never a project
        // member — inject it so owner/author rows resolve to its identity.
        kIntellibotUserId: intellibotRef(),
      },
      releaseVersionsById: {
        for (final v in at<ReleaseVersionRef>(11)) v.id: v,
      },
    );
  }
}
