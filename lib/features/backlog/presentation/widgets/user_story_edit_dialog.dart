import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Result of [showUserStoryEditDialog]. Mirrors both create and update
/// requests — the caller chooses which payload to send.
class UserStoryDialogResult {
  const UserStoryDialogResult({
    required this.subject,
    required this.description,
    this.statusId,
    this.epicId,
    this.pointsId,
  });

  final String subject;
  final String description;
  final String? statusId;
  final String? epicId;
  final String? pointsId;

  CreateUserStoryRequest toCreate() => CreateUserStoryRequest(
    subject: subject,
    description: description,
    statusId: statusId,
    epicId: epicId,
    pointsId: pointsId,
  );
}

extension _CreateAdapter on UserStoryDialogResult {
  CreateUserStoryRequest get asCreate => toCreate();
}

/// Shows the user-story dialog. Returns a [CreateUserStoryRequest] on save
/// (callers map it to create or update on their side via `BacklogCubit`).
Future<CreateUserStoryRequest?> showUserStoryEditDialog(
  BuildContext context, {
  required List<Epic> epics,
  required List<TaxonomyItem> statuses,
  required List<TaxonomyItem> points,
  UserStory? existing,
}) async {
  final t = AppLocalizations.of(context);
  final subjectCtrl =
      TextEditingController(text: existing?.subject ?? '');
  final descCtrl =
      TextEditingController(text: existing?.description ?? '');
  var statusId = existing?.statusId;
  var epicId = existing?.epicId;
  var pointsId = existing?.pointsId;

  return showDialog<CreateUserStoryRequest>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          existing == null ? t.actionNewUserStory : t.actionEditUserStory,
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
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: t.backlogFieldDescription,
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: pointsId,
                decoration: InputDecoration(labelText: t.backlogFieldPoints),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(t.backlogNoPoints),
                  ),
                  ...points.map(
                    (p) => DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text(
                        p.value == null ? p.name : '${p.name} (${p.value})',
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => pointsId = v),
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
                UserStoryDialogResult(
                  subject: subject,
                  description: descCtrl.text.trim(),
                  statusId: statusId,
                  epicId: epicId,
                  pointsId: pointsId,
                ).asCreate,
              );
            },
            child: Text(t.actionSave),
          ),
        ],
      ),
    ),
  );
}
