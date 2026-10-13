import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/meetings/domain/project_access_cache.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/members_cubit.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

// A platform superadmin reads every project but changes one only as a member.
// These widgets let him become one: a card on Settings › Members and a
// read-only banner over every project page, both opening the same role picker.

/// Ask which role to join with; the admin role is preselected. Returns the
/// chosen role slug, or null when cancelled.
Future<String?> showJoinProjectDialog(
  BuildContext context,
  List<Role> roles,
) {
  final t = AppLocalizations.of(context);
  final sorted = [...roles]..sort((a, b) => a.order.compareTo(b.order));
  var slug = (sorted.where((r) => r.isAdmin).firstOrNull ?? sorted.first).slug;
  return showDialog<String?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(t.actionJoinProject),
        content: SizedBox(
          width: 360,
          child: DropdownButtonFormField<String>(
            initialValue: slug,
            decoration: InputDecoration(labelText: t.memberRoleLabel),
            items: [
              for (final r in sorted)
                DropdownMenuItem(value: r.slug, child: Text(r.name)),
            ],
            onChanged: (v) => setState(() => slug = v ?? slug),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(slug),
            child: Text(t.actionJoinProject),
          ),
        ],
      ),
    ),
  );
}

void _announceJoined(String projectId) {
  if (getIt.isRegistered<ProjectAccessCache>()) {
    getIt<ProjectAccessCache>().invalidate(projectId);
  }
}

void _showJoinFailed(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(AppLocalizations.of(context).joinProjectFailed)),
  );
}

/// Settings › Members: offered to a superadmin who is not a member.
class JoinProjectCard extends StatelessWidget {
  const JoinProjectCard({required this.roles, super.key});
  final List<Role> roles;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
      builder: (context, state) {
        if (state is! ProjectDetailLoaded || !state.canJoin) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.login,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t.joinProjectBody)),
                FilledButton.icon(
                  icon: const Icon(Icons.person_add_alt_1),
                  onPressed: roles.isEmpty
                      ? null
                      : () => _join(context, state.project.id),
                  label: Text(t.actionJoinProject),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _join(BuildContext context, String projectId) async {
    final members = context.read<MembersCubit>();
    final slug = await showJoinProjectDialog(context, roles);
    if (slug == null) return;
    final failure = await members.join(slug);
    if (!context.mounted) return;
    if (failure != null) {
      _showJoinFailed(context);
      return;
    }
    _announceJoined(projectId);
  }
}

/// Wraps a project page: above it, a superadmin who is not a member sees that
/// the project is read-only for him, with a button to join.
class ReadOnlyProjectBanner extends StatefulWidget {
  const ReadOnlyProjectBanner({
    required this.projectId,
    required this.child,
    super.key,
  });

  /// Null until the shell has resolved the project ref.
  final String? projectId;
  final Widget child;

  @override
  State<ReadOnlyProjectBanner> createState() => _ReadOnlyProjectBannerState();
}

class _ReadOnlyProjectBannerState extends State<ReadOnlyProjectBanner> {
  ProjectAccessCache? _cache;
  bool _show = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<ProjectAccessCache>()) {
      _cache = getIt<ProjectAccessCache>()..addListener(_onChanged);
    }
    unawaited(_check());
  }

  @override
  void didUpdateWidget(covariant ReadOnlyProjectBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _show = false;
      unawaited(_check());
    }
  }

  @override
  void dispose() {
    _cache?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => unawaited(_check());

  Future<void> _check() async {
    final projectId = widget.projectId;
    final cache = _cache;
    if (projectId == null || cache == null) return;
    final access = await cache.access(projectId);
    if (!mounted || widget.projectId != projectId) return;
    final show = access.readAll && !access.isMember;
    if (show != _show) setState(() => _show = show);
  }

  Future<void> _join() async {
    final projectId = widget.projectId;
    if (projectId == null) return;
    setState(() => _busy = true);
    final repo = getIt<ProjectsRepository>();
    final roles = (await repo.listRoles(projectId)).valueOrNull;
    if (!mounted) return;
    if (roles == null || roles.isEmpty) {
      setState(() => _busy = false);
      _showJoinFailed(context);
      return;
    }
    final slug = await showJoinProjectDialog(context, roles);
    if (slug == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final res = await repo.joinProject(projectId, roleSlug: slug);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.isErr) {
      _showJoinFailed(context);
      return;
    }
    _announceJoined(projectId);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // One shape whether or not the banner shows, so the page below keeps its
    // state when it appears or goes.
    return Column(
      children: [
        if (_show)
          Material(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.joinProjectBanner,
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _join,
                    child: Text(t.actionJoinProject),
                  ),
                ],
              ),
            ),
          ),
        Expanded(key: const ValueKey('page'), child: widget.child),
      ],
    );
  }
}
