import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/datetime/relative_time.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';
import 'package:intellipilot/features/docs/presentation/cubits/doc_sources_cubit.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The landing page for a project's Wiki section: one large tile per place
/// documentation lives, starting with the internal wiki when it is enabled.
///
/// This is what "Wiki" in the navigation rail opens. Individual sources have
/// their own rows underneath it in the rail, so the overview exists for
/// discovery rather than as the only way in.
class WikiOverviewPage extends StatelessWidget {
  const WikiOverviewPage({required this.projectId, super.key});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<DocSourcesCubit>(
          create: (_) {
            final c = DocSourcesCubit(
              repo: getIt<DocsRepository>(),
              projectId: projectId,
            );
            unawaited(c.load());
            return c;
          },
        ),
        BlocProvider<ProjectDetailCubit>(
          create: (_) {
            final c = ProjectDetailCubit(
              repo: getIt<ProjectsRepository>(),
              projectId: projectId,
              currentUserId: '',
            );
            unawaited(c.load());
            return c;
          },
        ),
      ],
      child: _OverviewView(projectId: projectId),
    );
  }
}

class _OverviewView extends StatelessWidget {
  const _OverviewView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ProjectSectionBreadcrumb(
          projectId: projectId,
          currentLabel: t.railWiki,
          sectionRoute: Routes.projectWikiFor(projectId),
        ),
      ),
      body: BlocBuilder<ProjectDetailCubit, ProjectDetailState>(
        builder: (context, projectState) {
          final project = projectState is ProjectDetailLoaded
              ? projectState.project
              : null;
          return BlocBuilder<DocSourcesCubit, DocSourcesState>(
            builder: (context, state) {
              if (state is DocSourcesLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              // Hidden sources are withdrawn from navigation for everyone,
              // managers included; they remain manageable in settings.
              final sources = state is DocSourcesLoaded
                  ? state.sources.where((s) => !s.hidden).toList()
                  : const <DocSource>[];
              final wikiEnabled = project?.wikiEnabled ?? true;
              if (!wikiEnabled && sources.isEmpty) {
                return _EmptyState(projectId: projectId);
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        if (wikiEnabled)
                          _Tile(
                            icon: Icons.menu_book_outlined,
                            title: t.docsInternalWiki,
                            subtitle: t.docsInternalWikiHint,
                            color: Theme.of(context).colorScheme.primary,
                            onTap: () =>
                                context.go(Routes.wikiPagesFor(projectId)),
                          ),
                        for (final s in sources)
                          _SourceTile(source: s, projectId: projectId),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A tile for one external source, showing how fresh its content is.
class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.projectId});
  final DocSource source;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parsed = _parseColor(source.color);
    // A web link has no cache, so freshness is not a thing to report — the
    // address is the useful subtitle instead.
    if (source.kind.isWeb) {
      return _Tile(
        icon: Icons.language,
        emoji: source.emoji,
        title: source.name,
        subtitle: source.webUrl,
        color: parsed ?? theme.colorScheme.secondary,
        onTap: () => context.go(Routes.docSourceFor(projectId, source.id)),
      );
    }
    final subtitle = switch (source.cacheStatus) {
      DocCacheStatus.error when !source.hasContent =>
        source.cacheError ?? t.docsSyncFailed,
      DocCacheStatus.pending || DocCacheStatus.syncing => t.docsNotReady,
      _ when source.lastSyncedAt != null => t.docsSyncedAgo(
        relativeTime(t, source.lastSyncedAt),
      ),
      _ => t.docsNeverSynced,
    };
    return _Tile(
      icon: Icons.folder_shared_outlined,
      emoji: source.emoji,
      title: source.name,
      subtitle: subtitle,
      color: parsed ?? theme.colorScheme.tertiary,
      badge: source.readOnly ? t.docsReadOnly : null,
      onTap: () => context.go(Routes.docSourceFor(projectId, source.id)),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.emoji = '',
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final String emoji;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 320,
      height: 150,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // A colour spine, so tiles stay distinguishable at a glance.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 6, color: color),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (emoji.isNotEmpty)
                          Text(emoji, style: const TextStyle(fontSize: 22))
                        else
                          Icon(icon, color: color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Chip(
                          label: Text(badge!),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the internal wiki is off and no sources are registered — the
/// same condition that hides the section from the navigation rail, so this is
/// only reachable by a stale link or bookmark.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(t.docsNoDocumentation, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              t.docsNoDocumentationHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go(Routes.projectSettingsFor(projectId)),
              label: Text(t.railSettings),
            ),
          ],
        ),
      ),
    );
  }
}

/// Parse a `#rrggbb` swatch from the shared palette. Returns null for an
/// unset or malformed value so the caller can fall back to a theme colour.
Color? _parseColor(String hex) {
  final raw = hex.replaceFirst('#', '').trim();
  if (raw.length != 6) return null;
  final value = int.tryParse(raw, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
