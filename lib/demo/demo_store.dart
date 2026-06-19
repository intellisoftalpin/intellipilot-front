// In-memory data store backing the demo-mode repositories. Seeded with a
// single demo project that exercises every feature the app surfaces.
//
// All entity IDs are stable strings (no UUIDs) so deep links into the demo
// keep working across reloads.

import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/links/data/dtos/link_dtos.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';

/// Mutable in-memory state — every demo repository reads + writes against this
/// single instance. Tests/UI hold references to entities by id.
class DemoStore {
  DemoStore();

  // -- users / sessions ----------------------------------------------------
  late UserProfile currentUser;

  /// Other "members" used in the demo project for assignee filters etc.
  final List<UserProfile> users = [];

  // -- projects + members --------------------------------------------------
  final List<Project> projects = [];
  final Map<String, List<Role>> rolesByProject = {};
  final Map<String, List<Membership>> membersByProject = {};
  final Map<String, List<Invitation>> invitationsByProject = {};

  /// Permissions the demo user has per project — backs `ProjectDetailCubit`
  /// which calls `Project.permissions` indirectly via the wire.
  final Map<String, Set<Permission>> permissionsByProject = {};

  // -- catalog -------------------------------------------------------------
  final Map<String, List<TaxonomyItem>> taxonomyByProject = {};
  final Map<String, List<Label>> labelsByProject = {};
  final Map<String, List<Component>> componentsByProject = {};
  final Map<String, List<Customer>> customersByProject = {};
  final Map<String, List<Release>> releasesByProject = {};

  /// Release versions keyed by release id.
  final Map<String, List<ReleaseVersion>> versionsByRelease = {};

  /// Component→release links keyed by component id.
  final Map<String, List<ComponentReleaseLink>> componentReleases = {};

  /// Issue relationship links keyed by issue id (outgoing entries; the
  /// inverse is rendered for the other side).
  final Map<String, List<IssueLink>> issueLinks = {};

  /// Watcher user ids keyed by issue id.
  final Map<String, List<String>> watchersByIssue = {};

  // -- backlog entities ----------------------------------------------------
  final List<Epic> epics = [];
  final List<Issue> issues = [];

  // -- milestones / wiki / activity ---------------------------------------
  final List<Milestone> milestones = [];
  final List<WikiPage> wikiPages = [];
  final Map<String, List<WikiRevision>> revisionsByPage = {};
  final List<Comment> comments = [];
  final List<HistoryEvent> historyEvents = [];
  final List<Attachment> attachments = [];

  // -- entity links --------------------------------------------------------
  final List<EntityLink> links = [];

  // -- id counters ---------------------------------------------------------
  int _seq = 0;
  String nextId(String prefix) => '$prefix-${++_seq}';

  /// Strong ETag matching the backend's `"<id>:<version>"` shape.
  String etagOf(String id, int version) => '"$id:$version"';
}

/// Seed the store with one demo project that exercises every feature.
void seedDemoStore(DemoStore s) {
  final now = DateTime.now().toUtc();
  const userId = 'user-demo';
  s.currentUser = UserProfile(
    id: userId,
    email: 'demo@intellipilot.local',
    username: 'demo',
    fullName: 'Demo User',
    lang: 'en',
    timezone: 'UTC',
    isActive: true,
    isSuperadmin: true,
    mustChangePassword: false,
    createdAt: now.subtract(const Duration(days: 30)),
  );
  s.users
    ..add(s.currentUser)
    ..add(UserProfile(
      id: 'user-alex',
      email: 'alex@intellipilot.local',
      username: 'alex',
      fullName: 'Alex Stakeholder',
      lang: 'en',
      timezone: 'UTC',
      isActive: true,
      isSuperadmin: false,
      mustChangePassword: false,
      createdAt: now.subtract(const Duration(days: 20)),
    ));

  // ---- project --------------------------------------------------------
  const projectId = 'prj-demo';
  s.projects.add(Project(
    id: projectId,
    slug: 'demo',
    name: 'Demo Project',
    description: 'A scripted project that exercises every feature in '
        'IntelliPilot — backlog, board, milestones, wiki, attachments, '
        'comments and the command palette.',
    ownerId: userId,
    visibility: ProjectVisibility.private,
    kanbanEnabled: true,
    backlogEnabled: true,
    wikiEnabled: true,
    epicsEnabled: true,
    createdAt: now.subtract(const Duration(days: 14)),
  ));
  // Grant the demo user every permission so the UI is fully unlocked.
  s.permissionsByProject[projectId] = Permission.values.toSet();

  // ---- roles + members ------------------------------------------------
  final adminRole = Role(
    id: 'role-admin',
    projectId: projectId,
    slug: 'admin',
    name: 'Administrator',
    order: 0,
    isAdmin: true,
    permissions: Permission.values.toSet(),
  );
  final readerRole = Role(
    id: 'role-reader',
    projectId: projectId,
    slug: 'reader',
    name: 'Reader',
    order: 10,
    isAdmin: false,
    permissions: RolePresets.reader(),
  );
  s.rolesByProject[projectId] = [adminRole, readerRole];
  s.membersByProject[projectId] = [
    Membership(
      id: 'mbr-1',
      projectId: projectId,
      userId: userId,
      roleId: adminRole.id,
      roleSlug: adminRole.slug,
      createdAt: now.subtract(const Duration(days: 14)),
    ),
    Membership(
      id: 'mbr-2',
      projectId: projectId,
      userId: 'user-alex',
      roleId: readerRole.id,
      roleSlug: readerRole.slug,
      createdAt: now.subtract(const Duration(days: 10)),
    ),
  ];
  s.invitationsByProject[projectId] = const [];

  // ---- taxonomy -------------------------------------------------------
  TaxonomyItem t(
    String id,
    TaxonomyKind kind,
    String name,
    String slug,
    String color,
    double order, {
    bool? isClosed,
    double? value,
  }) =>
      TaxonomyItem(
        id: id,
        projectId: projectId,
        kind: kind,
        name: name,
        slug: slug,
        color: color,
        order: order,
        isClosed: isClosed,
        value: value,
        createdAt: now,
      );

  final taxonomy = <TaxonomyItem>[
    // Issue statuses (unified)
    t('us-st-new', TaxonomyKind.issueStatus, 'New', 'new', '#999999', 1, isClosed: false),
    t('us-st-ready', TaxonomyKind.issueStatus, 'Ready', 'ready', '#3b82f6', 2, isClosed: false),
    t('us-st-progress', TaxonomyKind.issueStatus, 'In progress', 'in-progress', '#f59e0b', 3, isClosed: false),
    t('us-st-done', TaxonomyKind.issueStatus, 'Done', 'done', '#10b981', 4, isClosed: true),
    // Issue types
    t('is-ty-story', TaxonomyKind.issueType, 'Story', 'story', '#3b7dd8', 1),
    t('is-ty-task', TaxonomyKind.issueType, 'Task', 'task', '#669900', 2),
    t('is-ty-bug', TaxonomyKind.issueType, 'Bug', 'bug', '#ef4444', 3),
    t('is-ty-question', TaxonomyKind.issueType, 'Question', 'question', '#3b82f6', 4),
    // Priority
    t('pri-low', TaxonomyKind.priority, 'Low', 'low', '#10b981', 1),
    t('pri-medium', TaxonomyKind.priority, 'Medium', 'medium', '#f59e0b', 2),
    t('pri-high', TaxonomyKind.priority, 'High', 'high', '#ef4444', 3),
    t('pri-critical', TaxonomyKind.priority, 'Critical', 'critical', '#b91c1c',
        4),
    t('pri-blocker', TaxonomyKind.priority, 'Blocker', 'blocker', '#7f1d1d', 5),
    // Size (XS..XXL — value is the ordinal driving the scaled badge)
    t('sz-xs', TaxonomyKind.size, 'XS', 'xs', '#10b981', 1, value: 1),
    t('sz-s', TaxonomyKind.size, 'S', 's', '#84cc16', 2, value: 2),
    t('sz-m', TaxonomyKind.size, 'M', 'm', '#f59e0b', 3, value: 3),
    t('sz-l', TaxonomyKind.size, 'L', 'l', '#f97316', 4, value: 4),
    t('sz-xl', TaxonomyKind.size, 'XL', 'xl', '#ef4444', 5, value: 5),
    t('sz-xxl', TaxonomyKind.size, 'XXL', 'xxl', '#b91c1c', 6, value: 6),
  ];
  s.taxonomyByProject[projectId] = taxonomy;

  // ---- labels + components -------------------------------------------
  s.labelsByProject[projectId] = [
    Label(
      id: 'lbl-frontend',
      projectId: projectId,
      name: 'frontend',
      color: '#3b82f6',
      createdAt: now,
    ),
    Label(
      id: 'lbl-backend',
      projectId: projectId,
      name: 'backend',
      color: '#10b981',
      createdAt: now,
    ),
  ];
  s.componentsByProject[projectId] = [
    Component(
      id: 'cmp-web',
      projectId: projectId,
      name: 'Web client',
      color: '#3b82f6',
      createdAt: now,
    ),
    Component(
      id: 'cmp-api',
      projectId: projectId,
      name: 'API',
      color: '#10b981',
      createdAt: now,
    ),
  ];

  // ---- customers ------------------------------------------------------
  s.customersByProject[projectId] = [
    Customer(
      id: 'cust-acme',
      projectId: projectId,
      name: 'Acme Corp',
      companyName: 'Acme Corporation',
      contactEmail: 'ops@acme.example',
      createdAt: now,
    ),
    Customer(
      id: 'cust-globex',
      projectId: projectId,
      name: 'Globex',
      companyName: 'Globex Inc',
      createdAt: now,
    ),
  ];

  // ---- releases + versions + component links --------------------------
  s.releasesByProject[projectId] = [
    Release(
      id: 'rel-psbp',
      projectId: projectId,
      name: 'PSBP',
      description: 'Public sector baseline platform',
      createdAt: now,
    ),
  ];
  s.versionsByRelease['rel-psbp'] = [
    ReleaseVersion(
      id: 'rv-psbp-10',
      releaseId: 'rel-psbp',
      version: '1.0',
      status: 'released',
      notes: '',
      createdAt: now,
    ),
    ReleaseVersion(
      id: 'rv-psbp-11',
      releaseId: 'rel-psbp',
      version: '1.1',
      status: 'in_progress',
      notes: '',
      createdAt: now,
    ),
  ];
  s.componentReleases['cmp-api'] = [
    ComponentReleaseLink(
      componentId: 'cmp-api',
      releaseId: 'rel-psbp',
      releaseName: 'PSBP',
      createdAt: now,
    ),
  ];

  // ---- milestone ------------------------------------------------------
  const milestoneId = 'ms-sprint-1';
  s.milestones.add(Milestone(
    id: milestoneId,
    projectId: projectId,
    name: 'Sprint 1',
    slug: 'sprint-1',
    startDate: now.subtract(const Duration(days: 7)),
    endDate: now.add(const Duration(days: 7)),
    closed: false,
    order: 1,
    version: 1,
    createdAt: now.subtract(const Duration(days: 14)),
    modifiedAt: now.subtract(const Duration(days: 14)),
  ));

  // ---- epics ----------------------------------------------------------
  s.epics.addAll([
    Epic(
      id: 'ep-auth',
      projectId: projectId,
      reference: 1,
      subject: 'Authentication',
      description: 'Sign-in, register, password reset, MFA.',
      color: '#3b82f6',
      order: 1,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('ep-auth', 1),
    ),
    Epic(
      id: 'ep-board',
      projectId: projectId,
      reference: 2,
      subject: 'Project workflows',
      description: 'Backlog, board, milestones, wiki.',
      color: '#10b981',
      order: 2,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('ep-board', 1),
    ),
  ]);

  // ---- backlog issues (stories) --------------------------------------
  s.issues.addAll([
    Issue(
      id: 'us-login',
      projectId: projectId,
      reference: 10,
      subject: 'User can sign in',
      description: 'Email + password login with refresh on 401.',
      statusId: 'us-st-done',
      typeId: 'is-ty-story',
      epicId: 'ep-auth',
      milestoneId: milestoneId,
      sizeId: 'sz-m',
      ownerId: userId,
      assignedTo: userId,
      labels: const [],
      components: const [],
      order: 1,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('us-login', 1),
    ),
    Issue(
      id: 'us-register',
      projectId: projectId,
      reference: 11,
      subject: 'User can create an account',
      description: 'Register form posts to /auth/register.',
      statusId: 'us-st-progress',
      typeId: 'is-ty-story',
      epicId: 'ep-auth',
      milestoneId: milestoneId,
      sizeId: 'sz-l',
      ownerId: userId,
      assignedTo: userId,
      labels: const [],
      components: const [],
      order: 2,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('us-register', 1),
    ),
    Issue(
      id: 'us-backlog',
      projectId: projectId,
      reference: 12,
      subject: 'Backlog page renders epics + issues',
      description: '',
      statusId: 'us-st-ready',
      typeId: 'is-ty-story',
      epicId: 'ep-board',
      milestoneId: milestoneId,
      sizeId: 'sz-m',
      ownerId: userId,
      assignedTo: 'user-alex',
      labels: const [],
      components: const [],
      order: 3,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('us-backlog', 1),
    ),
    Issue(
      id: 'us-wiki',
      projectId: projectId,
      reference: 13,
      subject: 'Wiki editor + revisions',
      description: '',
      statusId: 'us-st-new',
      typeId: 'is-ty-story',
      epicId: 'ep-board',
      sizeId: 'sz-l',
      ownerId: userId,
      labels: const [],
      components: const [],
      order: 4,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('us-wiki', 1),
    ),
  ]);

  // ---- sub-tasks (issues with a parent) ------------------------------
  s.issues.addAll([
    Issue(
      id: 'tk-form',
      projectId: projectId,
      reference: 100,
      subject: 'Build login form widget',
      description: '',
      statusId: 'us-st-done',
      typeId: 'is-ty-task',
      parentId: 'us-login',
      labels: const [],
      components: const [],
      order: 1,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('tk-form', 1),
    ),
    Issue(
      id: 'tk-error',
      projectId: projectId,
      reference: 101,
      subject: 'Handle 401 with refresh hook',
      description: '',
      statusId: 'us-st-done',
      typeId: 'is-ty-task',
      parentId: 'us-login',
      labels: const [],
      components: const [],
      order: 2,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('tk-error', 1),
    ),
    Issue(
      id: 'tk-register',
      projectId: projectId,
      reference: 102,
      subject: 'Register page validation',
      description: '',
      statusId: 'us-st-new',
      typeId: 'is-ty-task',
      parentId: 'us-register',
      labels: const [],
      components: const [],
      order: 1,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('tk-register', 1),
    ),
  ]);

  // ---- issues ---------------------------------------------------------
  s.issues.addAll([
    Issue(
      id: 'iss-1',
      projectId: projectId,
      reference: 200,
      subject: 'Reset password link expires too soon',
      description: 'Customer feedback from beta — 15-minute window is too short.',
      statusId: 'us-st-progress',
      typeId: 'is-ty-bug',
      priorityId: 'pri-high',
      sizeId: 'sz-l',
      category: 'customer_request',
      customerId: 'cust-acme',
      labels: const ['lbl-backend'],
      components: const ['cmp-api'],
      ownerId: userId,
      assignedTo: userId,
      order: 5,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('iss-1', 1),
    ),
    Issue(
      id: 'iss-2',
      projectId: projectId,
      reference: 201,
      subject: 'Dark theme contrast on cards',
      description: '',
      statusId: 'us-st-done',
      typeId: 'is-ty-bug',
      priorityId: 'pri-low',
      sizeId: 'sz-s',
      category: 'technical_debt',
      labels: const ['lbl-frontend'],
      components: const ['cmp-web'],
      order: 6,
      version: 1,
      createdAt: now,
      modifiedAt: now,
      etag: s.etagOf('iss-2', 1),
    ),
  ]);

  // ---- links ----------------------------------------------------------
  // Seed three so the panel has visible state to play with:
  //   • US-login `blocks` US-backlog (dependency)
  //   • T-form   `relates to` US-login (symmetric)
  //   • iss-1    `duplicates` iss-2 (directional)
  s.links.addAll([
    EntityLink(
      id: 'lnk-1',
      projectId: projectId,
      sourceKind: EntityKind.issue,
      sourceId: 'us-login',
      targetKind: EntityKind.issue,
      targetId: 'us-backlog',
      type: LinkType.blocks,
      createdAt: now,
    ),
    EntityLink(
      id: 'lnk-2',
      projectId: projectId,
      sourceKind: EntityKind.issue,
      sourceId: 'tk-form',
      targetKind: EntityKind.issue,
      targetId: 'us-login',
      type: LinkType.relates,
      createdAt: now,
    ),
    EntityLink(
      id: 'lnk-3',
      projectId: projectId,
      sourceKind: EntityKind.issue,
      sourceId: 'iss-1',
      targetKind: EntityKind.issue,
      targetId: 'iss-2',
      type: LinkType.duplicates,
      createdAt: now,
    ),
  ]);

  // ---- wiki -----------------------------------------------------------
  const welcomeBody = '''
# Welcome to the IntelliPilot demo

This project is seeded entirely from in-memory data — there's no backend
process behind it. Click around: every page, dialog, and shortcut works.

## What works

- Backlog, board, milestones, issues
- Comments + history on every backlog entity
- Wiki edit + revisions + diff
- Search via the Cmd-K palette (try `#10` or `welcome`)

## What's faked

- Attachments upload pretends to succeed but stays in-memory
- The session never expires (no refresh round-trip)
- Mutations vanish on a hard reload

Have fun.
''';
  final welcomePage = WikiPage(
    id: 'wp-welcome',
    projectId: projectId,
    slug: 'welcome',
    title: 'Welcome',
    body: welcomeBody,
    bodyHtml: '<p>Welcome to the IntelliPilot demo.</p>',
    version: 1,
    editorId: userId,
    createdAt: now.subtract(const Duration(days: 7)),
    modifiedAt: now.subtract(const Duration(days: 7)),
    etag: s.etagOf('wp-welcome', 1),
  );
  s.wikiPages.add(welcomePage);
  s.revisionsByPage['wp-welcome'] = [
    WikiRevision(
      id: 'wpr-1',
      pageId: 'wp-welcome',
      rev: 1,
      title: 'Welcome',
      body: welcomeBody,
      editorId: userId,
      createdAt: now.subtract(const Duration(days: 7)),
    ),
  ];

  // ---- one comment + one history entry on us-login --------------------
  s.comments.add(Comment(
    id: 'cm-1',
    targetType: 'user_story',
    targetId: 'us-login',
    authorId: 'user-alex',
    body: 'Looks good — shipped to staging.',
    bodyHtml: '<p>Looks good — shipped to staging.</p>',
    editedAt: null,
    createdAt: now.subtract(const Duration(hours: 6)),
  ));
  s.historyEvents.add(HistoryEvent(
    diff: const {
      'status_id': ['us-st-progress', 'us-st-done'],
    },
    actorId: userId,
    createdAt: now.subtract(const Duration(hours: 8)),
  ));
}
