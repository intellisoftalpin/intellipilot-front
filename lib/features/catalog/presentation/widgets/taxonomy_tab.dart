import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/cubits/taxonomy_cubit.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Stateful kind chooser + reorderable list of [TaxonomyItem]s per kind. The
/// [TaxonomyCubit] is recreated each time [kind] flips so the list reloads.
class TaxonomyTab extends StatefulWidget {
  const TaxonomyTab({required this.projectId, super.key});
  final String projectId;

  @override
  State<TaxonomyTab> createState() => _TaxonomyTabState();
}

class _TaxonomyTabState extends State<TaxonomyTab> {
  TaxonomyKind _kind = TaxonomyKind.usStatus;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 8,
              children: [
                for (final k in TaxonomyKind.values)
                  ChoiceChip(
                    label: Text(_kindLabel(t, k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: BlocProvider<TaxonomyCubit>(
            key: ValueKey(_kind),
            create: (_) => TaxonomyCubit(
              repo: getIt<CatalogRepository>(),
              projectId: widget.projectId,
              kind: _kind,
            )..load(),
            child: _TaxonomyKindView(kind: _kind),
          ),
        ),
      ],
    );
  }

  String _kindLabel(AppLocalizations t, TaxonomyKind k) => switch (k) {
    TaxonomyKind.usStatus => t.taxKindUsStatus,
    TaxonomyKind.taskStatus => t.taxKindTaskStatus,
    TaxonomyKind.issueStatus => t.taxKindIssueStatus,
    TaxonomyKind.issueType => t.taxKindIssueType,
    TaxonomyKind.priority => t.taxKindPriority,
    TaxonomyKind.severity => t.taxKindSeverity,
    TaxonomyKind.point => t.taxKindPoint,
  };
}

class _TaxonomyKindView extends StatelessWidget {
  const _TaxonomyKindView({required this.kind});
  final TaxonomyKind kind;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = context.watch<ProjectDetailCubit>().state;
    final canEdit =
        detail is ProjectDetailLoaded && detail.has(Permission.projectModify);

    return BlocBuilder<TaxonomyCubit, TaxonomyState>(
      builder: (context, state) {
        if (state is TaxonomyLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is TaxonomyLoadFailed) {
          return Center(child: Text(t.taxonomyLoadFailed));
        }
        if (state is! TaxonomyLoaded) return const SizedBox.shrink();
        return Column(
          children: [
            if (canEdit)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showEditDialog(context, kind, null),
                    label: Text(t.actionNewTaxonomyItem),
                  ),
                ),
              ),
            Expanded(
              child: state.items.isEmpty
                  ? Center(child: Text(t.taxonomyEmpty))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      buildDefaultDragHandles: false,
                      itemCount: state.items.length,
                      onReorderItem: canEdit
                          ? (oldIndex, newIndex) {
                              final moved = state.items[oldIndex];
                              // onReorderItem doesn't pre-adjust newIndex
                              // when moving downward; the cubit's reorder
                              // applies the same shift internally so we can
                              // pass the raw index through.
                              context
                                  .read<TaxonomyCubit>()
                                  .reorder(moved.id, newIndex);
                            }
                          : (_, _) {},
                      itemBuilder: (context, i) {
                        final item = state.items[i];
                        return Padding(
                          key: ValueKey(item.id),
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Card(
                            child: ListTile(
                              leading: HexColorDot(hex: item.color, size: 20),
                              title: Text(item.name),
                              subtitle: _ItemSubtitle(item: item),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  if (canEdit) ...[
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: t.actionEdit,
                                      onPressed: () => _showEditDialog(
                                        context,
                                        kind,
                                        item,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: t.actionDelete,
                                      onPressed: () =>
                                          _confirmDelete(context, item),
                                    ),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: const Icon(Icons.drag_handle),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    TaxonomyKind kind,
    TaxonomyItem? existing,
  ) async {
    final t = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final slugCtrl = TextEditingController(text: existing?.slug ?? '');
    final valueCtrl = TextEditingController(
      text: existing?.value?.toString() ?? '',
    );
    var color = (existing?.color.isNotEmpty ?? false)
        ? existing!.color
        : ColorPalette.swatches.first;
    var isClosed = existing?.isClosed ?? false;
    final cubit = context.read<TaxonomyCubit>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            existing == null
                ? t.actionNewTaxonomyItem
                : t.actionEditTaxonomyItem,
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
                  controller: slugCtrl,
                  enabled: existing == null,
                  decoration: InputDecoration(
                    labelText: t.fieldSlug,
                    helperText: existing == null ? null : t.fieldSlugFrozenHint,
                  ),
                ),
                const SizedBox(height: 12),
                Text(t.fieldColor),
                const SizedBox(height: 4),
                ColorSwatchPicker(
                  selectedHex: color,
                  onChanged: (h) => setState(() => color = h),
                ),
                if (kind.hasClosed) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.taxonomyIsClosed),
                    subtitle: Text(t.taxonomyIsClosedHint),
                    value: isClosed,
                    onChanged: (v) => setState(() => isClosed = v),
                  ),
                ],
                if (kind.hasValue) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: t.taxonomyValueLabel,
                      helperText: t.taxonomyValueHint,
                    ),
                  ),
                ],
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
                final value = kind.hasValue
                    ? double.tryParse(valueCtrl.text.trim())
                    : null;
                if (existing == null) {
                  final slug = slugCtrl.text.trim();
                  if (slug.isEmpty) return;
                  await cubit.create(
                    CreateTaxonomyItemRequest(
                      name: name,
                      slug: slug,
                      color: color,
                      isClosed: kind.hasClosed ? isClosed : null,
                      value: value,
                    ),
                  );
                } else {
                  await cubit.update(
                    existing.id,
                    UpdateTaxonomyItemRequest(
                      name: name,
                      color: color,
                      isClosed: kind.hasClosed ? isClosed : null,
                      value: value,
                    ),
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

  Future<void> _confirmDelete(
    BuildContext context,
    TaxonomyItem item,
  ) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.taxonomyDeleteTitle),
        content: Text(t.taxonomyDeleteConfirm(item.name)),
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
      await context.read<TaxonomyCubit>().delete(item.id);
    }
  }
}

class _ItemSubtitle extends StatelessWidget {
  const _ItemSubtitle({required this.item});
  final TaxonomyItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final parts = <String>[item.slug];
    if (item.isClosed ?? false) parts.add(t.taxonomyClosedBadge);
    if (item.value != null) {
      parts.add('${t.taxonomyValueLabel}: ${item.value}');
    }
    return Text(parts.join(' · '));
  }
}
