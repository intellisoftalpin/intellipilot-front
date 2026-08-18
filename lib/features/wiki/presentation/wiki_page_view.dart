import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/markdown_editor.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';
import 'package:intellipilot/features/wiki/presentation/cubits/wiki_page_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class WikiPageView extends StatelessWidget {
  const WikiPageView({
    required this.projectId,
    required this.pageId,
    super.key,
  });
  final String projectId;
  final String pageId;

  @override
  Widget build(BuildContext context) {
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
            body: Center(child: Text(AppLocalizations.of(context).errUnknown)),
          );
        }
        return MultiBlocProvider(
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
            BlocProvider<WikiPageCubit>(
              create: (_) {
                final c = WikiPageCubit(
                  repo: getIt<WikiRepository>(),
                  projectId: projectId,
                  pageId: pageId,
                );
                unawaited(c.load());
                return c;
              },
            ),
          ],
          child: _PageView(projectId: projectId, pageId: pageId),
        );
      },
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.projectId, required this.pageId});
  final String projectId;
  final String pageId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<WikiPageCubit, WikiPageState>(
      builder: (context, state) {
        if (state is WikiPageLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is WikiPageFailed) {
          return Scaffold(
            appBar: AppBar(
              title: ProjectSectionBreadcrumb(
                projectId: projectId,
                currentLabel: t.railWiki,
                sectionRoute: Routes.projectWikiFor(projectId),
                extraCrumbs: [Crumb(label: t.wikiPageTitle)],
              ),
            ),
            body: Center(child: Text(t.wikiPageLoadFailed)),
          );
        }
        if (state is! WikiPageLoaded) return const SizedBox.shrink();
        return Scaffold(
          appBar: AppBar(
            title: ProjectSectionBreadcrumb(
              projectId: projectId,
              currentLabel: t.railWiki,
              sectionRoute: Routes.projectWikiFor(projectId),
              extraCrumbs: [Crumb(label: state.page.title)],
            ),
            actions: [
              IconButton(
                tooltip: t.wikiRevisionsTooltip,
                icon: const Icon(Icons.history),
                onPressed: () => context.go(
                  Routes.wikiRevisionsFor(projectId, state.page.id),
                ),
              ),
              _EditOrSaveActions(state: state),
              _DeleteAction(state: state),
            ],
          ),
          body: Column(
            children: [
              if (state.conflict)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t.wikiConflictNotice)),
                        TextButton(
                          onPressed: () =>
                              context.read<WikiPageCubit>().overwrite(),
                          child: Text(t.wikiConflictOverwrite),
                        ),
                        TextButton(
                          onPressed: () =>
                              context.read<WikiPageCubit>().cancelEditing(),
                          child: Text(t.wikiConflictDiscard),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: state.editing
                    ? _Editor(state: state)
                    : _Reader(state: state),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Reader extends StatelessWidget {
  const _Reader({required this.state});
  final WikiPageLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: state.page.body.isEmpty
              ? Text(
                  '— ${t.wikiEmptyBody} —',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                )
              : MarkdownText(state.page.body),
        ),
      ),
    );
  }
}

/// The wiki page editor: title, then a split markdown editor.
///
/// Stateful because it **owns** its text controllers. They used to be built
/// inline in `build`, so every keystroke emitted new cubit state, rebuilt the
/// widget, constructed a fresh controller and dropped the caret back to
/// offset zero — the field was effectively unusable.
class _Editor extends StatefulWidget {
  const _Editor({required this.state});
  final WikiPageLoaded state;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _title;
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _title = TextEditingController(text: s.draftTitle ?? s.page.title)
      ..addListener(_pushTitle);
    _body = TextEditingController(text: s.draftBody ?? s.page.body)
      ..addListener(_pushBody);
  }

  @override
  void dispose() {
    _title
      ..removeListener(_pushTitle)
      ..dispose();
    _body
      ..removeListener(_pushBody)
      ..dispose();
    super.dispose();
  }

  /// The cubit holds the draft that gets saved; the controllers hold what the
  /// user is typing. Pushing one way only — the controllers are never written
  /// back from state — is what keeps the caret still.
  void _pushTitle() => context.read<WikiPageCubit>().setDraftTitle(_title.text);
  void _pushBody() => context.read<WikiPageCubit>().setDraftBody(_body.text);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: t.wikiFieldTitle),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: MarkdownEditor(
              controller: _body,
              layout: MarkdownEditorLayout.split,
              expand: true,
              onSubmitShortcut: () =>
                  unawaited(context.read<WikiPageCubit>().save()),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditOrSaveActions extends StatelessWidget {
  const _EditOrSaveActions({required this.state});
  final WikiPageLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canEdit = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(Permission.wikiModify);
    });
    if (!canEdit) return const SizedBox.shrink();
    if (!state.editing) {
      return IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: t.actionEdit,
        onPressed: () => context.read<WikiPageCubit>().startEditing(),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: state.busy
              ? null
              : () => context.read<WikiPageCubit>().cancelEditing(),
          child: Text(t.actionCancel),
        ),
        FilledButton.icon(
          icon: state.busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          onPressed: state.busy
              ? null
              : () => context.read<WikiPageCubit>().save(),
          label: Text(t.actionSave),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _DeleteAction extends StatelessWidget {
  const _DeleteAction({required this.state});
  final WikiPageLoaded state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canDelete = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(Permission.wikiDelete);
    });
    if (!canDelete || state.editing) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: t.actionDelete,
      onPressed: () async {
        final cubit = context.read<WikiPageCubit>();
        final page = state.page;
        if (page.etag == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.wikiDeleteTitle),
            content: Text(t.wikiDeleteConfirm(page.title)),
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
        if (!(ok ?? false) || !context.mounted) return;
        final repo = getIt<WikiRepository>();
        final res = await repo.delete(
          page.projectId,
          page.id,
          etag: page.etag!,
        );
        if (res.valueOrNull != null && context.mounted) {
          context.go(Routes.projectWikiFor(page.projectId));
        } else {
          // Surface failure to cubit listeners via a load() refresh so the
          // user can retry.
          await cubit.load();
        }
      },
    );
  }
}
