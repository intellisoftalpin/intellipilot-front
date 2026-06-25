import 'package:flutter/material.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Maps `issue_status` items to the epics board's "In Progress" column. Closed
/// statuses always belong to "Done" (shown but not selectable); everything
/// unchecked falls into "All". Returns the chosen in-progress status ids, or
/// null when cancelled.
Future<List<String>?> showEpicBoardSettingsDialog(
  BuildContext context, {
  required List<TaxonomyItem> statuses,
  required List<String> inProgressIds,
}) {
  final selected = inProgressIds.toSet();
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) {
      final t = AppLocalizations.of(ctx);
      final theme = Theme.of(ctx);
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t.epicBoardSettingsTitle),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.epicBoardSettingsHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in statuses)
                        if (s.isClosed ?? false)
                          ListTile(
                            dense: true,
                            leading: HexColorDot(hex: s.color, size: 14),
                            title: Text(s.name),
                            trailing: Chip(
                              label: Text(t.epicsColDone),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        else
                          CheckboxListTile(
                            dense: true,
                            value: selected.contains(s.id),
                            secondary: HexColorDot(hex: s.color, size: 14),
                            title: Text(s.name),
                            onChanged: (v) => setState(() {
                              if (v ?? false) {
                                selected.add(s.id);
                              } else {
                                selected.remove(s.id);
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
              onPressed: () => Navigator.of(ctx).pop(selected.toList()),
              child: Text(t.actionSave),
            ),
          ],
        ),
      );
    },
  );
}
