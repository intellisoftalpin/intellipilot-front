import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Reusable epic create / edit dialog. Returns the [CreateEpicRequest] that
/// the caller forwards either to `createEpic` or `updateEpic` — the surfaces
/// share the same fields so we model both via one DTO.
Future<CreateEpicRequest?> showEpicEditDialog(
  BuildContext context, {
  Epic? existing,
}) async {
  final t = AppLocalizations.of(context);
  final subjectCtrl =
      TextEditingController(text: existing?.subject ?? '');
  final descCtrl =
      TextEditingController(text: existing?.description ?? '');
  var color = (existing?.color.isNotEmpty ?? false)
      ? existing!.color
      : ColorPalette.swatches.first;
  return showDialog<CreateEpicRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          existing == null ? t.actionNewEpic : t.actionEditEpic,
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: subjectCtrl,
                autofocus: true,
                decoration: InputDecoration(labelText: t.backlogFieldSubject),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: t.backlogFieldDescription,
                ),
              ),
              const SizedBox(height: 12),
              Text(t.fieldColor),
              const SizedBox(height: 4),
              ColorSwatchPicker(
                selectedHex: color,
                onChanged: (h) => setState(() => color = h),
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
            onPressed: () {
              final subject = subjectCtrl.text.trim();
              if (subject.isEmpty) return;
              Navigator.of(ctx).pop(
                CreateEpicRequest(
                  subject: subject,
                  description: descCtrl.text.trim(),
                  color: color,
                ),
              );
            },
            child: Text(t.actionSave),
          ),
        ],
      ),
    ),
  );
}
