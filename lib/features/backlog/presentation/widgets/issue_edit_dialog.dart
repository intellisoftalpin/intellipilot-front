import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Minimal issue creation dialog — asks only for a subject and an issue type.
/// Everything else (status, priority, assignee, dates, labels…) is filled in
/// on the issue sidebar, which the caller opens right after creating. The
/// backend auto-assigns the default "new" status unless the caller presets
/// one (the board's per-column "+"). Mirrors the epic create flow
/// ([showEpicEditDialog]).
Future<CreateIssueRequest?> showIssueEditDialog(
  BuildContext context, {
  required List<TaxonomyItem> types,
}) async {
  final result = await showDialog<IssueCreateResult>(
    context: context,
    builder: (_) => IssueCreateDialog(types: types),
  );
  return result?.request;
}

/// The same dialog with a project picker in front, for creating an issue from
/// anywhere (the top-bar Create button and the `c` shortcut).
///
/// [initialProjectId] is preselected when it is among the listed projects.
/// Each picked project's issue types and the caller's `issue.create` right
/// are fetched through [loadTarget] on first pick and remembered for the
/// dialog's lifetime, so flipping between projects costs nothing twice.
Future<IssueCreateResult?> showIssueCreateWithProjectDialog(
  BuildContext context, {
  required Future<List<Project>?> Function() loadProjects,
  required IssueCreateTargetLoader loadTarget,
  String? initialProjectId,
}) {
  return showDialog<IssueCreateResult>(
    context: context,
    builder: (_) => IssueCreateDialog.withProjectPicker(
      loadProjects: loadProjects,
      loadTarget: loadTarget,
      initialProjectId: initialProjectId,
    ),
  );
}

/// What the create dialog needs to know about a picked project.
class IssueCreateTarget {
  const IssueCreateTarget({required this.types, required this.canCreate});

  final List<TaxonomyItem> types;

  /// The caller holds `issue.create` there.
  final bool canCreate;
}

/// Fetches an [IssueCreateTarget]; null when it could not be loaded.
typedef IssueCreateTargetLoader =
    Future<IssueCreateTarget?> Function(String projectId);

/// The dialog's answer: the request, and — in project-picker mode — the
/// project to create it in (null in fixed mode, where the caller knows it).
class IssueCreateResult {
  const IssueCreateResult({required this.request, this.projectId});
  final CreateIssueRequest request;
  final String? projectId;
}

/// Subject + type prompt shared by the Issues page, the board's per-column
/// "+" and the global Create button.
///
/// Owns its text controller so disposal happens with the dialog route, never
/// while the closing animation still has the field mounted.
class IssueCreateDialog extends StatefulWidget {
  /// Fixed project: the caller already has the project's [types].
  const IssueCreateDialog({required List<TaxonomyItem> this.types, super.key})
    : loadProjects = null,
      loadTarget = null,
      initialProjectId = null;

  /// Project picker first; types load per picked project.
  const IssueCreateDialog.withProjectPicker({
    required Future<List<Project>?> Function() this.loadProjects,
    required IssueCreateTargetLoader this.loadTarget,
    this.initialProjectId,
    super.key,
  }) : types = null;

  final List<TaxonomyItem>? types;
  final Future<List<Project>?> Function()? loadProjects;
  final IssueCreateTargetLoader? loadTarget;
  final String? initialProjectId;

  bool get _picker => loadTarget != null;

  @override
  State<IssueCreateDialog> createState() => _IssueCreateDialogState();
}

class _IssueCreateDialogState extends State<IssueCreateDialog> {
  final _subject = TextEditingController();
  String? _typeId;

  // Project-picker mode only.
  List<Project>? _projects;
  bool _projectsFailed = false;
  String? _projectId;
  final Map<String, IssueCreateTarget> _targets = {};
  bool _targetLoading = false;
  bool _targetFailed = false;

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so the Create button tracks the subject.
    _subject.addListener(_onSubjectChanged);
    if (widget._picker) unawaited(_loadProjects());
  }

  @override
  void dispose() {
    _subject
      ..removeListener(_onSubjectChanged)
      ..dispose();
    super.dispose();
  }

  void _onSubjectChanged() => setState(() {});

  Future<void> _loadProjects() async {
    final projects = await widget.loadProjects!();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _projectsFailed = projects == null;
    });
    if (projects == null || projects.isEmpty) return;
    final initial = widget.initialProjectId;
    final preselect = projects.any((p) => p.id == initial)
        ? initial
        : (projects.length == 1 ? projects.single.id : null);
    if (preselect != null) await _pickProject(preselect);
  }

  Future<void> _pickProject(String id) async {
    setState(() {
      _projectId = id;
      // Types are per project — a type picked for the previous one is
      // meaningless here.
      _typeId = null;
      _targetFailed = false;
      _targetLoading = !_targets.containsKey(id);
    });
    if (_targets.containsKey(id)) return;
    final target = await widget.loadTarget!(id);
    // A slower answer for a project the user already switched away from
    // must not land on the current one.
    if (!mounted || _projectId != id) return;
    setState(() {
      _targetLoading = false;
      if (target == null) {
        _targetFailed = true;
      } else {
        _targets[id] = target;
      }
    });
  }

  IssueCreateTarget? get _target =>
      _projectId == null ? null : _targets[_projectId];

  List<TaxonomyItem> get _types =>
      widget._picker ? (_target?.types ?? const []) : widget.types!;

  bool get _canSubmit {
    if (_subject.text.trim().isEmpty) return false;
    if (!widget._picker) return true;
    final target = _target;
    return target != null && target.canCreate;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(
      IssueCreateResult(
        projectId: _projectId,
        request: CreateIssueRequest(
          subject: _subject.text.trim(),
          typeId: _typeId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.actionNewIssue),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget._picker ? _pickerBody(t) : _fields(t),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('issue-create-submit'),
          onPressed: _canSubmit ? _submit : null,
          child: Text(t.actionCreate),
        ),
      ],
    );
  }

  List<Widget> _pickerBody(AppLocalizations t) {
    final projects = _projects;
    if (projects == null) {
      if (_projectsFailed) return [Text(t.ttActionFailed)];
      return const [LinearProgressIndicator()];
    }
    if (projects.isEmpty) return [Text(t.issueCreateNoProjects)];
    final target = _target;
    return [
      DropdownButtonFormField<String>(
        key: const ValueKey('issue-create-project'),
        initialValue: _projectId,
        isExpanded: true,
        decoration: InputDecoration(labelText: t.issueCreateFieldProject),
        items: [
          for (final p in projects)
            DropdownMenuItem<String>(
              value: p.id,
              child: Text(
                p.issuePrefix.isEmpty ? p.name : '${p.name} · ${p.issuePrefix}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) {
          if (id != null && id != _projectId) unawaited(_pickProject(id));
        },
      ),
      const SizedBox(height: 12),
      ..._fields(t),
      if (_targetLoading) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      if (_targetFailed)
        _Notice(
          text: t.issueCreateLoadFailed,
          action: TextButton(
            onPressed: () => unawaited(_pickProject(_projectId!)),
            child: Text(t.actionRetry),
          ),
        ),
      if (target != null && !target.canCreate)
        _Notice(text: t.issueCreateNoPermission),
    ];
  }

  List<Widget> _fields(AppLocalizations t) {
    final enabled = !widget._picker || _target != null;
    return [
      TextField(
        key: const ValueKey('issue-create-subject'),
        controller: _subject,
        autofocus: true,
        decoration: InputDecoration(labelText: t.backlogFieldSubject),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String?>(
        // Keyed by project: the field keeps its own selection, which must
        // reset when the option list is swapped for another project's.
        key: ValueKey('issue-create-type-$_projectId'),
        initialValue: _typeId,
        isExpanded: true,
        decoration: InputDecoration(labelText: t.issueFieldType),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('—')),
          for (final item in _types)
            DropdownMenuItem<String?>(
              value: item.id,
              child: Text(
                item.emoji.isEmpty ? item.name : '${item.emoji} ${item.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: enabled ? (v) => setState(() => _typeId = v) : null,
      ),
    ];
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
