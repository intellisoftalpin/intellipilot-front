import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/empty_state.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/milestones/presentation/cubits/milestones_list_cubit.dart';
import 'package:intellipilot/features/milestones/presentation/widgets/milestone_edit_dialog.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class MilestonesListPage extends StatelessWidget {
  const MilestonesListPage({required this.projectId, super.key});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future:
          getIt<ProfileRepository>().getProfile().then((r) => r.valueOrNull),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) {
          return Scaffold(
            body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider<ProjectDetailCubit>(
              create: (_) => ProjectDetailCubit(
                repo: getIt<ProjectsRepository>(),
                projectId: projectId,
                currentUserId: profile.id,
              )..load(),
            ),
            BlocProvider<MilestonesListCubit>(
              create: (_) => MilestonesListCubit(
                repo: getIt<MilestonesRepository>(),
                projectId: projectId,
              )..load(),
            ),
          ],
          child: _ListView(projectId: projectId),
        );
      },
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: projectId,
          currentLabel: t.milestonesTitle,
        ),
      ),
      floatingActionButton: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, s) {
          if (s is! ProjectDetailLoaded ||
              !s.has(Permission.milestoneCreate)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewMilestone),
            onPressed: () async {
              final body = await showMilestoneEditDialog(context);
              if (body == null || !context.mounted) return;
              await context.read<MilestonesListCubit>().create(body);
            },
          );
        },
      ),
      body: BlocBuilder<MilestonesListCubit, MilestonesListState>(
        builder: (context, state) {
          if (state is MilestonesListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is MilestonesListFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.milestonesLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () =>
                        context.read<MilestonesListCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is! MilestonesListLoaded) return const SizedBox.shrink();
          if (state.milestones.isEmpty) {
            final detail = context.watch<ProjectDetailCubit>().state;
            final canCreate = detail is ProjectDetailLoaded &&
                detail.has(Permission.milestoneCreate);
            return EmptyState(
              icon: Icons.flag_outlined,
              title: t.milestonesTitle,
              body: t.milestonesEmpty,
              action: canCreate
                  ? FilledButton.icon(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final cubit = context.read<MilestonesListCubit>();
                        final body =
                            await showMilestoneEditDialog(context);
                        if (body == null) return;
                        await cubit.create(body);
                      },
                      label: Text(t.actionNewMilestone),
                    )
                  : null,
            );
          }
          final detail = context.watch<ProjectDetailCubit>().state;
          final canEdit =
              detail is ProjectDetailLoaded &&
                  detail.has(Permission.milestoneModify);
          final canDelete =
              detail is ProjectDetailLoaded &&
                  detail.has(Permission.milestoneDelete);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final m in state.sorted)
                    _Row(
                      milestone: m,
                      projectId: projectId,
                      canEdit: canEdit,
                      canDelete: canDelete,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.milestone,
    required this.projectId,
    required this.canEdit,
    required this.canDelete,
  });
  final Milestone milestone;
  final String projectId;
  final bool canEdit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = [
      if (milestone.startDate != null) _isoDate(milestone.startDate!),
      if (milestone.endDate != null) _isoDate(milestone.endDate!),
    ].join(' → ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          milestone.closed
              ? Icons.check_circle
              : Icons.outlined_flag,
          color: milestone.closed
              ? theme.colorScheme.outline
              : theme.colorScheme.primary,
        ),
        title: Text(milestone.name),
        subtitle: Text([
          if (dates.isNotEmpty) dates,
          if (milestone.closed)
            t.milestoneStatusClosed
          else
            t.milestoneStatusOpen,
        ].join(' · ')),
        onTap: () =>
            context.go(Routes.milestoneDetailFor(projectId, milestone.id)),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final body = await showMilestoneEditDialog(
                    context,
                    existing: milestone,
                  );
                  if (body == null || !context.mounted) return;
                  await context.read<MilestonesListCubit>().update(
                    milestone.id,
                    UpdateMilestoneRequest(
                      name: body.name,
                      startDate: body.startDate,
                      endDate: body.endDate,
                    ),
                  );
                },
              ),
            if (canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(t.milestoneDeleteTitle),
                      content: Text(
                        t.milestoneDeleteConfirm(milestone.name),
                      ),
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
                    await context.read<MilestonesListCubit>().delete(
                      milestone.id,
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';
