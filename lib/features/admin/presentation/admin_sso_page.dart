import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/admin/data/dtos/sso_admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_sso_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Identity providers for single sign-on.
///
/// Several may be configured and enabled at once; the login screen renders a
/// button per enabled one. A new provider starts disabled on purpose — the
/// intended order is configure, press **Test**, then enable, so a mistyped
/// issuer is discovered by the administrator rather than by a user who cannot
/// sign in.
class AdminSsoPage extends StatelessWidget {
  const AdminSsoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocProvider<AdminSsoCubit>(
      create: (_) {
        final c = AdminSsoCubit(getIt<AdminRepository>());
        unawaited(c.load());
        return c;
      },
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(t.adminSsoTitle)),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => unawaited(_edit(context, null)),
            icon: const Icon(Icons.add),
            label: Text(t.adminSsoAddProvider),
          ),
          body: BlocBuilder<AdminSsoCubit, AdminSsoState>(
            builder: (context, state) => switch (state) {
              AdminSsoLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
              AdminSsoFailed(:final failure) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(failure.serverMessage ?? t.errUnknown),
                ),
              ),
              AdminSsoLoaded(:final providers) =>
                providers.isEmpty
                    ? _EmptyState(text: t.adminSsoEmpty)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              t.adminSsoIntro,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          for (final p in providers)
                            _ProviderCard(
                              provider: p,
                              onEdit: () => unawaited(_edit(context, p)),
                              onTest: () => unawaited(_test(context, p)),
                              onDelete: () => unawaited(_delete(context, p)),
                            ),
                        ],
                      ),
            },
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, OidcProviderConfig? existing) async {
    final cubit = context.read<AdminSsoCubit>();
    final t = AppLocalizations.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _ProviderEditor(existing: existing),
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.adminSsoSaved)));
    }
  }

  Future<void> _test(BuildContext context, OidcProviderConfig p) async {
    final cubit = context.read<AdminSsoCubit>();
    final t = AppLocalizations.of(context);
    final result = await cubit.test(p.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.adminSsoTestTitle),
        content: result.when(
          ok: (r) => _TestReport(result: r),
          err: (f) => Text(f.serverMessage ?? t.errUnknown),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.actionClose),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, OidcProviderConfig p) async {
    final cubit = context.read<AdminSsoCubit>();
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.adminSsoDeleteTitle),
        // Deleting cascades to every linked identity, so anyone who signs in
        // only this way loses that route. Worth spelling out.
        content: Text(t.adminSsoDeleteConfirm(p.displayName)),
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
    if (confirmed != true) return;
    final failure = await cubit.delete(p.id);
    if (!context.mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.serverMessage ?? t.errUnknown)),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.onEdit,
    required this.onTest,
    required this.onDelete,
  });

  final OidcProviderConfig provider;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              provider.enabled ? Icons.verified_user : Icons.shield_outlined,
              color: provider.enabled ? theme.colorScheme.primary : null,
            ),
            title: Text(provider.displayName),
            subtitle: Text(provider.issuerUrl),
            trailing: Chip(
              label: Text(
                provider.enabled ? t.adminSsoEnabled : t.adminSsoDisabled,
              ),
            ),
            onTap: onEdit,
          ),
          // The two URLs an operator must register at the provider. Shown on
          // the card, not buried in the editor, because they are the thing
          // most often needed while looking at the other system.
          _CopyRow(label: t.adminSsoRedirectUri, value: provider.redirectUri),
          _CopyRow(
            label: t.adminSsoBackchannelUri,
            value: provider.backchannelLogoutUri,
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onTest, child: Text(t.adminSsoTest)),
              TextButton(onPressed: onEdit, child: Text(t.actionEdit)),
              TextButton(onPressed: onDelete, child: Text(t.actionDelete)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                SelectableText(value, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).actionCopy,
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: () =>
                unawaited(Clipboard.setData(ClipboardData(text: value))),
          ),
        ],
      ),
    );
  }
}

class _TestReport extends StatelessWidget {
  const _TestReport({required this.result});
  final OidcTestResult result;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.ok ? Icons.check_circle_outline : Icons.error_outline,
                color: result.ok
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(result.message)),
            ],
          ),
          if (result.issuer != null) ...[
            const SizedBox(height: 12),
            _ReportLine(label: t.adminSsoFieldIssuer, value: result.issuer!),
          ],
          if (result.authorizationEndpoint != null)
            _ReportLine(
              label: t.adminSsoAuthorizationEndpoint,
              value: result.authorizationEndpoint!,
            ),
          if (result.tokenEndpoint != null)
            _ReportLine(
              label: t.adminSsoTokenEndpoint,
              value: result.tokenEndpoint!,
            ),
          _ReportLine(
            label: t.adminSsoDeviceFlow,
            value: result.supportsDeviceFlow
                ? t.adminSsoDeviceFlowYes
                : t.adminSsoDeviceFlowNo,
          ),
          _ReportLine(
            label: t.adminSsoSigningKeys,
            value: '${result.jwksKeys}',
          ),
        ],
      ),
    );
  }
}

class _ReportLine extends StatelessWidget {
  const _ReportLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          SelectableText(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Create/edit form.
class _ProviderEditor extends StatefulWidget {
  const _ProviderEditor({required this.existing});
  final OidcProviderConfig? existing;

  @override
  State<_ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<_ProviderEditor> {
  late UpsertOidcProviderRequest _draft;
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.existing?.toUpdate() ?? UpsertOidcProviderRequest.blank();
  }

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    // A blank secret means "keep the stored one", which is the whole reason
    // the field starts empty when editing an existing provider.
    final req = _draft.copyWith(
      clientSecret: _secret.text.trim().isEmpty ? null : _secret.text.trim(),
    );
    final failure = await context.read<AdminSsoCubit>().save(
      widget.existing?.id,
      req,
    );
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = failure.serverMessage ?? AppLocalizations.of(context).errUnknown;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null ? t.adminSsoAddProvider : t.adminSsoEditTitle,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              _text(
                label: t.adminSsoFieldDisplayName,
                value: _draft.displayName,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(displayName: v)),
              ),
              _text(
                label: t.adminSsoFieldSlug,
                helper: t.adminSsoFieldSlugHelp,
                value: _draft.slug,
                enabled: widget.existing == null,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(slug: v.toLowerCase()),
                ),
              ),
              _text(
                label: t.adminSsoFieldIssuer,
                helper: t.adminSsoFieldIssuerHelp,
                value: _draft.issuerUrl,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(issuerUrl: v)),
              ),
              _text(
                label: t.adminSsoFieldClientId,
                value: _draft.clientId,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(clientId: v)),
              ),
              TextField(
                controller: _secret,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.adminSsoFieldClientSecret,
                  helperText: widget.existing?.clientSecretSet ?? false
                      ? t.adminSsoFieldClientSecretStored
                      : t.adminSsoFieldClientSecretHelp,
                ),
              ),
              const SizedBox(height: 8),
              _text(
                label: t.adminSsoFieldScopes,
                value: _draft.scopes,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(scopes: v)),
              ),
              _text(
                label: t.adminSsoFieldSuperadminGroup,
                helper: t.adminSsoFieldSuperadminGroupHelp,
                value: _draft.superadminGroup,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(superadminGroup: v),
                ),
              ),
              const Divider(height: 32),
              Text(
                t.adminSsoClaimsSection,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _text(
                label: t.adminSsoFieldClaimEmail,
                value: _draft.claimEmail,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(claimEmail: v)),
              ),
              _text(
                label: t.adminSsoFieldClaimUsername,
                value: _draft.claimUsername,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(claimUsername: v)),
              ),
              _text(
                label: t.adminSsoFieldClaimDisplayName,
                value: _draft.claimDisplayName,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(claimDisplayName: v),
                ),
              ),
              _text(
                label: t.adminSsoFieldClaimGroups,
                value: _draft.claimGroups,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(claimGroups: v)),
              ),
              const Divider(height: 32),
              SwitchListTile(
                title: Text(t.adminSsoEnabledLabel),
                subtitle: Text(t.adminSsoEnabledHelp),
                value: _draft.enabled,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(enabled: v)),
              ),
              SwitchListTile(
                title: Text(t.adminSsoJitLabel),
                subtitle: Text(t.adminSsoJitHelp),
                value: _draft.allowJitProvisioning,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(allowJitProvisioning: v),
                ),
              ),
              SwitchListTile(
                title: Text(t.adminSsoVerifiedEmailLabel),
                subtitle: Text(t.adminSsoVerifiedEmailHelp),
                value: _draft.requireEmailVerified,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(requireEmailVerified: v),
                ),
              ),
              SwitchListTile(
                title: Text(t.adminSsoDeviceFlowLabel),
                subtitle: Text(t.adminSsoDeviceFlowHelp),
                value: _draft.deviceFlowEnabled,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(deviceFlowEnabled: v),
                ),
              ),
              SwitchListTile(
                title: Text(t.adminSsoSkipTlsLabel),
                subtitle: Text(t.adminSsoSkipTlsHelp),
                value: _draft.skipTlsVerify,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(skipTlsVerify: v)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(t.actionSave),
        ),
      ],
    );
  }

  Widget _text({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? helper,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextFormField(
      initialValue: value,
      enabled: enabled,
      decoration: InputDecoration(labelText: label, helperText: helper),
      onChanged: onChanged,
    ),
  );
}
