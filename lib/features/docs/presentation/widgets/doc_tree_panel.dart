import 'package:flutter/material.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The contents panel that sits on the **right** of the documentation viewer.
///
/// It lives on the right because the left of the screen already belongs to the
/// project navigation rail; putting a second tree there would give the reader
/// two competing hierarchies to parse.
///
/// Two sections: the source's folder tree, and the headings of the document
/// currently open.
class DocTreePanel extends StatelessWidget {
  const DocTreePanel({
    required this.tree,
    required this.currentPath,
    required this.headings,
    required this.onOpen,
    required this.onHeadingTap,
    super.key,
  });

  final DocTree tree;

  /// Jail-relative path of the open document, or null on the folder listing.
  final String? currentPath;
  final List<MarkdownHeading> headings;
  final void Function(String path) onOpen;
  final void Function(MarkdownHeading heading) onHeadingTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          children: [
            _SectionLabel(t.docsContents),
            if (tree.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  t.docsEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              for (final entry in tree.entries)
                _TreeNode(
                  entry: entry,
                  depth: 0,
                  currentPath: currentPath,
                  onOpen: onOpen,
                ),
            if (headings.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionLabel(t.docsOnThisPage),
              for (final h in headings)
                _HeadingRow(heading: h, onTap: () => onHeadingTap(h)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One node of the folder tree. Directories start expanded: a documentation
/// set is meant to be scanned, and collapsing everything hides exactly what
/// the reader came for.
class _TreeNode extends StatefulWidget {
  const _TreeNode({
    required this.entry,
    required this.depth,
    required this.currentPath,
    required this.onOpen,
  });

  final DocEntry entry;
  final int depth;
  final String? currentPath;
  final void Function(String path) onOpen;

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  late bool _expanded = true;

  @override
  void didUpdateWidget(_TreeNode old) {
    super.didUpdateWidget(old);
    // Navigating into a collapsed folder reveals it, so the reader never
    // loses their place in the tree.
    final current = widget.currentPath;
    if (!_expanded &&
        current != null &&
        current.startsWith('${widget.entry.path}/')) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final selected = entry.path == widget.currentPath;
    final indent = 8.0 + widget.depth * 12;

    if (!entry.isDir) {
      return _Row(
        indent: indent,
        selected: selected,
        icon: Icons.description_outlined,
        label: entry.name,
        onTap: () => widget.onOpen(entry.path),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          indent: indent,
          selected: false,
          icon: _expanded ? Icons.folder_open : Icons.folder_outlined,
          label: entry.name,
          bold: true,
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 16,
            color: theme.colorScheme.outline,
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          for (final child in entry.children)
            _TreeNode(
              entry: child,
              depth: widget.depth + 1,
              currentPath: widget.currentPath,
              onOpen: widget.onOpen,
            ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.indent,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.bold = false,
    this.trailing,
  });

  final double indent;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool bold;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.secondaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: EdgeInsets.fromLTRB(indent, 6, 8, 6),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: bold || selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: selected
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _HeadingRow extends StatelessWidget {
  const _HeadingRow({required this.heading, required this.onTap});
  final MarkdownHeading heading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // h1 is usually the document title, already shown above; indent from h2 so
    // the outline reads as a hierarchy rather than a flat list.
    final indent = 8.0 + (heading.level - 1).clamp(0, 4) * 10;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 5, 8, 5),
        child: Text(
          heading.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: heading.level <= 2 ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
