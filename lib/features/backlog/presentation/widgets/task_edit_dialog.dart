import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Shared create/edit dialog for tasks. Result is a [CreateTaskRequest];
/// callers map it to an [UpdateTaskRequest] when editing.
///
/// Mirrors `showUserStoryEditDialog` in shape — pass the parent user-story
/// list + the `task_status` taxonomy so the dropdowns can render.
Future<CreateTaskRequest?> showTaskEditDialog(
  BuildContext context, {
  required List<UserStory> userStories,
  required List<TaxonomyItem> statuses,
  Task? existing,
}) async {
  final t = AppLocalizations.of(context);
  final subjectCtrl = TextEditingController(text: existing?.subject ?? '');
  final descCtrl = TextEditingController(text: existing?.description ?? '');
  var statusId = existing?.statusId;
  var userStoryId = existing?.userStoryId;

  return showDialog<CreateTaskRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          existing == null ? t.actionNewTask : t.actionEditTask,
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
                decoration:
                    InputDecoration(labelText: t.backlogFieldSubject),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: t.backlogFieldDescription,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: userStoryId,
                isExpanded: true,
                decoration: InputDecoration(labelText: t.taskFieldParent),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(t.taskNoParent),
                  ),
                  ...userStories.map(
                    (us) => DropdownMenuItem<String?>(
                      value: us.id,
                      child: Text(
                        'US-${us.reference} · ${us.subject}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => userStoryId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: statusId,
                decoration: InputDecoration(labelText: t.backlogFieldStatus),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(t.backlogNoStatus),
                  ),
                  ...statuses.map(
                    (s) => DropdownMenuItem<String?>(
                      value: s.id,
                      child: Text(s.name),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => statusId = v),
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
                CreateTaskRequest(
                  subject: subject,
                  description: descCtrl.text.trim(),
                  statusId: statusId,
                  userStoryId: userStoryId,
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
