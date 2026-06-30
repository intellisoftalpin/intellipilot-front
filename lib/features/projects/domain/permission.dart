/// All atomic permissions defined in the backend's `intellipilot_core::perms`
/// (53 entries). Names match the wire strings exactly so we can round-trip
/// without mapping tables.
enum Permission {
  // Project
  projectView('project.view', PermissionDomain.project),
  projectModify('project.modify', PermissionDomain.project),
  projectDelete('project.delete', PermissionDomain.project),
  projectAdmin('project.admin', PermissionDomain.project),

  // Members
  memberView('member.view', PermissionDomain.members),
  memberAdd('member.add', PermissionDomain.members),
  memberRemove('member.remove', PermissionDomain.members),
  memberModifyRole('member.modify_role', PermissionDomain.members),

  // Roles
  roleView('role.view', PermissionDomain.roles),
  roleCreate('role.create', PermissionDomain.roles),
  roleModify('role.modify', PermissionDomain.roles),
  roleDelete('role.delete', PermissionDomain.roles),

  // Epics
  epicView('epic.view', PermissionDomain.epics),
  epicCreate('epic.create', PermissionDomain.epics),
  epicModify('epic.modify', PermissionDomain.epics),
  epicDelete('epic.delete', PermissionDomain.epics),

  // Issues (user stories and tasks were merged into the unified issue type;
  // their old us.* / task.* permissions no longer exist).
  issueView('issue.view', PermissionDomain.issues),
  issueCreate('issue.create', PermissionDomain.issues),
  issueModify('issue.modify', PermissionDomain.issues),
  issueDelete('issue.delete', PermissionDomain.issues),

  // Milestones
  milestoneView('milestone.view', PermissionDomain.milestones),
  milestoneCreate('milestone.create', PermissionDomain.milestones),
  milestoneModify('milestone.modify', PermissionDomain.milestones),
  milestoneDelete('milestone.delete', PermissionDomain.milestones),

  // Wiki
  wikiView('wiki.view', PermissionDomain.wiki),
  wikiCreate('wiki.create', PermissionDomain.wiki),
  wikiModify('wiki.modify', PermissionDomain.wiki),
  wikiDelete('wiki.delete', PermissionDomain.wiki),

  // Comments & attachments
  commentCreate('comment.create', PermissionDomain.commentsAndAttachments),
  commentModerate('comment.moderate', PermissionDomain.commentsAndAttachments),
  attachmentCreate(
    'attachment.create',
    PermissionDomain.commentsAndAttachments,
  ),
  attachmentDelete(
    'attachment.delete',
    PermissionDomain.commentsAndAttachments,
  ),

  // Time tracking
  timeLog('time.log', PermissionDomain.timeTracking),
  timeViewAll('time.view_all', PermissionDomain.timeTracking),
  timeManage('time.manage', PermissionDomain.timeTracking),

  // Taxonomy (issue types, priorities, sizes, statuses, resolutions)
  taxonomyCreate('taxonomy.create', PermissionDomain.taxonomy),
  taxonomyModify('taxonomy.modify', PermissionDomain.taxonomy),
  taxonomyDelete('taxonomy.delete', PermissionDomain.taxonomy),

  // Labels
  labelCreate('label.create', PermissionDomain.labels),
  labelModify('label.modify', PermissionDomain.labels),
  labelDelete('label.delete', PermissionDomain.labels),

  // Components
  componentCreate('component.create', PermissionDomain.components),
  componentModify('component.modify', PermissionDomain.components),
  componentDelete('component.delete', PermissionDomain.components),

  // Repositories (incl. SSH keys and component links)
  repositoryCreate('repository.create', PermissionDomain.repositories),
  repositoryModify('repository.modify', PermissionDomain.repositories),
  repositoryDelete('repository.delete', PermissionDomain.repositories),

  // Customers
  customerCreate('customer.create', PermissionDomain.customers),
  customerModify('customer.modify', PermissionDomain.customers),
  customerDelete('customer.delete', PermissionDomain.customers),

  // Releases (incl. versions and component links)
  releaseCreate('release.create', PermissionDomain.releases),
  releaseModify('release.modify', PermissionDomain.releases),
  releaseDelete('release.delete', PermissionDomain.releases),

  // Shared boards (personal boards need only project.view)
  boardSharedCreate('board.shared.create', PermissionDomain.boards),
  boardSharedModify('board.shared.modify', PermissionDomain.boards),
  boardSharedDelete('board.shared.delete', PermissionDomain.boards);

  const Permission(this.wire, this.domain);
  final String wire;
  final PermissionDomain domain;

  static Permission? fromWire(String wire) {
    for (final p in Permission.values) {
      if (p.wire == wire) return p;
    }
    return null;
  }
}

enum PermissionDomain {
  project,
  members,
  roles,
  epics,
  issues,
  milestones,
  wiki,
  commentsAndAttachments,
  timeTracking,
  taxonomy,
  labels,
  components,
  repositories,
  customers,
  releases,
  boards,
}

/// Built-in preset permission sets matching the backend's default roles. Used
/// by the role editor's bulk-toggle buttons. These mirror `default_roles()`
/// in `intellipilot_core::perms` but exclude `project.admin` from the Admin
/// preset because that flag is enforced via a separate `is_admin` column —
/// the UI only edits the permissions vector.
abstract final class RolePresets {
  /// All view permissions (the stakeholder baseline).
  static Set<Permission> reader() =>
      Permission.values.where((p) => p.wire.endsWith('.view')).toSet();

  /// Developer: view everything, create/modify work items + comments/
  /// attachments. No delete, no project/member/role admin.
  static Set<Permission> contributor() {
    final base = reader();
    base.addAll(const [
      Permission.epicCreate,
      Permission.epicModify,
      Permission.issueCreate,
      Permission.issueModify,
      Permission.milestoneCreate,
      Permission.milestoneModify,
      Permission.wikiCreate,
      Permission.wikiModify,
      Permission.commentCreate,
      Permission.attachmentCreate,
      Permission.attachmentDelete,
      Permission.timeLog,
    ]);
    return base;
  }

  /// Product owner: contributor set + member/role management + delete on
  /// work items + comment moderation + project.modify.
  static Set<Permission> maintainer() {
    final base = contributor();
    base.addAll(const [
      Permission.projectModify,
      Permission.memberView,
      Permission.memberAdd,
      Permission.memberRemove,
      Permission.memberModifyRole,
      Permission.roleView,
      Permission.roleCreate,
      Permission.roleModify,
      Permission.roleDelete,
      Permission.epicDelete,
      Permission.issueDelete,
      Permission.milestoneDelete,
      Permission.wikiDelete,
      Permission.commentModerate,
      Permission.timeViewAll,
      // Project-configuration entities.
      Permission.taxonomyCreate,
      Permission.taxonomyModify,
      Permission.taxonomyDelete,
      Permission.labelCreate,
      Permission.labelModify,
      Permission.labelDelete,
      Permission.componentCreate,
      Permission.componentModify,
      Permission.componentDelete,
      Permission.repositoryCreate,
      Permission.repositoryModify,
      Permission.repositoryDelete,
      Permission.customerCreate,
      Permission.customerModify,
      Permission.customerDelete,
      Permission.releaseCreate,
      Permission.releaseModify,
      Permission.releaseDelete,
      Permission.boardSharedCreate,
      Permission.boardSharedModify,
      Permission.boardSharedDelete,
    ]);
    return base;
  }

  /// Administrator: every permission.
  static Set<Permission> admin() => Permission.values.toSet();
}
