import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/ui/breadcrumb_bar.dart';
import 'package:intellipilot/core/ui/breakpoints.dart';
import 'package:intellipilot/core/ui/timestamps.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Routed full-page editor for backlog entities. Replaces the modal
/// `openEditDialog` for surfaces that want a Jira-style deep-linkable edit
/// screen (entity detail page → Edit). The same fields render in a Scaffold
/// with a sticky Cancel / Save action bar instead of an `AlertDialog`.
class EntityEditPage extends StatefulWidget {
  const EntityEditPage({
    required this.projectId,
    required this.kind,
    required this.entityId,
    super.key,
  });

  final String projectId;
  final EntityKind kind;
  final String entityId;

  @override
  State<EntityEditPage> createState() => _EntityEditPageState();
}

class _EntityEditPageState extends State<EntityEditPage> {
  late Future<_EditData?> _future;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_EditData?> _load() async {
    final backlog = getIt<BacklogRepository>();
    final catalog = getIt<CatalogRepository>();
    final projects = getIt<ProjectsRepository>();
    final milestones = getIt<MilestonesRepository>();
    final profileRepo = getIt<ProfileRepository>();
    final project =
        (await projects.getProject(widget.projectId)).valueOrNull;
    if (project == null) return null;
    final profile = (await profileRepo.getProfile()).valueOrNull;
    switch (widget.kind) {
      case EntityKind.epic:
        final entity =
            (await backlog.getEpic(widget.projectId, widget.entityId))
                .valueOrNull;
        if (entity == null) return null;
        return _EditData(
          project: project,
          profile: profile,
          epic: entity,
        );
      case EntityKind.issue:
        final entity =
            (await backlog.getIssue(widget.projectId, widget.entityId))
                .valueOrNull;
        if (entity == null) return null;
        final epics =
            (await backlog.listEpics(widget.projectId)).valueOrNull ?? [];
        final ms = (await milestones.list(widget.projectId)).valueOrNull ?? [];
        final statuses = (await catalog.listTaxonomy(
                  widget.projectId, TaxonomyKind.issueStatus,
                ))
                .valueOrNull ??
            [];
        final types = (await catalog.listTaxonomy(
                  widget.projectId, TaxonomyKind.issueType,
                ))
                .valueOrNull ??
            [];
        final priorities = (await catalog.listTaxonomy(
                  widget.projectId, TaxonomyKind.priority,
                ))
                .valueOrNull ??
            [];
        final sizes = (await catalog.listTaxonomy(
                  widget.projectId, TaxonomyKind.size,
                ))
                .valueOrNull ??
            [];
        final labels =
            (await catalog.listLabels(widget.projectId)).valueOrNull ?? [];
        final components =
            (await catalog.listComponents(widget.projectId)).valueOrNull ??
                [];
        final customers =
            (await catalog.listCustomers(widget.projectId)).valueOrNull ?? [];
        // Fix-version options for the issue's currently-selected components.
        final fixVersions = entity.components.isEmpty
            ? <ReleaseVersionRef>[]
            : (await catalog.versionsForComponents(
                        widget.projectId, entity.components,
                      ))
                    .valueOrNull ??
                [];
        return _EditData(
          project: project,
          profile: profile,
          issue: entity,
          epics: epics,
          milestones: ms,
          statuses: statuses,
          types: types,
          priorities: priorities,
          sizes: sizes,
          labels: labels,
          components: components,
          customers: customers,
          fixVersions: fixVersions,
        );
    }
  }

  void _cancel() {
    context.go(
      Routes.entityDetailFor(widget.projectId, widget.kind, widget.entityId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EditData?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data;
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text(AppLocalizations.of(context).entityDetailLoadFailed),
            ),
          );
        }
        return _EditView(
          data: data,
          kind: widget.kind,
          projectId: widget.projectId,
          entityId: widget.entityId,
          saving: _saving,
          onCancel: _cancel,
          onSavingChanged: (v) => setState(() => _saving = v),
        );
      },
    );
  }
}

class _EditData {
  _EditData({
    required this.project,
    this.profile,
    this.epic,
    this.issue,
    this.epics = const [],
    this.milestones = const [],
    this.statuses = const [],
    this.sizes = const [],
    this.types = const [],
    this.priorities = const [],
    this.labels = const [],
    this.components = const [],
    this.customers = const [],
    this.fixVersions = const [],
  });

  final Project project;
  final UserProfile? profile;
  final Epic? epic;
  final Issue? issue;
  final List<Epic> epics;
  final List<Milestone> milestones;
  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> sizes;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<Label> labels;
  final List<Component> components;
  final List<Customer> customers;
  final List<ReleaseVersionRef> fixVersions;
}

class _EditView extends StatefulWidget {
  const _EditView({
    required this.data,
    required this.kind,
    required this.projectId,
    required this.entityId,
    required this.saving,
    required this.onCancel,
    required this.onSavingChanged,
  });

  final _EditData data;
  final EntityKind kind;
  final String projectId;
  final String entityId;
  final bool saving;
  final VoidCallback onCancel;
  final ValueChanged<bool> onSavingChanged;

  @override
  State<_EditView> createState() => _EditViewState();
}

class _EditViewState extends State<_EditView> {
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _assigneeCtrl;
  late final TextEditingController _reporterCtrl;

  String? _statusId;
  String? _epicId;
  String? _milestoneId;
  String? _sizeId;
  String? _parentId;
  String? _typeId;
  String? _priorityId;
  String? _category;
  String? _customerId;
  String? _resolution;
  String? _releaseVersionId;
  late final TextEditingController _releaseTextCtrl;
  late final TextEditingController _startDateCtrl;
  late final TextEditingController _dueDateCtrl;
  String _color = '';
  final _labels = <String>{};
  final _components = <String>{};

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _subjectCtrl = TextEditingController(text: _initialSubject(d));
    _descCtrl = TextEditingController(text: _initialDescription(d));
    _assigneeCtrl =
        TextEditingController(text: _initialAssignee(d) ?? '');
    _reporterCtrl =
        TextEditingController(text: _initialReporter(d) ?? '');
    _releaseTextCtrl =
        TextEditingController(text: d.issue?.releaseText ?? '');
    _startDateCtrl = TextEditingController(text: d.issue?.startDate ?? '');
    _dueDateCtrl = TextEditingController(text: d.issue?.dueDate ?? '');
    switch (widget.kind) {
      case EntityKind.epic:
        _statusId = d.epic?.statusId;
        _color = (d.epic?.color.isNotEmpty ?? false)
            ? d.epic!.color
            : ColorPalette.swatches.first;
      case EntityKind.issue:
        _statusId = d.issue?.statusId;
        _typeId = d.issue?.typeId;
        _priorityId = d.issue?.priorityId;
        _sizeId = d.issue?.sizeId;
        _epicId = d.issue?.epicId;
        _parentId = d.issue?.parentId;
        _milestoneId = d.issue?.milestoneId;
        _category = d.issue?.category;
        _customerId = d.issue?.customerId;
        _resolution = d.issue?.resolution;
        _releaseVersionId = d.issue?.releaseVersionId;
        _labels.addAll(d.issue?.labels ?? const []);
        _components.addAll(d.issue?.components ?? const []);
    }
  }

  String? _initialAssignee(_EditData d) => switch (widget.kind) {
    EntityKind.epic => d.epic?.assignedTo,
    EntityKind.issue => d.issue?.assignedTo,
  };

  String? _initialReporter(_EditData d) => switch (widget.kind) {
    EntityKind.epic => d.epic?.ownerId,
    EntityKind.issue => d.issue?.ownerId,
  };

  DateTime _createdAt(_EditData d) => switch (widget.kind) {
    EntityKind.epic => d.epic!.createdAt,
    EntityKind.issue => d.issue!.createdAt,
  };

  DateTime _modifiedAt(_EditData d) => switch (widget.kind) {
    EntityKind.epic => d.epic!.modifiedAt,
    EntityKind.issue => d.issue!.modifiedAt,
  };

  String _kindLabel(AppLocalizations t) => switch (widget.kind) {
    EntityKind.epic => t.kindLabelEpic,
    EntityKind.issue => t.kindLabelIssue,
  };

  /// Returns the trimmed text from `c` or `null` when it's empty. Used so
  /// the backend sees an explicit `null` to clear assignee/reporter
  /// instead of an empty string.
  String? _textOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  /// Returns the trimmed `YYYY-MM-DD` text or `null` when empty.
  String? _dateOrNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  String _initialSubject(_EditData d) => switch (widget.kind) {
    EntityKind.epic => d.epic?.subject ?? '',
    EntityKind.issue => d.issue?.subject ?? '',
  };

  String _initialDescription(_EditData d) => switch (widget.kind) {
    EntityKind.epic => d.epic?.description ?? '',
    EntityKind.issue => d.issue?.description ?? '',
  };

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    _assigneeCtrl.dispose();
    _reporterCtrl.dispose();
    _releaseTextCtrl.dispose();
    _startDateCtrl.dispose();
    _dueDateCtrl.dispose();
    super.dispose();
  }

  int _reference(_EditData d) => switch (widget.kind) {
    EntityKind.epic => d.epic!.reference,
    EntityKind.issue => d.issue!.reference,
  };

  String _prefix() => switch (widget.kind) {
    EntityKind.epic => 'EPIC',
    EntityKind.issue => 'ISSUE',
  };

  Future<void> _save() async {
    final subject = _subjectCtrl.text.trim();
    if (subject.isEmpty) return;
    widget.onSavingChanged(true);
    final backlog = getIt<BacklogRepository>();
    final assignedTo = _textOrNull(_assigneeCtrl);
    final ownerId = _textOrNull(_reporterCtrl);
    try {
      switch (widget.kind) {
        case EntityKind.epic:
          final etag = widget.data.epic?.etag;
          if (etag == null) return;
          await backlog.updateEpic(
            widget.projectId,
            widget.entityId,
            body: UpdateEpicRequest(
              subject: subject,
              description: _descCtrl.text.trim(),
              statusId: _statusId,
              color: _color,
              assignedTo: assignedTo,
              ownerId: ownerId,
            ),
            etag: etag,
          );
        case EntityKind.issue:
          final etag = widget.data.issue?.etag;
          if (etag == null) return;
          await backlog.updateIssue(
            widget.projectId,
            widget.entityId,
            body: UpdateIssueRequest(
              subject: subject,
              description: _descCtrl.text.trim(),
              statusId: _statusId,
              typeId: _typeId,
              priorityId: _priorityId,
              sizeId: _sizeId,
              epicId: _epicId,
              parentId: _parentId,
              milestoneId: _milestoneId,
              category: _category,
              // Customer is only meaningful when category == customer_request.
              customerId: _category == IssueCategory.customerRequest.wire
                  ? _customerId
                  : null,
              startDate: _dateOrNull(_startDateCtrl),
              dueDate: _dateOrNull(_dueDateCtrl),
              resolution: _resolution,
              // At most one fix-version representation; structured wins.
              releaseVersionId: _releaseVersionId,
              releaseText: _releaseVersionId == null
                  ? _textOrNull(_releaseTextCtrl)
                  : null,
              labels: _labels.toList(),
              components: _components.toList(),
              assignedTo: assignedTo,
              ownerId: ownerId,
            ),
            etag: etag,
          );
      }
      if (!mounted) return;
      context.go(
        Routes.entityDetailFor(widget.projectId, widget.kind, widget.entityId),
      );
    } finally {
      if (mounted) widget.onSavingChanged(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isWide = Breakpoints.of(context).isExpanded;
    final maxWidth = isWide ? 880.0 : double.infinity;
    final key = '${_prefix()}-${_reference(widget.data)}';
    return Scaffold(
      appBar: AppBar(
        title: BreadcrumbBar(
          crumbs: [
            Crumb(
              label: t.projectsTitle,
              onTap: () => context.go(Routes.projects),
            ),
            Crumb(
              label: widget.data.project.name,
              onTap: () => context.go(
                Routes.projectDetailFor(widget.data.project.id),
              ),
            ),
            Crumb(
              label: key,
              mono: true,
              onTap: () => context.go(
                Routes.entityDetailFor(
                  widget.projectId,
                  widget.kind,
                  widget.entityId,
                ),
              ),
            ),
            Crumb(label: t.actionEdit),
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.saving ? null : widget.onCancel,
            child: Text(t.actionCancel),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              icon: widget.saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              onPressed: widget.saving ? null : _save,
              label: Text(t.actionSave),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section(
                  context,
                  title: t.panelDescription,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _subjectCtrl,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: t.backlogFieldSubject,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descCtrl,
                        maxLines: 6,
                        minLines: 4,
                        decoration: InputDecoration(
                          labelText: t.backlogFieldDescription,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _section(
                  context,
                  title: t.panelDetails,
                  child: _kindFields(t),
                ),
                const SizedBox(height: 12),
                _section(
                  context,
                  title: t.panelPeople,
                  child: _peopleFields(t),
                ),
                const SizedBox(height: 12),
                _section(
                  context,
                  title: t.panelMetadata,
                  child: _metadataFields(t, key),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.saving ? null : widget.onCancel,
                child: Text(t.actionCancel),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: widget.saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                onPressed: widget.saving ? null : _save,
                label: Text(t.actionSave),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindFields(AppLocalizations t) {
    final d = widget.data;
    switch (widget.kind) {
      case EntityKind.epic:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.fieldColor),
            const SizedBox(height: 8),
            ColorSwatchPicker(
              selectedHex: _color,
              onChanged: (h) => setState(() => _color = h),
            ),
          ],
        );
      case EntityKind.issue:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _taxonomyDropdown(
              label: t.issueFieldStatus,
              none: t.backlogNoStatus,
              items: d.statuses,
              current: _statusId,
              onChanged: (v) => setState(() => _statusId = v),
            ),
            const SizedBox(height: 12),
            _idDropdown<Epic>(
              label: t.backlogFieldEpic,
              none: t.backlogNoEpic,
              items: d.epics,
              idOf: (e) => e.id,
              labelOf: (e) => 'EPIC-${e.reference} · ${e.subject}',
              current: _epicId,
              onChanged: (v) => setState(() => _epicId = v),
            ),
            const SizedBox(height: 12),
            _idDropdown<Milestone>(
              label: t.detailFieldMilestone,
              none: t.backlogNoMilestone,
              items: d.milestones,
              idOf: (m) => m.id,
              labelOf: (m) => m.name,
              current: _milestoneId,
              onChanged: (v) => setState(() => _milestoneId = v),
            ),
            const SizedBox(height: 12),
            _taxonomyDropdown(
              label: 'Size',
              none: t.backlogNoStatus,
              items: d.sizes,
              current: _sizeId,
              onChanged: (v) => setState(() => _sizeId = v),
              labelBuilder: (p) =>
                  p.value == null ? p.name : '${p.name} (${p.value})',
            ),
            const SizedBox(height: 12),
            _taxonomyDropdown(
              label: t.issueFieldType,
              none: t.backlogNoStatus,
              items: d.types,
              current: _typeId,
              onChanged: (v) => setState(() => _typeId = v),
            ),
            const SizedBox(height: 12),
            _taxonomyDropdown(
              label: t.issueFieldPriority,
              none: t.backlogNoStatus,
              items: d.priorities,
              current: _priorityId,
              onChanged: (v) => setState(() => _priorityId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem<String?>(child: Text('—')),
                for (final c in IssueCategory.values)
                  DropdownMenuItem<String?>(
                    value: c.wire,
                    child: Text(c.label),
                  ),
              ],
              onChanged: (v) => setState(() {
                _category = v;
                // Customer only applies to customer requests.
                if (v != IssueCategory.customerRequest.wire) {
                  _customerId = null;
                }
              }),
            ),
            if (_category == IssueCategory.customerRequest.wire) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _customerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Customer'),
                items: [
                  const DropdownMenuItem<String?>(child: Text('—')),
                  for (final c in d.customers)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                ],
                onChanged: (v) => setState(() => _customerId = v),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startDateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Start date',
                      hintText: 'YYYY-MM-DD',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _dueDateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Due date',
                      hintText: 'YYYY-MM-DD',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _resolution,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Resolution'),
              items: [
                const DropdownMenuItem<String?>(child: Text('—')),
                for (final r in IssueResolution.values)
                  DropdownMenuItem<String?>(
                    value: r.wire,
                    child: Text(r.label),
                  ),
              ],
              onChanged: (v) => setState(() => _resolution = v),
            ),
            const SizedBox(height: 12),
            _fixVersionField(d),
            const SizedBox(height: 16),
            Text(t.issueFieldLabels),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in d.labels)
                  FilterChip(
                    label: Text(l.name),
                    selected: _labels.contains(l.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _labels.add(l.id);
                      } else {
                        _labels.remove(l.id);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(t.issueFieldComponents),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in d.components)
                  FilterChip(
                    label: Text(c.name),
                    selected: _components.contains(c.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _components.add(c.id);
                      } else {
                        _components.remove(c.id);
                      }
                    }),
                  ),
              ],
            ),
          ],
        );
    }
  }

  Widget _peopleFields(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _userField(
          controller: _assigneeCtrl,
          label: t.detailFieldAssignee,
          suffixTooltip: t.assigneeAssignToMe,
        ),
        const SizedBox(height: 12),
        _userField(
          controller: _reporterCtrl,
          label: t.detailFieldReporter,
          suffixTooltip: t.reporterSetMe,
        ),
      ],
    );
  }

  Widget _userField({
    required TextEditingController controller,
    required String label,
    required String suffixTooltip,
  }) {
    final myId = widget.data.profile?.id;
    final t = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: t.editFieldUserPlaceholder,
        suffixIcon: myId == null
            ? null
            : IconButton(
                tooltip: suffixTooltip,
                icon: const Icon(Icons.person_outline),
                onPressed: () {
                  controller.text = myId;
                  controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: controller.text.length),
                  );
                },
              ),
      ),
    );
  }

  Widget _metadataFields(AppLocalizations t, String referenceKey) {
    final d = widget.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metaRow(t.detailFieldType, _kindLabel(t)),
        const SizedBox(height: 8),
        _metaRow(t.editFieldKey, referenceKey, mono: true),
        const SizedBox(height: 8),
        _metaRow(t.detailFieldCreated, formatTimestamp(context, _createdAt(d))),
        const SizedBox(height: 8),
        _metaRow(t.detailFieldUpdated, formatTimestamp(context, _modifiedAt(d))),
      ],
    );
  }

  Widget _metaRow(String label, String value, {bool mono = false}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: mono
                ? theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'JetBrainsMono',
                  )
                : theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }

  /// Fix-version field: when the issue's components link releases, the
  /// available versions (`for-components`) drive a dropdown that sets
  /// `release_version_id`; otherwise a free-text field sets `release_text`.
  Widget _fixVersionField(_EditData d) {
    if (d.fixVersions.isNotEmpty) {
      return DropdownButtonFormField<String?>(
        initialValue: _releaseVersionId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Fix version'),
        items: [
          const DropdownMenuItem<String?>(child: Text('—')),
          for (final v in d.fixVersions)
            DropdownMenuItem<String?>(value: v.id, child: Text(v.label)),
        ],
        onChanged: (v) => setState(() => _releaseVersionId = v),
      );
    }
    return TextField(
      controller: _releaseTextCtrl,
      decoration: const InputDecoration(
        labelText: 'Fix version',
        hintText: 'Free text (no linked releases)',
      ),
    );
  }

  Widget _taxonomyDropdown({
    required String label,
    required String none,
    required List<TaxonomyItem> items,
    required String? current,
    required ValueChanged<String?> onChanged,
    String Function(TaxonomyItem)? labelBuilder,
  }) {
    return DropdownButtonFormField<String?>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(none)),
        ...items.map(
          (s) => DropdownMenuItem<String?>(
            value: s.id,
            child: Text(labelBuilder?.call(s) ?? s.name),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _idDropdown<T>({
    required String label,
    required String none,
    required List<T> items,
    required String Function(T) idOf,
    required String Function(T) labelOf,
    required String? current,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String?>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(none)),
        ...items.map(
          (e) => DropdownMenuItem<String?>(
            value: idOf(e),
            child: Text(labelOf(e), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
