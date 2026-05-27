/// All 40 atomic permissions defined in the backend's `intellipilot_core::perms`.
/// Names match the wire strings exactly so we can round-trip without mapping
/// tables.
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

  // User stories
  usView('us.view', PermissionDomain.userStories),
  usCreate('us.create', PermissionDomain.userStories),
  usModify('us.modify', PermissionDomain.userStories),
  usDelete('us.delete', PermissionDomain.userStories),

  // Tasks
  taskView('task.view', PermissionDomain.tasks),
  taskCreate('task.create', PermissionDomain.tasks),
  taskModify('task.modify', PermissionDomain.tasks),
  taskDelete('task.delete', PermissionDomain.tasks),

  // Issues
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
  );

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
  userStories,
  tasks,
  issues,
  milestones,
  wiki,
  commentsAndAttachments,
}

/// Built-in preset permission sets matching the backend's default roles. Used
/// by the role editor's bulk-toggle buttons. These mirror `default_roles()`
/// in `intellipilot_core::perms` but exclude `project.admin` from the Admin
/// preset because that flag is enforced via a separate `is_admin` column —
/// the UI only edits the permissions vector.
abstract final class RolePresets {
  /// All view permissions (the stakeholder baseline).
  static Set<Permission> reader() => Permission.values
      .where((p) => p.wire.endsWith('.view'))
      .toSet();

  /// Developer: view everything, create/modify work items + comments/
  /// attachments. No delete, no project/member/role admin.
  static Set<Permission> contributor() {
    final base = reader();
    base.addAll(const [
      Permission.epicCreate,
      Permission.epicModify,
      Permission.usCreate,
      Permission.usModify,
      Permission.taskCreate,
      Permission.taskModify,
      Permission.issueCreate,
      Permission.issueModify,
      Permission.milestoneCreate,
      Permission.milestoneModify,
      Permission.wikiCreate,
      Permission.wikiModify,
      Permission.commentCreate,
      Permission.attachmentCreate,
      Permission.attachmentDelete,
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
      Permission.usDelete,
      Permission.taskDelete,
      Permission.issueDelete,
      Permission.milestoneDelete,
      Permission.wikiDelete,
      Permission.commentModerate,
    ]);
    return base;
  }

  /// Administrator: every permission.
  static Set<Permission> admin() => Permission.values.toSet();
}
