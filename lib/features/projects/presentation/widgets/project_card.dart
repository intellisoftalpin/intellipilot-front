import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/widgets/project_avatar.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Height every [ProjectCard] is laid out at, so grid rows line up.
const projectCardHeight = 204.0;

/// One project on the projects screen: a band in the project's color carrying
/// its icon and the favorite star, then name, key, description, and quick
/// links. Tapping the card opens the project overview.
class ProjectCard extends StatefulWidget {
  const ProjectCard({
    required this.project,
    required this.favorite,
    required this.canFavorite,
    required this.onToggleFavorite,
    super.key,
  });

  final Project project;
  final bool favorite;

  /// False when the favorites are full and this project is not one of them.
  final bool canFavorite;
  final VoidCallback onToggleFavorite;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = AppLocalizations.of(context);
    final p = widget.project;
    final accent = projectColorOrPrimary(context, p.color);
    const band = 64.0;
    const avatar = 48.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: _hover ? 0.14 : 0.05),
            blurRadius: _hover ? 18 : 6,
            offset: Offset(0, _hover ? 8 : 2),
          ),
        ],
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _hover
                ? accent.withValues(alpha: 0.6)
                : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(Routes.projectDetailFor(p.id)),
          onHover: (h) => setState(() => _hover = h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: band,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent,
                              Color.lerp(accent, scheme.surface, 0.45)!,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.surfaceContainerLow,
                            width: 3,
                          ),
                        ),
                        child: ProjectAvatar(project: p, size: avatar),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _FavoriteStar(
                        favorite: widget.favorite,
                        enabled: widget.favorite || widget.canFavorite,
                        onPressed: widget.onToggleFavorite,
                        tooltip: widget.favorite
                            ? t.projectFavoriteRemove
                            : widget.canFavorite
                            ? t.projectFavoriteAdd
                            : t.projectFavoritesFull(maxFavoriteProjects),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IssueKeyChip(
                            text: p.issuePrefix.isEmpty
                                ? p.slug
                                : p.issuePrefix,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
                child: Row(
                  children: [
                    _VisibilityBadge(visibility: p.visibility),
                    const Spacer(),
                    _QuickLink(
                      icon: Icons.list_alt_outlined,
                      tooltip: t.railIssues,
                      onPressed: () =>
                          context.go(Routes.projectIssuesFor(p.id)),
                    ),
                    _QuickLink(
                      icon: Icons.view_kanban_outlined,
                      tooltip: t.railBoard,
                      onPressed: () => context.go(Routes.projectBoardFor(p.id)),
                    ),
                    _QuickLink(
                      icon: Icons.settings_outlined,
                      tooltip: t.railSettings,
                      onPressed: () =>
                          context.go(Routes.projectSettingsFor(p.id)),
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

/// The star toggle, drawn on a translucent disc so it reads on any band color.
class _FavoriteStar extends StatelessWidget {
  const _FavoriteStar({
    required this.favorite,
    required this.enabled,
    required this.onPressed,
    required this.tooltip,
  });

  final bool favorite;
  final bool enabled;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface.withValues(alpha: favorite ? 0.9 : 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 20,
              color: favorite
                  ? Colors.amber.shade600
                  : scheme.onSurface.withValues(alpha: enabled ? 0.8 : 0.35),
            ),
          ),
        ),
      ),
    );
  }
}

class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visibility});
  final ProjectVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = switch (visibility) {
      ProjectVisibility.private => (
        Icons.lock_outline,
        t.projectVisibilityPrivate,
      ),
      ProjectVisibility.internal => (
        Icons.groups_outlined,
        t.projectVisibilityInternal,
      ),
      ProjectVisibility.publicReadonly => (
        Icons.public,
        t.projectVisibilityPublicReadonly,
      ),
    };
    return Tooltip(
      message: label,
      child: Icon(icon, size: 16, color: scheme.onSurfaceVariant),
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 18),
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    onPressed: onPressed,
  );
}
