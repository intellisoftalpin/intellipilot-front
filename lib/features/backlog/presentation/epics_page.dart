import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/core/widgets/members_scope.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_sheet.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/epics_cubit.dart';
import 'package:intellipilot/features/backlog/presentation/widgets/epic_edit_dialog.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Project Epics: a flat list with full CRUD. Epics are a separate entity
/// from issues; this page is the dedicated place to create, edit and delete
/// them (the backlog now only filters by epic).
class EpicsPage extends StatelessWidget {
  const EpicsPage({required this.projectId, super.key});
  final String projectId;

  Future<(UserProfile?, Map<String, UserRef>)> _loadContext() async {
    final p = await getIt<ProfileRepository>().getProfile();
    final m = await getIt<ProjectsRepository>().listMembers(projectId);
    final map = {
      for (final mem in (m.valueOrNull ?? const <Membership>[]))
        mem.userId: mem.toRef(),
    };
    return (p.valueOrNull, map);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(UserProfile?, Map<String, UserRef>)>(
      future: _loadContext(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final (profile, members) =
            snap.data ?? (null, const <String, UserRef>{});
        if (profile == null) {
          return Scaffold(
            body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
          );
        }
        return MembersScope(
          membersById: members,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ProjectDetailCubit>(
                create: (_) {
                  final c = ProjectDetailCubit(
                    repo: getIt<ProjectsRepository>(),
                    projectId: projectId,
                    currentUserId: profile.id,
                  );
                  unawaited(c.load());
                  return c;
                },
              ),
              BlocProvider<EpicsCubit>(
                create: (_) {
                  final c = EpicsCubit(
                    repo: getIt<BacklogRepository>(),
                    catalog: getIt<CatalogRepository>(),
                    projectId: projectId,
                  );
                  unawaited(c.load());
                  return c;
                },
              ),
            ],
            child: _EpicsView(projectId: projectId),
          ),
        );
      },
    );
  }
}

class _EpicsView extends StatelessWidget {
  const _EpicsView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: projectId,
          currentLabel: t.railEpics,
        ),
      ),
      floatingActionButton: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, detail) {
          if (detail is! ProjectDetailLoaded ||
              !detail.has(Permission.epicCreate)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewEpic),
            onPressed: () => _create(context),
          );
        },
      ),
      body: BlocBuilder<EpicsCubit, EpicsState>(
        builder: (context, state) {
          if (state is EpicsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is EpicsFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.epicsLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<EpicsCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is! EpicsLoaded) return const SizedBox.shrink();
          return _Loaded(state: state);
        },
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<EpicsCubit>();
    final result = await showEpicEditDialog(context);
    if (result == null) return;
    await cubit.createEpic(result);
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state});
  final EpicsLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit =
        detail is ProjectDetailLoaded && detail.has(Permission.epicModify);
    final canDelete =
        detail is ProjectDetailLoaded && detail.has(Permission.epicDelete);
    if (state.epics.isEmpty) {
      return EmptyState(
        icon: Icons.bookmarks_outlined,
        title: t.railEpics,
        body: t.epicsEmpty,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: state.epics.length,
          itemBuilder: (context, i) => _EpicRow(
            epic: state.epics[i],
            statuses: state.statuses,
            canEdit: canEdit,
            canDelete: canDelete,
          ),
        ),
      ),
    );
  }
}

class _EpicRow extends StatelessWidget {
  const _EpicRow({
    required this.epic,
    required this.statuses,
    required this.canEdit,
    required this.canDelete,
  });
  final Epic epic;
  final List<TaxonomyItem> statuses;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final status = statuses
        .where((s) => s.id == epic.statusId)
        .cast<TaxonomyItem?>()
        .firstOrNull;
    final assignee = MembersScope.user(context, epic.assignedTo);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: HexColorDot(hex: epic.color, size: 16),
        title: Row(
          children: [
            IssueKeyChip(text: 'EPIC-${epic.reference}'),
            const SizedBox(width: 8),
            Expanded(child: Text(epic.subject)),
            if (assignee != null) ...[
              const SizedBox(width: 8),
              UserAvatar(user: assignee, size: 26),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (status != null)
                StatusPill(
                  label: status.name,
                  colorHex: status.color,
                  dense: true,
                ),
              if (epic.description.trim().isNotEmpty)
                Text(
                  epic.description.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        onTap: () => _openDetail(context),
        trailing: (canEdit || canDelete)
            ? PopupMenuButton<String>(
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'open', child: Text(t.actionOpenDetail)),
                  if (canEdit)
                    PopupMenuItem(value: 'edit', child: Text(t.actionEdit)),
                  if (canDelete)
                    PopupMenuItem(value: 'delete', child: Text(t.actionDelete)),
                ],
                onSelected: (v) => _onMenu(context, v),
              )
            : null,
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    final cubit = context.read<EpicsCubit>();
    await showEntityDetailSheet(
      context,
      projectId: epic.projectId,
      kind: EntityKind.epic,
      entityId: epic.id,
    );
    await cubit.load();
  }

  Future<void> _onMenu(BuildContext context, String v) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<EpicsCubit>();
    if (v == 'open') {
      await _openDetail(context);
    } else if (v == 'edit') {
      final updated = await showEpicEditDialog(context, existing: epic);
      if (updated == null) return;
      await cubit.updateEpic(
        epic.id,
        UpdateEpicRequest(
          subject: updated.subject,
          description: updated.description,
          color: updated.color,
        ),
      );
    } else if (v == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.backlogDeleteEpicTitle),
          content: Text(t.backlogDeleteEpicConfirm(epic.subject)),
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
        await cubit.deleteEpic(epic.id);
      }
    }
  }
}
