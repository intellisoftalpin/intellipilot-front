import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The "New project" dialog. [create] performs the request and returns the
/// new project, or null on failure (the caller reports it). On success the
/// app navigates to the new project.
Future<void> showCreateProjectDialog(
  BuildContext context, {
  required Future<Project?> Function(CreateProjectRequest body) create,
}) async {
  final t = AppLocalizations.of(context);
  final nameController = TextEditingController();
  final descController = TextEditingController();
  final prefixController = TextEditingController();
  var visibility = ProjectVisibility.private;
  String? color;

  final created = await showDialog<Project?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: Text(t.actionNewProject),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(labelText: t.projectFieldName),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: t.projectFieldDescription,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ProjectVisibility>(
                  initialValue: visibility,
                  decoration: InputDecoration(
                    labelText: t.projectFieldVisibility,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: ProjectVisibility.private,
                      child: Text(t.projectVisibilityPrivate),
                    ),
                    DropdownMenuItem(
                      value: ProjectVisibility.internal,
                      child: Text(t.projectVisibilityInternal),
                    ),
                    DropdownMenuItem(
                      value: ProjectVisibility.publicReadonly,
                      child: Text(t.projectVisibilityPublicReadonly),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => visibility = v ?? visibility),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prefixController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                    LengthLimitingTextInputFormatter(3),
                    TextInputFormatter.withFunction(
                      (_, n) => n.copyWith(text: n.text.toUpperCase()),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: t.projectFieldPrefix,
                    helperText: t.projectFieldPrefixOptional,
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t.projectFieldColor,
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                ColorSwatchPicker(
                  selectedHex: color ?? '',
                  onChanged: (hex) => setState(() => color = hex),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(t.actionCancel),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final prefix = prefixController.text.trim().toUpperCase();
                // A typed prefix must be 2–3 letters; blank = auto-derive.
                if (prefix.isNotEmpty && prefix.length < 2) return;
                final created = await create(
                  CreateProjectRequest(
                    name: name,
                    description: descController.text.trim(),
                    visibility: visibility,
                    issuePrefix: prefix.isEmpty ? null : prefix,
                    color: color,
                  ),
                );
                if (ctx.mounted) Navigator.of(ctx).pop(created);
              },
              child: Text(t.actionCreate),
            ),
          ],
        );
      },
    ),
  );
  if (created != null && context.mounted) {
    context.go(Routes.projectDetailFor(created.id));
  }
}
