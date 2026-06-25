import 'package:flutter/material.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Shared create/edit dialog. Result is a [CreateMilestoneRequest]; callers
/// map to [UpdateMilestoneRequest] when editing an existing record.
Future<CreateMilestoneRequest?> showMilestoneEditDialog(
  BuildContext context, {
  Milestone? existing,
}) {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  var start = existing?.startDate;
  var end = existing?.endDate;
  return showDialog<CreateMilestoneRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final t = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(
            existing == null ? t.milestoneCreateTitle : t.milestoneEditTitle,
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(labelText: t.milestoneFieldName),
                ),
                const SizedBox(height: 16),
                _DateField(
                  label: t.milestoneFieldStart,
                  value: start,
                  onChanged: (v) => setState(() => start = v),
                ),
                const SizedBox(height: 8),
                _DateField(
                  label: t.milestoneFieldEnd,
                  value: end,
                  onChanged: (v) => setState(() => end = v),
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
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.of(ctx).pop(
                  CreateMilestoneRequest(
                    name: name,
                    startDate: start,
                    endDate: end,
                  ),
                );
              },
              child: Text(t.actionSave),
            ),
          ],
        );
      },
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(
              value == null
                  ? t.milestoneDateNotSet
                  : '${value!.year.toString().padLeft(4, '0')}'
                        '-${value!.month.toString().padLeft(2, '0')}'
                        '-${value!.day.toString().padLeft(2, '0')}',
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.event),
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 5),
            );
            if (picked != null) onChanged(picked);
          },
        ),
        if (value != null)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}
