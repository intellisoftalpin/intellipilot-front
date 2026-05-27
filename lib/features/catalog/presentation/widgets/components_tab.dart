import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/components_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class ComponentsTab extends StatelessWidget {
  const ComponentsTab({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ComponentsCubit>(
      create: (_) => ComponentsCubit(
        repo: getIt<CatalogRepository>(),
        projectId: projectId,
      )..load(),
      child: const _ComponentsView(),
    );
  }
}

class _ComponentsView extends StatelessWidget {
  const _ComponentsView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit = detail is ProjectDetailLoaded &&
        detail.has(Permission.projectModify);

    return BlocBuilder<ComponentsCubit, ComponentsState>(
      builder: (context, state) {
        if (state is ComponentsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ComponentsLoadFailed) {
          return Center(child: Text(t.componentsLoadFailed));
        }
        if (state is! ComponentsLoaded) return const SizedBox.shrink();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canEdit)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showEditDialog(context, null),
                  label: Text(t.actionNewComponent),
                ),
              ),
            const SizedBox(height: 8),
            if (state.components.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(t.componentsEmpty, textAlign: TextAlign.center),
              )
            else
              for (final component in state.components)
                Card(
                  child: ListTile(
                    leading: HexColorDot(hex: component.color, size: 18),
                    title: Text(component.name),
                    subtitle: Text(
                      component.gitRepository == null ||
                              component.gitRepository!.isEmpty
                          ? component.color
                          : component.gitRepository!,
                    ),
                    trailing: canEdit
                        ? Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: t.actionEdit,
                                onPressed: () =>
                                    _showEditDialog(context, component),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: t.actionDelete,
                                onPressed: () =>
                                    _confirmDelete(context, component),
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

  Future<void> _showEditDialog(
    BuildContext context,
    Component? existing,
  ) async {
    final t = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final repoCtrl = TextEditingController(
      text: existing?.gitRepository ?? '',
    );
    var color = (existing?.color.isNotEmpty ?? false)
        ? existing!.color
        : ColorPalette.swatches.first;
    final cubit = context.read<ComponentsCubit>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null
                ? t.actionNewComponent
                : t.actionEditComponent,
          ),
          content: SizedBox(
            width: 400,
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
                TextField(
                  controller: repoCtrl,
                  decoration: InputDecoration(
                    labelText: t.componentRepoLabel,
                    helperText: t.componentRepoHint,
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
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final repo = repoCtrl.text.trim();
                if (existing == null) {
                  await cubit.create(
                    name: name,
                    color: color,
                    gitRepository: repo.isEmpty ? null : repo,
                  );
                } else {
                  await cubit.update(existing.id, name: name, color: color);
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

  Future<void> _confirmDelete(
    BuildContext context,
    Component component,
  ) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.componentDeleteTitle),
        content: Text(t.componentDeleteConfirm(component.name)),
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
      await context.read<ComponentsCubit>().delete(component.id);
    }
  }
}
