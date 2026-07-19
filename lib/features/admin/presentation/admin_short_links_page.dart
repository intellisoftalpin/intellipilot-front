import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Superadmin view of the short-link rename history: every remembered
/// renamed-away project prefix and board key. Entries can be pruned one by
/// one or in bulk via the selection — after pruning, the matching old short
/// links stop resolving (UUID links keep working regardless).
class AdminShortLinksPage extends StatefulWidget {
  const AdminShortLinksPage({super.key});

  @override
  State<AdminShortLinksPage> createState() => _AdminShortLinksPageState();
}

class _AdminShortLinksPageState extends State<AdminShortLinksPage> {
  ShortLinkHistory? _history;
  bool _failed = false;
  bool _busy = false;
  final Set<String> _selectedProjects = {};
  final Set<String> _selectedBoards = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _history = null;
      _selectedProjects.clear();
      _selectedBoards.clear();
    });
    final res = await getIt<AdminRepository>().shortLinkHistory();
    if (!mounted) return;
    res.when(
      ok: (h) => setState(() => _history = h),
      err: (_) => setState(() => _failed = true),
    );
  }

  Future<void> _delete({
    required List<String> projectIds,
    required List<String> boardIds,
  }) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final count = projectIds.length + boardIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.adminShortLinksDeleteTitle),
        content: Text(t.adminShortLinksDeleteConfirm(count)),
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
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await getIt<AdminRepository>().deleteShortLinkHistory(
      projectIds: projectIds,
      boardIds: boardIds,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.isErr) {
      messenger.showSnackBar(SnackBar(content: Text(t.errUnknown)));
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final selected = _selectedProjects.length + _selectedBoards.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.adminShortLinksTitle),
        actions: [
          if (selected > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(t.adminShortLinksDeleteSelected(selected)),
                onPressed: _busy
                    ? null
                    : () => _delete(
                        projectIds: _selectedProjects.toList(),
                        boardIds: _selectedBoards.toList(),
                      ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.actionRetry,
            onPressed: _busy ? null : _load,
          ),
        ],
      ),
      body: _body(t),
    );
  }

  Widget _body(AppLocalizations t) {
    final theme = Theme.of(context);
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.errUnknown),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: Text(t.actionRetry)),
          ],
        ),
      );
    }
    final history = _history;
    if (history == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (history.isEmpty) {
      return Center(
        child: Text(
          t.adminShortLinksEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          t.adminShortLinksHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (history.projects.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            t.adminShortLinksProjects,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final e in history.projects)
            _row(
              id: e.id,
              token: e.prefix,
              subtitle: t.adminShortLinksProjectRow(e.projectName),
              replacedAt: e.replacedAt,
              selectedSet: _selectedProjects,
              onDelete: () => _delete(projectIds: [e.id], boardIds: const []),
            ),
        ],
        if (history.boards.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(t.adminShortLinksBoards, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final e in history.boards)
            _row(
              id: e.id,
              token: e.boardKey,
              subtitle: t.adminShortLinksBoardRow(e.boardName, e.projectName),
              replacedAt: e.replacedAt,
              selectedSet: _selectedBoards,
              onDelete: () => _delete(projectIds: const [], boardIds: [e.id]),
            ),
        ],
      ],
    );
  }

  Widget _row({
    required String id,
    required String token,
    required String subtitle,
    required DateTime replacedAt,
    required Set<String> selectedSet,
    required VoidCallback onDelete,
  }) {
    final theme = Theme.of(context);
    final date = replacedAt.toLocal().toIso8601String().substring(0, 10);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Checkbox(
          value: selectedSet.contains(id),
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  if (v ?? false) {
                    selectedSet.add(id);
                  } else {
                    selectedSet.remove(id);
                  }
                }),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(token, style: AppTheme.mono(context, size: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(date),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: _busy ? null : onDelete,
        ),
      ),
    );
  }
}
