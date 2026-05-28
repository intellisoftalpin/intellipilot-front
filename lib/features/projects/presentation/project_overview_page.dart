import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/features/projects/presentation/widgets/permission_gate.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class ProjectOverviewPage extends StatelessWidget {
  const ProjectOverviewPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _loadProfile(),
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
        return BlocProvider<ProjectDetailCubit>(
          create: (_) => ProjectDetailCubit(
            repo: getIt<ProjectsRepository>(),
            projectId: projectId,
            currentUserId: profile.id,
          )..load(),
          child: const _ProjectOverviewView(),
        );
      },
    );
  }

  Future<UserProfile?> _loadProfile() async {
    final res = await getIt<ProfileRepository>().getProfile();
    return res.valueOrNull;
  }
}

class _ProjectOverviewView extends StatelessWidget {
  const _ProjectOverviewView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
          builder: (_, s) {
            if (s is ProjectDetailLoaded) return Text(s.project.name);
            return Text(t.projectOverviewTitle);
          },
        ),
        actions: [
          PermissionGate(
            permission: Permission.projectModify,
            child: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
              builder: (context, s) {
                if (s is! ProjectDetailLoaded) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: t.projectSettingsTitle,
                  onPressed: () => context.go(
                    Routes.projectSettingsFor(s.project.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, state) {
          if (state is ProjectDetailLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ProjectDetailFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.projectLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () =>
                        context.read<ProjectDetailCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is ProjectDetailLoaded) {
            return _Overview(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.state});
  final ProjectDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final project = state.project;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        project.slug,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(_visibilityLabel(t, project.visibility))),
              ],
            ),
            const SizedBox(height: 16),
            if (project.description.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(project.description),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              t.projectFeaturesTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _FeatureChip(label: t.projectFeatureBacklog, on: project.backlogEnabled),
                _FeatureChip(label: t.projectFeatureKanban, on: project.kanbanEnabled),
                _FeatureChip(label: t.projectFeatureEpics, on: project.epicsEnabled),
                _FeatureChip(label: t.projectFeatureWiki, on: project.wikiEnabled),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.list_alt),
                  onPressed: () =>
                      context.go(Routes.projectBacklogFor(project.id)),
                  label: Text(t.actionOpenBacklog),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.view_kanban_outlined),
                  onPressed: () =>
                      context.go(Routes.projectBoardFor(project.id)),
                  label: Text(t.actionOpenBoard),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: () =>
                      context.go(Routes.projectMilestonesFor(project.id)),
                  label: Text(t.actionOpenMilestones),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.bug_report_outlined),
                  onPressed: () =>
                      context.go(Routes.projectIssuesFor(project.id)),
                  label: Text(t.actionOpenIssues),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              t.projectPhase5Notice,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _visibilityLabel(AppLocalizations t, ProjectVisibility v) =>
      switch (v) {
        ProjectVisibility.private => t.projectVisibilityPrivate,
        ProjectVisibility.internal => t.projectVisibilityInternal,
        ProjectVisibility.publicReadonly => t.projectVisibilityPublicReadonly,
      };
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.on});
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        on ? Icons.check_circle_outline : Icons.do_not_disturb_alt,
        size: 16,
        color: on
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      label: Text(label),
    );
  }
}
