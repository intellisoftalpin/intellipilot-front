import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/features/backlog/presentation/cubits/issues_cubit.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/issues_io/data/dtos/issues_io_dtos.dart';
import 'package:intellipilot/features/issues_io/domain/issues_io_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Sentinel dropdown values that aren't a taxonomy id.
const _create = '__create__';
const _skip = '__skip__';

/// Opens the import wizard (pick file → map values → commit). Returns true
/// when issues were imported, so the caller can reload the list.
Future<bool> showIssueImportDialog(
  BuildContext context, {
  required String projectId,
  required IssuesLoaded state,
}) async {
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImportDialog(projectId: projectId, state: state),
  );
  return done ?? false;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.projectId, required this.state});
  final String projectId;
  final IssuesLoaded state;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _repo = getIt<IssuesIoRepository>();

  bool _busy = false;
  String? _error;

  // Picked file.
  String? _filename;
  late Uint8List _bytes;

  // Preview + the user's per-value selections (value -> id | sentinel).
  ImportPreview? _preview;
  final Map<String, String> _types = {};
  final Map<String, String> _statuses = {};
  final Map<String, String> _priorities = {};
  final Map<String, String> _components = {};

  // Final summary.
  ImportResult? _result;

  Future<void> _pick() async {
    final picker = getIt<FilePicker>();
    final picked = await picker.pickSingleFile();
    if (picked == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _filename = picked.name;
      _bytes = picked.bytes;
    });
    final res = await _repo.preview(
      widget.projectId,
      filename: picked.name,
      bytes: picked.bytes,
    );
    if (!mounted) return;
    res.when(
      ok: (p) => setState(() {
        _busy = false;
        _preview = p;
        _seedDefaults(p);
      }),
      err: (_) => setState(() {
        _busy = false;
        _error = AppLocalizations.of(context).importParseFailed;
      }),
    );
  }

  /// Default each value to its auto-match, else "create" (categoricals) or
  /// "skip" (components, which can only map to existing).
  void _seedDefaults(ImportPreview p) {
    for (final v in p.types) {
      _types[v.value] = v.matchedId ?? _create;
    }
    for (final v in p.statuses) {
      _statuses[v.value] = v.matchedId ?? _create;
    }
    for (final v in p.priorities) {
      _priorities[v.value] = v.matchedId ?? _create;
    }
    for (final v in p.components) {
      _components[v.value] = v.matchedId ?? _skip;
    }
  }

  ImportMapping _buildMapping() {
    List<ValueChoice> choices(Map<String, String> sel) => sel.entries.map((e) {
      if (e.value == _create) {
        return ValueChoice(value: e.key, create: true);
      }
      if (e.value == _skip) {
        return ValueChoice(value: e.key);
      }
      return ValueChoice(value: e.key, target: e.value);
    }).toList();
    return ImportMapping(
      types: choices(_types),
      statuses: choices(_statuses),
      priorities: choices(_priorities),
      components: choices(_components),
    );
  }

  Future<void> _commit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await _repo.commit(
      widget.projectId,
      filename: _filename ?? 'import.csv',
      bytes: _bytes,
      mapping: _buildMapping(),
    );
    if (!mounted) return;
    res.when(
      ok: (r) => setState(() {
        _busy = false;
        _result = r;
      }),
      err: (_) => setState(() {
        _busy = false;
        _error = AppLocalizations.of(context).importFailed;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.importTitle),
      content: SizedBox(
        width: 460,
        child: _busy
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(child: _body(t)),
      ),
      actions: _actions(t),
    );
  }

  Widget _body(AppLocalizations t) {
    if (_result != null) return _summary(t, _result!);
    if (_preview == null) return _picker(t);
    return _mapping(t, _preview!);
  }

  Widget _picker(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t.importPickHint),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file),
          label: Text(_filename ?? t.importChooseFile),
          onPressed: _pick,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  Widget _mapping(AppLocalizations t, ImportPreview p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t.importIssueCount(p.issueCount)),
        if (p.types.isNotEmpty)
          _section(t.importTypes, p.types, _types, widget.state.types, true),
        if (p.statuses.isNotEmpty)
          _section(
            t.importStatuses,
            p.statuses,
            _statuses,
            widget.state.statuses,
            true,
          ),
        if (p.priorities.isNotEmpty)
          _section(
            t.importPriorities,
            p.priorities,
            _priorities,
            widget.state.priorities,
            true,
          ),
        if (p.components.isNotEmpty)
          _componentSection(t, p.components),
        if (p.unmatchedUsers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(t.importUnmatchedUsers, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(p.unmatchedUsers.join(', '), style: Theme.of(context).textTheme.bodySmall),
          Text(t.importUnmatchedUsersHint, style: Theme.of(context).textTheme.bodySmall),
        ],
        for (final w in p.warnings) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(child: Text(w, style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  /// One mapping section for a categorical dimension. [allowCreate] adds the
  /// "create new" option; existing [items] become the other dropdown entries.
  Widget _section(
    String title,
    List<ValueMatch> values,
    Map<String, String> selection,
    List<TaxonomyItem> items,
    bool allowCreate,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final v in values)
            _row(
              v.value,
              selection[v.value] ?? _create,
              [
                if (allowCreate)
                  DropdownMenuItem(value: _create, child: Text('+ ${v.value}')),
                ...items.map(
                  (it) => DropdownMenuItem(value: it.id, child: Text(it.name)),
                ),
              ],
              (sel) => setState(() => selection[v.value] = sel),
            ),
        ],
      ),
    );
  }

  Widget _componentSection(AppLocalizations t, List<ValueMatch> values) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.importComponents, style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final v in values)
            _row(
              v.value,
              _components[v.value] ?? _skip,
              [
                DropdownMenuItem(value: _skip, child: Text(t.importSkip)),
                ...widget.state.components.map(
                  (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                ),
              ],
              (sel) => setState(() => _components[v.value] = sel),
            ),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value,
    List<DropdownMenuItem<String>> items,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: value,
              items: items,
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(AppLocalizations t, ImportResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 36),
        const SizedBox(height: 12),
        Text(t.importDoneIssues(r.createdIssues)),
        if (r.createdEpics > 0) Text(t.importDoneEpics(r.createdEpics)),
        if (r.createdComments > 0) Text(t.importDoneComments(r.createdComments)),
        if (r.createdTaxonomy > 0) Text(t.importDoneTaxonomy(r.createdTaxonomy)),
        for (final s in r.skipped) ...[
          const SizedBox(height: 6),
          Text('• $s', style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  List<Widget> _actions(AppLocalizations t) {
    if (_result != null) {
      return [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.actionDone),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: Text(t.actionCancel),
      ),
      FilledButton(
        onPressed: (_preview == null || _busy) ? null : _commit,
        child: Text(t.importAction),
      ),
    ];
  }
}
