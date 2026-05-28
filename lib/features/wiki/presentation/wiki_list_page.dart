import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';
import 'package:intellipilot/features/wiki/presentation/cubits/wiki_list_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class WikiListPage extends StatelessWidget {
  const WikiListPage({required this.projectId, super.key});
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
            BlocProvider<WikiListCubit>(
              create: (_) => WikiListCubit(
                repo: getIt<WikiRepository>(),
                projectId: projectId,
              )..load(),
            ),
          ],
          child: _View(projectId: projectId),
        );
      },
    );
  }
}

class _View extends StatelessWidget {
  const _View({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.wikiTitle)),
      floatingActionButton:
          BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, s) {
          if (s is! ProjectDetailLoaded || !s.has(Permission.wikiCreate)) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(t.actionNewWikiPage),
            onPressed: () => _newPage(context),
          );
        },
      ),
      body: BlocBuilder<WikiListCubit, WikiListState>(
        builder: (context, state) {
          if (state is WikiListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is WikiListFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.wikiLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<WikiListCubit>().load(),
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is! WikiListLoaded) return const SizedBox.shrink();
          if (state.pages.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t.wikiEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: t.wikiSearchHint,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: context.read<WikiListCubit>().setSearch,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final p in state.visible)
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.article_outlined),
                              title: Text(p.title),
                              subtitle: Text('/${p.slug}'),
                              onTap: () => context.go(
                                Routes.wikiPageFor(projectId, p.id),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _newPage(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final titleCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.wikiCreateTitle),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: t.wikiFieldTitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionCreate),
          ),
        ],
      ),
    );
    if (!(ok ?? false) || !context.mounted) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    final cubit = context.read<WikiListCubit>();
    final created = await cubit.create(CreateWikiPageRequest(title: title));
    if (created != null && context.mounted) {
      context.go(Routes.wikiPageFor(projectId, created.id));
    }
  }
}
