import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Epic creation dialog — asks only for a title and colour. Everything else
/// (description, status, milestone, dates, cover image…) is filled in on the
/// epic sidebar, which the caller opens right after creating.
Future<CreateEpicRequest?> showEpicEditDialog(BuildContext context) async {
  final t = AppLocalizations.of(context);
  final subjectCtrl = TextEditingController();
  var color = ColorPalette.swatches.first;
  return showDialog<CreateEpicRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(t.actionNewEpic),
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
                CreateEpicRequest(subject: subject, color: color),
              );
            },
            child: Text(t.actionSave),
          ),
        ],
      ),
    ),
  );
}
