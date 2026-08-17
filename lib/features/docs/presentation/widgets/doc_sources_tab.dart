import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/datetime/relative_time.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/color_swatch_picker.dart';
import 'package:intellipilot/features/catalog/presentation/widgets/emoji_picker.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/features/docs/domain/docs_repository.dart';
import 'package:intellipilot/features/docs/presentation/cubits/doc_key_cubit.dart';
import 'package:intellipilot/features/docs/presentation/cubits/doc_sources_cubit.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/widgets/permission_gate.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Project-settings tab for external documentation sources, plus the caller's
/// own write key.
class DocSourcesTab extends StatelessWidget {
  const DocSourcesTab({required this.projectId, super.key});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<DocSourcesCubit>(
          create: (_) {
            final c = DocSourcesCubit(
              repo: getIt<DocsRepository>(),
              projectId: projectId,
            );
            unawaited(c.load());
            return c;
          },
        ),
        BlocProvider<DocKeyCubit>(
          create: (_) {
            final c = DocKeyCubit(
              repo: getIt<DocsRepository>(),
              projectId: projectId,
            );
            unawaited(c.load());
            return c;
          },
        ),
      ],
      child: _TabView(projectId: projectId),
    );
  }
}

class _TabView extends StatelessWidget {
  const _TabView({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<DocSourcesCubit, DocSourcesState>(
      builder: (context, state) {
        if (state is DocSourcesLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is! DocSourcesLoaded) {
          return Center(child: Text(t.errUnknown));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.docsSourcesTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                PermissionGate(
                  permission: Permission.docSourceCreate,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    onPressed: state.sources.length >= 10
                        ? null
                        : () => unawaited(_add(context)),
                    label: Text(t.docsAddSource),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              state.sources.length >= 10
                  ? t.docsSourceCapReached
                  : t.docsSourcesHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (state.sources.isEmpty)
              _Empty(text: t.docsNoSources)
            else
              for (var i = 0; i < state.sources.length; i++)
                _SourceRow(
                  source: state.sources[i],
                  first: i == 0,
                  last: i == state.sources.length - 1,
                  onMove: (delta) =>
                      unawaited(_move(context, state.sources, i, delta)),
                ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            _MyKeyCard(projectId: projectId),
          ],
        );
      },
    );
  }

  Future<void> _add(BuildContext context) async {
    final cubit = context.read<DocSourcesCubit>();
    final body = await showDocSourceDialog(context, projectId: projectId);
    if (body == null) return;
    final created = await cubit.create(body);
    if (!context.mounted) return;
    if (created == null) {
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.docsAddSourceFailed)));
    }
  }

  /// Move a source one position, giving it a rank midway between its new
  /// neighbours so only the moved row is written.
  Future<void> _move(
    BuildContext context,
    List<DocSource> sources,
    int index,
    int delta,
  ) async {
    final target = index + delta;
    if (target < 0 || target >= sources.length) return;
    final moving = sources[index];
    final before = delta < 0
        ? (target > 0 ? sources[target - 1].order : null)
        : sources[target].order;
    final after = delta < 0
        ? sources[target].order
        : (target + 1 < sources.length ? sources[target + 1].order : null);
    final rank = switch ((before, after)) {
      (null, final a?) => a - 1,
      (final b?, null) => b + 1,
      (final b?, final a?) => (b + a) / 2,
      _ => moving.order,
    };
    await context.read<DocSourcesCubit>().reorder(moving, rank);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.first,
    required this.last,
    required this.onMove,
  });

  final DocSource source;
  final bool first;
  final bool last;
  final void Function(int delta) onMove;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isWeb = source.kind.isWeb;
    final failed = source.cacheStatus == DocCacheStatus.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      // A hidden source stays fully legible but visibly withdrawn, so the
      // switch reads as a state rather than as damage.
      child: Opacity(
        opacity: source.hidden ? 0.55 : 1,
        child: ListTile(
          leading: source.emoji.isNotEmpty
              ? Text(source.emoji, style: const TextStyle(fontSize: 22))
              : Icon(isWeb ? Icons.language : Icons.folder_shared_outlined),
          title: Row(
            children: [
              Flexible(child: Text(source.name)),
              if (source.hidden) ...[
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.visibility_off_outlined, size: 14),
                  label: Text(t.docsHidden),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
              // A web link's read-only-ness is inherent, not a choice, so
              // badging it would be noise.
              if (source.readOnly && !isWeb) ...[
                const SizedBox(width: 8),
                Chip(
                  label: Text(t.docsReadOnly),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isWeb
                    ? source.webUrl
                    : '${source.sshUrl ?? ''} · ${source.branch ?? ''}'
                          '${source.docPath.isEmpty ? '' : ' · /${source.docPath}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              Text(
                // A web link has no cache, so there is no freshness to report
                // about it — say what it is instead.
                isWeb
                    ? t.docsWebSourceKind
                    : failed
                    ? (source.cacheError ?? t.docsSyncFailed)
                    : source.lastSyncedAt == null
                    ? t.docsNeverSynced
                    : t.docsSyncedAgo(relativeTime(t, source.lastSyncedAt)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: !isWeb && failed
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isWeb)
                IconButton(
                  tooltip: t.docsSyncNow,
                  icon: const Icon(Icons.refresh),
                  onPressed: () => unawaited(
                    context.read<DocSourcesCubit>().sync(source.id),
                  ),
                ),
              PermissionGate(
                permission: Permission.docSourceModify,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: source.hidden ? t.docsShow : t.docsHide,
                      icon: Icon(
                        source.hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => unawaited(_toggleHidden(context)),
                    ),
                    IconButton(
                      tooltip: t.docsMoveUp,
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: first ? null : () => onMove(-1),
                    ),
                    IconButton(
                      tooltip: t.docsMoveDown,
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: last ? null : () => onMove(1),
                    ),
                    IconButton(
                      tooltip: t.actionEdit,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => unawaited(_edit(context)),
                    ),
                  ],
                ),
              ),
              PermissionGate(
                permission: Permission.docSourceDelete,
                child: IconButton(
                  tooltip: t.actionDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => unawaited(_delete(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleHidden(BuildContext context) async {
    final cubit = context.read<DocSourcesCubit>();
    final ok = await cubit.update(
      source,
      UpdateDocSourceRequest(hidden: !source.hidden),
    );
    if (!context.mounted || ok) return;
    final t = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.docsSaveFailed)));
  }

  Future<void> _edit(BuildContext context) async {
    final cubit = context.read<DocSourcesCubit>();
    final patch = await showDocSourceEditDialog(context, source: source);
    if (patch == null) return;
    final ok = await cubit.update(source, patch);
    if (!context.mounted || ok) return;
    final t = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.docsSaveFailed)));
  }

  Future<void> _delete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<DocSourcesCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.docsDeleteSourceTitle),
        content: Text(t.docsDeleteSourceBody(source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await cubit.delete(source.id);
  }
}

/// The caller's personal write key. Without one, documents are read-only for
/// them no matter what permissions they hold — the key is what makes a commit
/// attributable to a person.
class _MyKeyCard extends StatelessWidget {
  const _MyKeyCard({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<DocKeyCubit, DocKeyState>(
      builder: (context, state) {
        if (state.loading) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.docsMyKeyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              t.docsMyKeyIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  state.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (state.hasKey)
              _KeyDetails(key0: state.key!, busy: state.busy)
            else
              Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.key),
                    onPressed: state.busy
                        ? null
                        : () => unawaited(
                            context.read<DocKeyCubit>().register(),
                          ),
                    label: Text(t.docsGenerateMyKey),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.upload_file_outlined),
                    onPressed: state.busy
                        ? null
                        : () => unawaited(_import(context)),
                    label: Text(t.docsImportMyKey),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Future<void> _import(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<DocKeyCubit>();
    final controller = TextEditingController();
    final pem = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.docsImportMyKey),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.docsImportHint),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: t.docsPrivateKeyLabel,
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                ),
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
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(t.docsImportMyKey),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pem == null || pem.isEmpty) return;
    await cubit.register(privateKey: pem);
  }
}

class _KeyDetails extends StatelessWidget {
  const _KeyDetails({required this.key0, required this.busy});

  /// Named `key0` because `key` is taken by [Widget].
  final DocUserKey key0;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              key0.isImported ? t.docsKeyImported : t.docsKeyGenerated,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            SelectableText(
              key0.publicKey,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            const SizedBox(height: 6),
            Text(
              key0.fingerprint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.docsMyKeyRegisterHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => unawaited(_copy(context)),
                  label: Text(t.docsCopyPublicKey),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  onPressed: busy
                      ? null
                      : () => unawaited(context.read<DocKeyCubit>().remove()),
                  label: Text(t.docsRemoveMyKey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final t = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: key0.publicKey));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.docsCopied)));
  }
}

// --- dialogs ---------------------------------------------------------------

/// Add a source. Returns the request, or null if cancelled.
Future<CreateDocSourceRequest?> showDocSourceDialog(
  BuildContext context, {
  required String projectId,
}) => showDialog<CreateDocSourceRequest>(
  context: context,
  builder: (_) => _AddSourceDialog(projectId: projectId),
);

/// Edit a source. Returns only the changed fields, or null if cancelled.
Future<UpdateDocSourceRequest?> showDocSourceEditDialog(
  BuildContext context, {
  required DocSource source,
}) => showDialog<UpdateDocSourceRequest>(
  context: context,
  builder: (_) => _EditSourceDialog(source: source),
);

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog({required this.projectId});
  final String projectId;

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _name = TextEditingController();
  final _sshUrl = TextEditingController();
  final _webUrl = TextEditingController();
  final _branch = TextEditingController(text: 'main');
  final _path = TextEditingController();
  final _keyName = TextEditingController();
  DocSourceKind _kind = DocSourceKind.git;
  bool _readOnly = false;
  bool _generateKey = true;
  String? _existingKeyId;
  String _color = '';
  String _emoji = '';
  List<SshKey> _keys = const [];
  bool _webTouched = false;

  @override
  void initState() {
    super.initState();
    _sshUrl.addListener(_deriveWebUrl);
    unawaited(_loadKeys());
  }

  @override
  void dispose() {
    _sshUrl.removeListener(_deriveWebUrl);
    for (final c in [_name, _sshUrl, _webUrl, _branch, _path, _keyName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadKeys() async {
    final res = await getIt<CatalogRepository>().listSshKeys(widget.projectId);
    if (!mounted) return;
    setState(() => _keys = res.valueOrNull ?? const []);
  }

  /// Pre-fill the web URL from the SSH URL for the common hosts. The field
  /// stays required and editable — this only saves typing, and stops guessing
  /// the moment the user edits it.
  void _deriveWebUrl() {
    if (_webTouched) return;
    final derived = deriveWebUrl(_sshUrl.text);
    if (derived != null && derived != _webUrl.text) {
      _webUrl.text = derived;
    }
  }

  bool get _valid {
    if (_name.text.trim().isEmpty) return false;
    if (!_webUrl.text.trim().startsWith('http')) return false;
    // A web link needs nothing else: a title and an address are the whole
    // configuration.
    if (_kind == DocSourceKind.web) return true;
    return _sshUrl.text.trim().isNotEmpty &&
        _branch.text.trim().isNotEmpty &&
        (_generateKey
            ? _keyName.text.trim().isNotEmpty
            : _existingKeyId != null);
  }

  CreateDocSourceRequest _build() => _kind == DocSourceKind.web
      ? CreateDocSourceRequest.web(
          name: _name.text.trim(),
          webUrl: _webUrl.text.trim(),
          color: _color,
          emoji: _emoji,
        )
      : CreateDocSourceRequest(
          name: _name.text.trim(),
          sshUrl: _sshUrl.text.trim(),
          webUrl: _webUrl.text.trim(),
          branch: _branch.text.trim(),
          docPath: _path.text.trim(),
          sshKeyId: _generateKey ? null : _existingKeyId,
          newKeyName: _generateKey ? _keyName.text.trim() : null,
          readOnly: _readOnly,
          color: _color,
          emoji: _emoji,
        );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isWeb = _kind == DocSourceKind.web;
    return AlertDialog(
      title: Text(t.docsAddSource),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.docsSourceKind,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              SegmentedButton<DocSourceKind>(
                segments: [
                  ButtonSegment(
                    value: DocSourceKind.git,
                    icon: const Icon(Icons.folder_shared_outlined),
                    label: Text(t.docsGitSourceKind),
                  ),
                  ButtonSegment(
                    value: DocSourceKind.web,
                    icon: const Icon(Icons.language),
                    label: Text(t.docsWebSourceKind),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              const SizedBox(height: 4),
              Text(
                isWeb ? t.docsWebSourceKindHint : t.docsGitSourceKindHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              _field(_name, t.docsTitleLabel, helper: t.docsTitleHint),
              if (isWeb) ...[
                _field(
                  _webUrl,
                  t.docsPageUrl,
                  hint: 'https://example.com/handbook',
                  helper: t.docsPageUrlHint,
                  onChanged: (_) => _webTouched = true,
                ),
              ] else ...[
                _field(
                  _sshUrl,
                  t.docsSshUrl,
                  hint: 'git@github.com:acme/docs.git',
                ),
                _field(
                  _webUrl,
                  t.docsWebUrl,
                  hint: 'https://github.com/acme/docs',
                  helper: t.docsWebUrlHint,
                  onChanged: (_) => _webTouched = true,
                ),
                _field(_branch, t.docsBranch),
                _field(_path, t.docsFolder, helper: t.docsFolderHint),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _readOnly,
                  onChanged: (v) => setState(() => _readOnly = v),
                  title: Text(t.docsReadOnly),
                  subtitle: Text(t.docsReadOnlyHelp),
                ),
              ],
              if (!isWeb) ...[
                const Divider(),
                Text(
                  t.docsDeployKey,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text(t.docsGenerateDeployKey),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text(t.docsUseExistingKey),
                      // Nothing to pick from until the project has a key.
                      enabled: _keys.isNotEmpty,
                    ),
                  ],
                  selected: {_generateKey},
                  onSelectionChanged: (v) =>
                      setState(() => _generateKey = v.first),
                ),
                if (_generateKey)
                  _field(_keyName, t.docsDeployKeyName)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: DropdownButtonFormField<String>(
                      initialValue: _existingKeyId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t.docsDeployKey,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final k in _keys)
                          DropdownMenuItem(value: k.id, child: Text(k.name)),
                      ],
                      onChanged: (v) => setState(() => _existingKeyId = v),
                    ),
                  ),
              ],
              const Divider(),
              Text(
                t.docsAppearance,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              ColorSwatchPicker(
                selectedHex: _color,
                onChanged: (v) => setState(() => _color = v),
              ),
              const SizedBox(height: 8),
              EmojiPicker(
                selected: _emoji,
                onChanged: (v) => setState(() => _emoji = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: _valid ? () => Navigator.of(context).pop(_build()) : null,
          child: Text(t.actionAdd),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    String? helper,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) {
        onChanged?.call(v);
        setState(() {});
      },
    ),
  );
}

class _EditSourceDialog extends StatefulWidget {
  const _EditSourceDialog({required this.source});
  final DocSource source;

  @override
  State<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends State<_EditSourceDialog> {
  late final _name = TextEditingController(text: widget.source.name);
  late final _webUrl = TextEditingController(text: widget.source.webUrl);
  late final _branch = TextEditingController(text: widget.source.branch ?? '');
  late final _path = TextEditingController(text: widget.source.docPath);
  late bool _readOnly = widget.source.readOnly;
  late bool _hidden = widget.source.hidden;
  late String _color = widget.source.color;
  late String _emoji = widget.source.emoji;

  @override
  void dispose() {
    for (final c in [_name, _webUrl, _branch, _path]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only send what actually changed, so a PATCH never overwrites a field the
  /// form did not touch and the version guard stays meaningful.
  UpdateDocSourceRequest _diff() {
    final s = widget.source;
    return UpdateDocSourceRequest(
      name: _name.text.trim() == s.name ? null : _name.text.trim(),
      webUrl: _webUrl.text.trim() == s.webUrl ? null : _webUrl.text.trim(),
      branch: _branch.text.trim() == (s.branch ?? '')
          ? null
          : _branch.text.trim(),
      docPath: _path.text.trim() == s.docPath ? null : _path.text.trim(),
      readOnly: _readOnly == s.readOnly ? null : _readOnly,
      hidden: _hidden == s.hidden ? null : _hidden,
      color: _color == s.color ? null : _color,
      emoji: _emoji == s.emoji ? null : _emoji,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isWeb = widget.source.kind.isWeb;
    return AlertDialog(
      title: Text(t.docsEditSource),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_name, t.docsTitleLabel, helper: t.docsTitleHint),
              if (isWeb)
                _field(_webUrl, t.docsPageUrl, helper: t.docsPageUrlHint)
              else ...[
                // The SSH URL is deliberately not editable: repointing a
                // source at a different repository is adding a different
                // source.
                _field(_webUrl, t.docsWebUrl),
                _field(_branch, t.docsBranch, helper: t.docsBranchChangeHint),
                _field(_path, t.docsFolder, helper: t.docsFolderHint),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _readOnly,
                  onChanged: (v) => setState(() => _readOnly = v),
                  title: Text(t.docsReadOnly),
                  subtitle: Text(t.docsReadOnlyHelp),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _hidden,
                onChanged: (v) => setState(() => _hidden = v),
                title: Text(t.docsHidden),
                subtitle: Text(t.docsHiddenHelp),
              ),
              const Divider(),
              ColorSwatchPicker(
                selectedHex: _color,
                onChanged: (v) => setState(() => _color = v),
              ),
              const SizedBox(height: 8),
              EmojiPicker(
                selected: _emoji,
                onChanged: (v) => setState(() => _emoji = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_diff()),
          child: Text(t.actionSave),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {String? helper}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
      );
}

/// Best-effort browse URL for the common hosts, used to pre-fill the required
/// web address field. Returns null when the shape is unfamiliar, leaving the
/// user to type it.
String? deriveWebUrl(String sshUrl) {
  final url = sshUrl.trim();
  if (url.isEmpty) return null;

  String? host;
  String? path;
  if (url.startsWith('ssh://')) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    host = uri.host;
    path = uri.path;
  } else {
    // scp-like: git@host:org/repo.git
    final at = url.indexOf('@');
    final colon = url.indexOf(':', at + 1);
    if (at == -1 || colon == -1) return null;
    host = url.substring(at + 1, colon);
    path = url.substring(colon + 1);
  }

  final cleaned = path
      .replaceAll(RegExp('^/+'), '')
      .replaceAll(RegExp(r'\.git$'), '');
  if (cleaned.isEmpty || host.isEmpty) return null;
  return 'https://$host/$cleaned';
}
