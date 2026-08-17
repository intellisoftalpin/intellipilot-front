import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/datetime/relative_time.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/doc_path.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';
import 'package:intellipilot/features/docs/presentation/cubits/doc_view_cubit.dart';
import 'package:intellipilot/features/docs/presentation/widgets/doc_image.dart';
import 'package:intellipilot/features/docs/presentation/widgets/doc_tree_panel.dart';
import 'package:intellipilot/features/docs/presentation/widgets/web_source_view.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Below this width the contents panel moves into an end drawer rather than
/// squeezing the document into an unreadable column.
const _panelBreakpoint = 1000.0;
const _panelWidth = 280.0;

/// Reader and editor for one external documentation source.
class DocsPage extends StatelessWidget {
  const DocsPage({
    required this.projectId,
    required this.sourceId,
    this.path,
    super.key,
  });

  final String projectId;
  final String sourceId;

  /// Jail-relative document to open. Null opens the source's homepage.
  final String? path;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DocViewCubit>(
      // Keyed on the source so switching sources in the rail rebuilds the
      // cubit rather than showing the previous source's tree.
      key: ValueKey(sourceId),
      create: (_) {
        final c = DocViewCubit(
          repo: getIt<DocsRepository>(),
          projectId: projectId,
          sourceId: sourceId,
        );
        unawaited(c.load(path: path));
        return c;
      },
      child: _DocsView(
        projectId: projectId,
        sourceId: sourceId,
        requestedPath: path,
      ),
    );
  }
}

class _DocsView extends StatefulWidget {
  const _DocsView({
    required this.projectId,
    required this.sourceId,
    required this.requestedPath,
  });

  final String projectId;
  final String sourceId;
  final String? requestedPath;

  @override
  State<_DocsView> createState() => _DocsViewState();
}

class _DocsViewState extends State<_DocsView> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _anchors = MarkdownAnchorController();
  List<MarkdownHeading> _headings = const [];

  @override
  void didUpdateWidget(_DocsView old) {
    super.didUpdateWidget(old);
    // A URL change (deep link, browser back) reopens the named document.
    final wanted = widget.requestedPath;
    if (wanted != null && wanted != old.requestedPath) {
      unawaited(context.read<DocViewCubit>().open(wanted));
    }
  }

  /// Keep the address bar in step so a document can be linked to and the
  /// browser's back button behaves.
  void _syncUrl(String? path) {
    final target = Routes.docSourceFor(
      widget.projectId,
      widget.sourceId,
      path: path,
    );
    if (GoRouterState.of(context).uri.toString() != target) {
      context.go(target);
    }
  }

  void _openDoc(String path) {
    unawaited(context.read<DocViewCubit>().open(path));
    _syncUrl(path);
  }

  /// Follow a link found inside a document.
  ///
  /// Anything that resolves inside the shared folder opens in place. Anything
  /// above it is sent to the git host: that content is deliberately not served
  /// here, and silently doing nothing would look like a broken link.
  void _followLink(DocViewLoaded state, String href) {
    final target = resolveDocLink(
      from: state.content?.path ?? '',
      href: href,
      webUrl: state.source.webUrl,
      // Only reachable for a git source, which always has a branch.
      branch: state.source.branch ?? '',
      docPath: state.source.docPath,
    );
    switch (target) {
      case DocInternalLink(:final path):
        _openDoc(path);
      case DocAnchorLink():
        // Handled inside the renderer, which owns the heading keys.
        break;
      case DocExternalLink(:final url, :final escapedJail):
        if (escapedJail) _notifyEscape();
        openExternalUrl(url);
      case DocDeadLink():
        _notifyEscape();
    }
  }

  void _notifyEscape() {
    final t = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t.docsLinkOutside)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocConsumer<DocViewCubit, DocViewState>(
      listenWhen: (a, b) => b is DocViewLoaded,
      listener: (context, state) {
        if (state is DocViewLoaded && !state.editing) {
          _syncUrl(state.content?.path);
        }
      },
      builder: (context, state) {
        if (state is DocViewLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is DocViewFailed) {
          return Scaffold(
            appBar: AppBar(title: Text(t.docsTitle)),
            body: _ErrorView(
              error: state.error,
              onRetry: () => unawaited(context.read<DocViewCubit>().load()),
            ),
          );
        }
        if (state is! DocViewLoaded) return const SizedBox.shrink();

        // A web link has no tree, no headings and nothing to edit — it is one
        // framed page with a way out to the real tab.
        if (state.source.kind.isWeb) {
          return Scaffold(
            appBar: _webAppBar(context, state.source, t),
            body: WebSourceView(source: state.source),
          );
        }

        final wide = MediaQuery.sizeOf(context).width >= _panelBreakpoint;
        final panel = DocTreePanel(
          tree: state.tree,
          currentPath: state.content?.path,
          headings: _headings,
          onOpen: _openDoc,
          onHeadingTap: (h) => _anchors.scrollTo(h.anchor),
        );

        return Scaffold(
          key: _scaffoldKey,
          appBar: _appBar(context, state, wide, t),
          endDrawer: wide ? null : Drawer(child: SafeArea(child: panel)),
          body: Column(
            children: [
              if (state.error != null)
                _Banner(error: state.error!, detail: state.errorDetail),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _body(context, state, t)),
                    if (wide) SizedBox(width: _panelWidth, child: panel),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// App bar for a web link: just the breadcrumb. The way out to a real tab
  /// lives above the frame itself, where it is impossible to miss.
  PreferredSizeWidget _webAppBar(
    BuildContext context,
    DocSource source,
    AppLocalizations t,
  ) => AppBar(
    title: ProjectSectionBreadcrumb(
      projectId: widget.projectId,
      currentLabel: t.wikiTitle,
      sectionRoute: Routes.projectWikiFor(widget.projectId),
      extraCrumbs: [Crumb(label: source.name)],
    ),
  );

  PreferredSizeWidget _appBar(
    BuildContext context,
    DocViewLoaded state,
    bool wide,
    AppLocalizations t,
  ) {
    final source = state.source;
    final crumbs = <Crumb>[Crumb(label: source.name)];
    final path = state.content?.path;
    if (path != null) {
      for (final segment in path.split('/')) {
        crumbs.add(Crumb(label: segment));
      }
    }
    return AppBar(
      title: ProjectSectionBreadcrumb(
        projectId: widget.projectId,
        currentLabel: t.wikiTitle,
        sectionRoute: Routes.projectWikiFor(widget.projectId),
        extraCrumbs: crumbs,
      ),
      actions: [
        _SyncStatus(
          source: source,
          busy: state.busy,
          onSync: () => unawaited(context.read<DocViewCubit>().sync()),
        ),
        if (source.webUrl.isNotEmpty)
          IconButton(
            tooltip: t.docsOpenOnSource,
            icon: const Icon(Icons.open_in_new),
            onPressed: () => openExternalUrl(_sourceUrl(source, path)),
          ),
        if (state.content != null && !state.editing)
          if (state.content!.canEdit)
            IconButton(
              tooltip: t.actionEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: context.read<DocViewCubit>().startEditing,
            )
          else
            IconButton(
              tooltip: source.readOnly
                  ? t.docsSourceIsReadOnly
                  : t.docsWriteKeyMissing,
              icon: const Icon(Icons.lock_outline),
              onPressed: () => _explainReadOnly(context, source, t),
            ),
        if (!wide)
          IconButton(
            tooltip: t.docsContents,
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
      ],
    );
  }

  void _explainReadOnly(
    BuildContext context,
    DocSource source,
    AppLocalizations t,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            source.readOnly ? t.docsSourceIsReadOnly : t.docsWriteKeyMissing,
          ),
          action: source.readOnly
              ? null
              : SnackBarAction(
                  label: t.docsConfigureKey,
                  onPressed: () =>
                      context.go(Routes.projectSettingsFor(widget.projectId)),
                ),
        ),
      );
  }

  static String _sourceUrl(DocSource source, String? path) {
    final base = source.webUrl.replaceAll(RegExp(r'/+$'), '');
    if (path == null) return base;
    final inRepo = source.docPath.isEmpty ? path : '${source.docPath}/$path';
    // Only called from the git viewer, where a branch is always present.
    return '$base/blob/${source.branch ?? ''}/$inRepo';
  }

  Widget _body(BuildContext context, DocViewLoaded state, AppLocalizations t) {
    if (state.editing) return _Editor(state: state);
    final content = state.content;
    if (content == null) {
      return _TreeLanding(tree: state.tree, onOpen: _openDoc);
    }
    return _Reader(
      state: state,
      projectId: widget.projectId,
      onLink: (href) => _followLink(state, href),
      onHeadings: (h) {
        if (!mounted) return;
        setState(() => _headings = h);
      },
      anchors: _anchors,
    );
  }
}

/// The rendered document, plus its git provenance.
class _Reader extends StatelessWidget {
  const _Reader({
    required this.state,
    required this.projectId,
    required this.onLink,
    required this.onHeadings,
    required this.anchors,
  });

  final DocViewLoaded state;
  final String projectId;
  final void Function(String href) onLink;
  final void Function(List<MarkdownHeading> headings) onHeadings;
  final MarkdownAnchorController anchors;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final content = state.content!;
    final repo = getIt<DocsRepository>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MarkdownText(
                content.body,
                onLinkTap: onLink,
                onHeadings: onHeadings,
                anchorController: anchors,
                imageBuilder: (src, alt) => DocImage(
                  repo: repo,
                  projectId: projectId,
                  sourceId: state.source.id,
                  docPath: content.path,
                  src: src,
                  alt: alt,
                ),
              ),
              if (content.lastCommit != null) ...[
                const SizedBox(height: 32),
                _CommitFooter(commit: content.lastCommit!, t: t),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitFooter extends StatelessWidget {
  const _CommitFooter({required this.commit, required this.t});
  final DocCommitInfo commit;
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Tooltip(
        message: '${commit.shortSha} · ${absoluteTime(commit.committedAt)}',
        child: Row(
          children: [
            Icon(
              Icons.history,
              size: 14,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                t.docsLastChangedBy(
                  commit.authorName,
                  relativeTime(t, commit.committedAt),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            if (commit.message.isNotEmpty)
              Flexible(
                child: Text(
                  commit.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Landing page for a source with no obvious homepage: the folder listing.
class _TreeLanding extends StatelessWidget {
  const _TreeLanding({required this.tree, required this.onOpen});
  final DocTree tree;
  final void Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final docs = tree.documents;
    if (docs.isEmpty) {
      return Center(
        child: Text(
          t.docsEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(t.docsBrowseAll, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final d in docs)
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(d.name),
            subtitle: d.path == d.name ? null : Text(d.path),
            onTap: () => onOpen(d.path),
          ),
      ],
    );
  }
}

/// The markdown editor, with a commit message and a live-ish save bar.
class _Editor extends StatefulWidget {
  const _Editor({required this.state});
  final DocViewLoaded state;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _body = TextEditingController(
    text: widget.state.draft,
  );
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _body.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cubit = context.read<DocViewCubit>();
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: TextField(
              controller: _body,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: cubit.updateDraft,
            ),
          ),
        ),
        Material(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _message,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: t.docsCommitMessage,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: widget.state.busy ? null : cubit.cancelEditing,
                  child: Text(t.actionCancel),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: widget.state.busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  onPressed: widget.state.busy
                      ? null
                      : () => unawaited(
                          cubit.save(
                            message: _message.text.trim().isEmpty
                                ? null
                                : _message.text.trim(),
                          ),
                        ),
                  label: Text(t.docsSaveDoc),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The "synced 3 minutes ago" label plus its refresh button.
class _SyncStatus extends StatelessWidget {
  const _SyncStatus({
    required this.source,
    required this.busy,
    required this.onSync,
  });

  final DocSource source;
  final bool busy;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final failed = source.cacheStatus == DocCacheStatus.error;
    final label = source.lastSyncedAt == null
        ? t.docsNeverSynced
        : t.docsSyncedAgo(relativeTime(t, source.lastSyncedAt));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: failed
              ? (source.cacheError ?? t.docsSyncFailed)
              : absoluteTime(source.lastSyncedAt),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failed) ...[
                Icon(
                  Icons.cloud_off_outlined,
                  size: 15,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: t.docsSyncNow,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          onPressed: busy ? null : onSync,
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.error, this.detail});
  final DocViewError error;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final message = switch (error) {
      DocViewError.notReady => t.docsNotReadyHint,
      DocViewError.pathMissing => t.docsPathMissing,
      DocViewError.conflict => t.docsConflict,
      DocViewError.rejected => detail ?? t.docsPushRejected,
      DocViewError.notFound => t.docsDocNotFound,
      DocViewError.generic => detail ?? t.errUnknown,
    };
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.warning_amber),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final DocViewError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (icon, title, body) = switch (error) {
      DocViewError.notReady => (
        Icons.cloud_download_outlined,
        t.docsNotReady,
        t.docsNotReadyHint,
      ),
      DocViewError.pathMissing => (
        Icons.folder_off_outlined,
        t.docsPathMissing,
        t.docsPathMissingHint,
      ),
      _ => (Icons.error_outline, t.errUnknown, ''),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.refresh),
              onPressed: onRetry,
              label: Text(t.actionRetry),
            ),
          ],
        ),
      ),
    );
  }
}
