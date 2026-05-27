import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/components_tab.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/labels_tab.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/taxonomy_tab.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/invitations_cubit.dart';
import 'package:intellipilot/features/projects/presentation/cubits/members_cubit.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_settings_cubit.dart';
import 'package:intellipilot/features/projects/presentation/cubits/roles_cubit.dart';
import 'package:intellipilot/features/projects/presentation/widgets/permission_gate.dart';
import 'package:intellipilot/features/projects/presentation/widgets/role_editor.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class ProjectSettingsPage extends StatelessWidget {
  const ProjectSettingsPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final repo = getIt<ProjectsRepository>();
    return FutureBuilder<UserProfile?>(
      future: getIt<ProfileRepository>().getProfile().then(
        (r) => r.valueOrNull,
      ),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) {
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).errUnknown),
            ),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider<ProjectDetailCubit>(
              create: (_) => ProjectDetailCubit(
                repo: repo,
                projectId: projectId,
                currentUserId: profile.id,
              )..load(),
            ),
            BlocProvider<ProjectSettingsCubit>(
              create: (_) =>
                  ProjectSettingsCubit(repo: repo, projectId: projectId),
            ),
            BlocProvider<MembersCubit>(
              create: (_) =>
                  MembersCubit(repo: repo, projectId: projectId)..load(),
            ),
            BlocProvider<RolesCubit>(
              create: (_) =>
                  RolesCubit(repo: repo, projectId: projectId)..load(),
            ),
            BlocProvider<InvitationsCubit>(
              create: (_) =>
                  InvitationsCubit(repo: repo, projectId: projectId)..load(),
            ),
          ],
          child: _SettingsView(projectId: projectId),
        );
      },
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
            builder: (_, s) => Text(
              s is ProjectDetailLoaded
                  ? '${s.project.name} · ${t.projectSettingsTitle}'
                  : t.projectSettingsTitle,
            ),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: t.tabGeneral),
              Tab(text: t.tabMembers),
              Tab(text: t.tabRoles),
              Tab(text: t.tabTaxonomy),
              Tab(text: t.tabLabels),
              Tab(text: t.tabComponents),
              Tab(text: t.tabDangerZone),
            ],
          ),
        ),
        body: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
          builder: (context, state) {
            if (state is ProjectDetailLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is ProjectDetailFailed) {
              return Center(
                child: Text(t.projectLoadFailed),
              );
            }
            if (state is ProjectDetailLoaded) {
              return TabBarView(
                children: [
                  _GeneralTab(state: state),
                  _MembersTab(state: state),
                  _RolesTab(state: state),
                  TaxonomyTab(projectId: projectId),
                  LabelsTab(projectId: projectId),
                  ComponentsTab(projectId: projectId),
                  _DangerZoneTab(state: state),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// General tab
// ---------------------------------------------------------------------------

class _GeneralTab extends StatefulWidget {
  const _GeneralTab({required this.state});
  final ProjectDetailLoaded state;

  @override
  State<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<_GeneralTab> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late ProjectVisibility _visibility;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.state.project.name);
    _desc = TextEditingController(text: widget.state.project.description);
    _visibility = widget.state.project.visibility;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _canEdit => widget.state.has(Permission.projectModify);

  Future<void> _save() async {
    final patch = UpdateProjectRequest(
      name: _name.text.trim(),
      description: _desc.text.trim(),
      visibility: _visibility,
    );
    final updated =
        await context.read<ProjectSettingsCubit>().save(patch);
    if (!mounted) return;
    if (updated != null) {
      context.read<ProjectDetailCubit>().replace(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).projectSavedSnack)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _name,
          enabled: _canEdit,
          decoration: InputDecoration(labelText: t.projectFieldName),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _desc,
          enabled: _canEdit,
          maxLines: 4,
          decoration: InputDecoration(labelText: t.projectFieldDescription),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ProjectVisibility>(
          initialValue: _visibility,
          decoration: InputDecoration(labelText: t.projectFieldVisibility),
          items: [
            DropdownMenuItem(
              value: ProjectVisibility.private,
              child: Text(t.projectVisibilityPrivate),
            ),
            DropdownMenuItem(
              value: ProjectVisibility.internal,
              child: Text(t.projectVisibilityInternal),
            ),
            DropdownMenuItem(
              value: ProjectVisibility.publicReadonly,
              child: Text(t.projectVisibilityPublicReadonly),
            ),
          ],
          onChanged: _canEdit
              ? (v) => setState(() => _visibility = v ?? _visibility)
              : null,
        ),
        const SizedBox(height: 24),
        BlocBuilder<ProjectSettingsCubit, ProjectSettingsState>(
          builder: (context, s) {
            final saving = s is ProjectSettingsSaving;
            return FilledButton(
              onPressed: !_canEdit || saving ? null : _save,
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.actionSave),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Members tab
// ---------------------------------------------------------------------------

class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.state});
  final ProjectDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<MembersCubit, MembersState>(
      builder: (context, m) {
        if (m is MembersLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (m is MembersFailed) {
          return Center(child: Text(t.membersLoadFailed));
        }
        if (m is! MembersLoaded) return const SizedBox.shrink();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const PermissionGate(
              permission: Permission.memberAdd,
              child: _InviteCard(),
            ),
            const SizedBox(height: 16),
            Text(
              t.membersTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final member in m.members)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(member.userId),
                  subtitle: Text(member.roleSlug),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      PermissionGate(
                        permission: Permission.memberModifyRole,
                        child: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: t.memberChangeRoleTooltip,
                          onPressed: () => _showRoleDialog(
                            context,
                            member.userId,
                            member.roleSlug,
                            m.roles,
                          ),
                        ),
                      ),
                      PermissionGate(
                        permission: Permission.memberRemove,
                        child: IconButton(
                          icon: const Icon(Icons.person_remove_outlined),
                          tooltip: t.memberRemoveTooltip,
                          onPressed: () => _confirmRemove(context, member.userId),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const _PendingInvitations(),
          ],
        );
      },
    );
  }

  Future<void> _showRoleDialog(
    BuildContext context,
    String userId,
    String currentSlug,
    List<Role> roles,
  ) async {
    final t = AppLocalizations.of(context);
    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        var slug = currentSlug;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(t.memberChangeRoleTitle),
            content: DropdownButton<String>(
              value: slug,
              isExpanded: true,
              items: [
                for (final r in roles)
                  DropdownMenuItem(value: r.slug, child: Text(r.name)),
              ],
              onChanged: (v) => setState(() => slug = v ?? slug),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(t.actionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(slug),
                child: Text(t.actionApply),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && context.mounted) {
      await context.read<MembersCubit>().changeRole(userId, picked);
    }
  }

  Future<void> _confirmRemove(BuildContext context, String userId) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.memberRemoveTitle),
        content: Text(t.memberRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionRemove),
          ),
        ],
      ),
    );
    if ((ok ?? false) && context.mounted) {
      await context.read<MembersCubit>().remove(userId);
    }
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: BlocBuilder<RolesCubit, RolesState>(
          builder: (context, rs) {
            final roles =
                rs is RolesLoaded ? rs.roles : const <Role>[];
            return Row(
              children: [
                Icon(
                  Icons.mail_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t.membersInviteBody)),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  onPressed: roles.isEmpty
                      ? null
                      : () => _showInviteDialog(context, roles),
                  label: Text(t.actionInviteMember),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showInviteDialog(
    BuildContext context,
    List<Role> roles,
  ) async {
    final t = AppLocalizations.of(context);
    final emailCtrl = TextEditingController();
    var slug = roles.first.slug;
    final cubit = context.read<InvitationsCubit>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t.actionInviteMember),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  autofocus: true,
                  decoration: InputDecoration(labelText: t.fieldEmail),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: slug,
                  decoration: InputDecoration(labelText: t.memberRoleLabel),
                  items: [
                    for (final r in roles)
                      DropdownMenuItem(value: r.slug, child: Text(r.name)),
                  ],
                  onChanged: (v) => setState(() => slug = v ?? slug),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.actionCancel),
            ),
            FilledButton(
              onPressed: () async {
                final email = emailCtrl.text.trim();
                if (email.isEmpty) return;
                await cubit.invite(email: email, roleSlug: slug);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(t.actionSend),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingInvitations extends StatelessWidget {
  const _PendingInvitations();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocConsumer<InvitationsCubit, InvitationsState>(
      listenWhen: (prev, next) =>
          next is InvitationsLoaded && next.lastInviteToken != null,
      listener: (context, state) {
        if (state is InvitationsLoaded && state.lastInviteToken != null) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(t.invitationTokenDialogTitle),
              content: SelectableText(state.lastInviteToken!),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: state.lastInviteToken!),
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: Text(t.actionCopy),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(t.actionDone),
                ),
              ],
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is! InvitationsLoaded) return const SizedBox.shrink();
        if (state.invitations.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.invitationsPendingTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final inv in state.invitations)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(inv.email),
                  subtitle: Text(inv.createdAt.toLocal().toString()),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Roles tab
// ---------------------------------------------------------------------------

class _RolesTab extends StatelessWidget {
  const _RolesTab({required this.state});
  final ProjectDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canModify = state.has(Permission.roleModify);
    final canCreate = state.has(Permission.roleCreate);
    final canDelete = state.has(Permission.roleDelete);

    return BlocBuilder<RolesCubit, RolesState>(
      builder: (context, rs) {
        if (rs is RolesLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rs is RolesFailed) {
          return Center(child: Text(t.rolesLoadFailed));
        }
        if (rs is! RolesLoaded) return const SizedBox.shrink();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canCreate)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _showCreateDialog(context),
                  icon: const Icon(Icons.add),
                  label: Text(t.actionNewRole),
                ),
              ),
            const SizedBox(height: 8),
            for (final role in rs.roles)
              Card(
                child: ExpansionTile(
                  title: Text(role.name),
                  subtitle: Text(
                    role.isAdmin
                        ? t.roleAdminBadge
                        : '${role.permissions.length} ${t.rolePermissionsSuffix}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: _RoleEditorBlock(
                        role: role,
                        canModify: canModify && !role.isAdmin,
                        canDelete: canDelete && !role.isAdmin,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final slugCtrl = TextEditingController();
    var perms = RolePresets.contributor();
    final cubit = context.read<RolesCubit>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t.actionNewRole),
          content: SizedBox(
            width: 560,
            height: 460,
            child: Column(
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: t.roleFieldName),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: slugCtrl,
                  decoration: InputDecoration(
                    labelText: t.roleFieldSlug,
                    helperText: t.roleFieldSlugHint,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: RoleEditor(
                      selected: perms,
                      onChanged: (s) => setState(() => perms = s),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.actionCancel),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final slug = slugCtrl.text.trim();
                if (name.isEmpty || slug.isEmpty) return;
                await cubit.create(
                  name: name,
                  slug: slug,
                  permissions: perms,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(t.actionCreate),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleEditorBlock extends StatefulWidget {
  const _RoleEditorBlock({
    required this.role,
    required this.canModify,
    required this.canDelete,
  });
  final Role role;
  final bool canModify;
  final bool canDelete;

  @override
  State<_RoleEditorBlock> createState() => _RoleEditorBlockState();
}

class _RoleEditorBlockState extends State<_RoleEditorBlock> {
  late Set<Permission> _perms;

  @override
  void initState() {
    super.initState();
    _perms = Set.from(widget.role.permissions);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoleEditor(
          selected: _perms,
          onChanged: (s) => setState(() => _perms = s),
          readOnly: !widget.canModify,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.canDelete)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context),
                label: Text(t.actionDelete),
              ),
            const SizedBox(width: 8),
            if (widget.canModify)
              FilledButton(
                onPressed: () => context
                    .read<RolesCubit>()
                    .updatePermissions(widget.role.id, _perms),
                child: Text(t.actionSave),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.roleDeleteTitle),
        content: Text(t.roleDeleteConfirm(widget.role.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if ((ok ?? false) && context.mounted) {
      await context.read<RolesCubit>().delete(widget.role.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Danger Zone tab
// ---------------------------------------------------------------------------

class _DangerZoneTab extends StatefulWidget {
  const _DangerZoneTab({required this.state});
  final ProjectDetailLoaded state;

  @override
  State<_DangerZoneTab> createState() => _DangerZoneTabState();
}

class _DangerZoneTabState extends State<_DangerZoneTab> {
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await context.read<ProjectSettingsCubit>().deleteWithConfirmation(
      typedConfirmation: _confirmCtrl.text,
      expectedName: widget.state.project.name,
    );
    if (!context.mounted) return;
    final t = AppLocalizations.of(context);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.projectDeletedSnack)),
      );
      context.go(Routes.projects);
    } else {
      final state = context.read<ProjectSettingsCubit>().state;
      if (state is ProjectSettingsFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.projectDeleteNameMismatch)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canDelete = widget.state.has(Permission.projectDelete);
    final project = widget.state.project;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              color: Theme.of(context).colorScheme.errorContainer.withValues(
                alpha: 0.4,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.projectDeleteSectionTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(t.projectDeleteBody),
                    const SizedBox(height: 12),
                    Text(t.projectDeleteTypeName(project.name)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _confirmCtrl,
                      enabled: canDelete,
                      decoration: InputDecoration(hintText: project.name),
                    ),
                    const SizedBox(height: 12),
                    BlocBuilder<ProjectSettingsCubit, ProjectSettingsState>(
                      builder: (context, s) {
                        final busy = s is ProjectSettingsDeleting;
                        return FilledButton.tonalIcon(
                          icon: const Icon(Icons.delete_forever),
                          onPressed: !canDelete || busy
                              ? null
                              : () => _delete(context),
                          label: Text(t.actionDeleteProject),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
