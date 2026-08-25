import 'package:flutter/material.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The result of the board-columns settings dialog: the full ordering of status
/// ids and the subset that should stay hidden.
class BoardColumnsResult {
  const BoardColumnsResult({required this.order, required this.hidden});
  final List<String> order;
  final Set<String> hidden;
}

/// Lets the user show/hide and reorder the board's status columns. [order] is
/// the current full ordering of status ids; [hidden] the currently hidden set.
/// Returns null when cancelled.
Future<BoardColumnsResult?> showBoardColumnsDialog(
  BuildContext context, {
  required List<TaxonomyItem> statuses,
  required List<String> order,
  required Set<String> hidden,
}) {
  final byId = {for (final s in statuses) s.id: s};
  // Work on a local, mutable ordering that includes every known status.
  final working = <String>[
    ...order.where(byId.containsKey),
    for (final s in statuses)
      if (!order.contains(s.id)) s.id,
  ];
  final hiddenSet = {...hidden};

  return showDialog<BoardColumnsResult>(
    context: context,
    builder: (ctx) {
      final t = AppLocalizations.of(ctx);
      final theme = Theme.of(ctx);
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t.boardColumnsTitle),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.boardColumnsHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ReorderableListView(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    // onReorderItem adjusts newIndex for the removed item
                    // itself, so no manual `newIndex - 1` when dragging down.
                    onReorderItem: (oldIndex, newIndex) => setState(() {
                      final id = working.removeAt(oldIndex);
                      working.insert(newIndex, id);
                    }),
                    children: [
                      for (var i = 0; i < working.length; i++)
                        if (byId[working[i]] != null)
                          _ColumnRow(
                            key: ValueKey(working[i]),
                            index: i,
                            status: byId[working[i]]!,
                            visible: !hiddenSet.contains(working[i]),
                            onVisibleChanged: (v) => setState(() {
                              if (v) {
                                hiddenSet.remove(working[i]);
                              } else {
                                hiddenSet.add(working[i]);
                              }
                            }),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(
                BoardColumnsResult(order: working, hidden: hiddenSet),
              ),
              child: Text(t.actionSaveShort),
            ),
          ],
        ),
      );
    },
  );
}

class _ColumnRow extends StatelessWidget {
  const _ColumnRow({
    required this.index,
    required this.status,
    required this.visible,
    required this.onVisibleChanged,
    super.key,
  });

  final int index;
  final TaxonomyItem status;
  final bool visible;
  final ValueChanged<bool> onVisibleChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: HexColorDot(hex: status.color, size: 14),
      title: Text(status.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: visible, onChanged: onVisibleChanged),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  }
}
