import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/issue_chips.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/links/data/dtos/link_dtos.dart';
import 'package:intellipilot/features/links/presentation/cubits/links_cubit.dart';
import 'package:intellipilot/features/links/presentation/widgets/add_link_dialog.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Compact registry of every entity in the project — used to resolve a
/// link's far side to a key (`US-12`) + subject for rendering. Caller
/// passes the same maps the entity detail page already builds for its
/// _DetailsTable.
class LinksLookup {
  const LinksLookup({
    required this.epics,
    required this.issues,
    this.prefix = '',
  });

  final Map<String, Epic> epics;
  final Map<String, Issue> issues;

  /// Project issue-key prefix used to format resolved keys.
  final String prefix;

  ({String key, String subject})? resolve(EntityKind kind, String id) {
    switch (kind) {
      case EntityKind.epic:
        final e = epics[id];
        return e == null
            ? null
            : (key: epicKeyLabel(prefix, e.reference), subject: e.subject);
      case EntityKind.issue:
        final i = issues[id];
        return i == null
            ? null
            : (key: issueKeyLabel(prefix, i.reference), subject: i.subject);
    }
  }
}

/// Links list rendered inside the entity detail page's left column.
/// Reads the [LinksCubit] for state and the [ProjectDetailCubit] for the
/// edit-permission gate. Embeds the Add button + per-row delete.
class LinksPanelContent extends StatelessWidget {
  const LinksPanelContent({
    required this.projectId,
    required this.sourceKind,
    required this.sourceId,
    required this.lookup,
    required this.modifyPermission,
    super.key,
  });

  final String projectId;
  final EntityKind sourceKind;
  final String sourceId;
  final LinksLookup lookup;
  final Permission modifyPermission;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<LinksCubit, LinksState>(
      builder: (context, state) {
        if (state is LinksLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is LinksFailed) {
          return Center(
            child: Text(
              t.entityDetailLoadFailed,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          );
        }
        if (state is! LinksLoaded) return const SizedBox.shrink();
        final grouped = _group(state.links, t);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.links.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  t.linksEmpty,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              for (final entry in grouped.entries) ...[
                _GroupHeader(label: entry.key),
                const SizedBox(height: 4),
                for (final row in entry.value)
                  _LinkRow(
                    row: row,
                    projectId: projectId,
                    onDelete: _canModify(context)
                        ? () => context.read<LinksCubit>().delete(row.link.id)
                        : null,
                  ),
                const SizedBox(height: 12),
              ],
            // Only issues can carry links (backend model); epics show
            // existing rows read-only and no add affordance.
            if (_canModify(context) && sourceKind == EntityKind.issue)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  onPressed: () => _openAdd(context),
                  label: Text(t.actionAddLink),
                ),
              ),
          ],
        );
      },
    );
  }

  bool _canModify(BuildContext context) {
    final s = context.watch<ProjectDetailCubit>().state;
    return s is ProjectDetailLoaded && s.has(modifyPermission);
  }

  Future<void> _openAdd(BuildContext context) async {
    final cubit = context.read<LinksCubit>();
    final result = await showAddLinkDialog(
      context,
      projectId: projectId,
      sourceKind: sourceKind,
      sourceId: sourceId,
      keyPrefix: lookup.prefix,
    );
    if (result == null) return;
    await cubit.add(
      targetKind: result.targetKind,
      targetId: result.targetId,
      type: result.type,
    );
  }

  /// Partition the raw links into display rows grouped by the label that
  /// applies on THIS entity's side (which flips for inbound directional
  /// links). Returns a map preserving insertion order.
  Map<String, List<_LinkRowData>> _group(
    List<EntityLink> links,
    AppLocalizations t,
  ) {
    final out = <String, List<_LinkRowData>>{};
    for (final l in links) {
      final outgoing = l.sourceKind == sourceKind && l.sourceId == sourceId;
      final otherKind = outgoing ? l.targetKind : l.sourceKind;
      final otherId = outgoing ? l.targetId : l.sourceId;
      final label = _labelFor(t, l.type, outgoing);
      out
          .putIfAbsent(label, () => [])
          .add(
            _LinkRowData(
              link: l,
              label: label,
              otherKind: otherKind,
              otherId: otherId,
            ),
          );
    }
    return out;
  }
}

String _labelFor(AppLocalizations t, LinkType type, bool outgoing) {
  if (type.isSymmetric) return t.linkTypeRelates;
  switch (type) {
    case LinkType.blocks:
      return outgoing ? t.linkTypeBlocks : t.linkTypeBlockedBy;
    case LinkType.duplicates:
      return outgoing ? t.linkTypeDuplicates : t.linkTypeDuplicatedBy;
    case LinkType.clones:
      return outgoing ? t.linkTypeClones : t.linkTypeClonedBy;
    case LinkType.causes:
      return outgoing ? t.linkTypeCauses : t.linkTypeCausedBy;
    case LinkType.relates:
      return t.linkTypeRelates;
  }
}

class _LinkRowData {
  const _LinkRowData({
    required this.link,
    required this.label,
    required this.otherKind,
    required this.otherId,
  });
  final EntityLink link;
  final String label;
  final EntityKind otherKind;
  final String otherId;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.row,
    required this.projectId,
    required this.onDelete,
  });
  final _LinkRowData row;
  final String projectId;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Need a LinksLookup to resolve. The widget is wrapped at the panel
    // level by `LinksPanelContent.lookup`. We pull it from an inherited
    // widget via context.findAncestorWidgetOfExactType — but to avoid
    // that, the parent passes a builder. To keep code straightforward we
    // re-look-up via the parent context's ancestor query.
    final lookupHost = context
        .findAncestorWidgetOfExactType<LinksPanelContent>();
    final resolved = lookupHost?.lookup.resolve(row.otherKind, row.otherId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (resolved != null) ...[
            IssueKeyChip(text: resolved.key),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => context.go(
                  Routes.entityDetailFor(
                    projectId,
                    row.otherKind,
                    row.otherId,
                  ),
                ),
                child: Text(
                  resolved.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                row.otherId,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: AppLocalizations.of(context).actionDelete,
              onPressed: () async {
                final t = AppLocalizations.of(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: Text(t.linkDeleteConfirm),
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
                if (ok ?? false) onDelete?.call();
              },
            ),
        ],
      ),
    );
  }
}
