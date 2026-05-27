import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class BulkPasteResult {
  const BulkPasteResult({required this.subjects, this.epicId});
  final List<String> subjects;
  final String? epicId;
}

/// Modal for the "paste many user stories" flow. Splits the textarea by line
/// and trims; callers fan-out to `bulk_create_us`.
Future<BulkPasteResult?> showBulkPasteDialog(
  BuildContext context, {
  required List<Epic> epics,
}) async {
  final t = AppLocalizations.of(context);
  final controller = TextEditingController();
  String? epicId;

  return showDialog<BulkPasteResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(t.backlogBulkTitle),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.backlogBulkBody),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: epicId,
                decoration: InputDecoration(labelText: t.backlogFieldEpic),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(t.backlogNoEpic),
                  ),
                  ...epics.map(
                    (e) => DropdownMenuItem<String?>(
                      value: e.id,
                      child: Text('EPIC-${e.reference} · ${e.subject}'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => epicId = v),
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
              final lines = controller.text
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
              if (lines.isEmpty) return;
              Navigator.of(ctx).pop(
                BulkPasteResult(subjects: lines, epicId: epicId),
              );
            },
            child: Text(t.backlogBulkCreate),
          ),
        ],
      ),
    ),
  );
}
