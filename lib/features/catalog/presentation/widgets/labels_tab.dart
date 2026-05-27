import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/labels_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class LabelsTab extends StatelessWidget {
  const LabelsTab({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LabelsCubit>(
      create: (_) =>
          LabelsCubit(repo: getIt<CatalogRepository>(), projectId: projectId)
            ..load(),
      child: const _LabelsView(),
    );
  }
}

class _LabelsView extends StatelessWidget {
  const _LabelsView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit = detail is ProjectDetailLoaded &&
        detail.has(Permission.projectModify);

    return BlocBuilder<LabelsCubit, LabelsState>(
      builder: (context, state) {
        if (state is LabelsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is LabelsLoadFailed) {
          return Center(child: Text(t.labelsLoadFailed));
        }
        if (state is! LabelsLoaded) return const SizedBox.shrink();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canEdit)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showEditDialog(context, null),
                  label: Text(t.actionNewLabel),
                ),
              ),
            const SizedBox(height: 8),
            if (state.labels.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t.labelsEmpty, textAlign: TextAlign.center),
              )
            else
              for (final label in state.labels)
                Card(
                  child: ListTile(
                    leading: HexColorDot(hex: label.color, size: 18),
                    title: Text(label.name),
                    subtitle: Text(label.color),
                    trailing: canEdit
                        ? Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: t.actionEdit,
                                onPressed: () =>
                                    _showEditDialog(context, label),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: t.actionDelete,
                                onPressed: () =>
                                    _confirmDelete(context, label),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<void> _showEditDialog(BuildContext context, Label? existing) async {
    final t = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var color = (existing?.color.isNotEmpty ?? false)
        ? existing!.color
        : ColorPalette.swatches.first;
    final cubit = context.read<LabelsCubit>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null ? t.actionNewLabel : t.actionEditLabel,
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
                  decoration: InputDecoration(labelText: t.fieldName),
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
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                if (existing == null) {
                  await cubit.create(name: name, color: color);
                } else {
                  await cubit.update(
                    existing.id,
                    name: name,
                    color: color,
                  );
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(t.actionSave),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Label label) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.labelDeleteTitle),
        content: Text(t.labelDeleteConfirm(label.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if ((ok ?? false) && context.mounted) {
      await context.read<LabelsCubit>().delete(label.id);
    }
  }
}
