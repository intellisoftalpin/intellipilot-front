import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_ldap_cubit.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class AdminLdapPage extends StatelessWidget {
  const AdminLdapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminLdapCubit>(
      create: (_) {
        final c = AdminLdapCubit(
          getIt<AdminRepository>(),
          getIt<ProfileRepository>(),
        );
        unawaited(c.load());
        return c;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context).adminLdapTitle),
        ),
        body: BlocBuilder<AdminLdapCubit, AdminLdapState>(
          builder: (context, state) => switch (state) {
            AdminLdapLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
            AdminLdapFailed(:final failure) => Center(
              child: Text(
                AppLocalizations.of(context).adminLdapLoadFailed(
                  failure.debugLabel,
                ),
              ),
            ),
            AdminLdapLoaded(
              :final settings,
              :final saving,
              :final currentUserIsLdap,
            ) =>
              _LdapForm(
                key: ValueKey(settings.updatedAt),
                settings: settings,
                saving: saving,
                readOnly: currentUserIsLdap,
              ),
          },
        ),
      ),
    );
  }
}

class _LdapForm extends StatefulWidget {
  const _LdapForm({
    required this.settings,
    required this.saving,
    this.readOnly = false,
    super.key,
  });
  final LdapSettings settings;
  final bool saving;

  /// When true the whole form is view-only (current admin signed in via LDAP).
  final bool readOnly;

  @override
  State<_LdapForm> createState() => _LdapFormState();
}

class _LdapFormState extends State<_LdapForm> {
  late bool _enabled;
  late bool _startTls;
  late bool _skipVerify;
  late String _bindMode;
  late final TextEditingController _serverUrl;
  late final TextEditingController _baseDn;
  late final TextEditingController _defaultDomain;
  late final TextEditingController _bindDnFormat;
  late final TextEditingController _userFilter;
  late final TextEditingController _superadminGroup;
  late final TextEditingController _attrEmail;
  late final TextEditingController _attrDisplayName;
  late final TextEditingController _attrUsername;
  late final TextEditingController _timeout;
  late final TextEditingController _serviceBindDn;
  late final TextEditingController _serviceBindPassword;
  late final TextEditingController _userSearchBase;
  late final TextEditingController _groupSearchBase;
  late final TextEditingController _groupSearchFilter;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _enabled = s.enabled;
    _startTls = s.useStartTls;
    _skipVerify = s.skipTlsVerify;
    _bindMode = s.bindMode == 'search' ? 'search' : 'direct';
    _serverUrl = TextEditingController(text: s.serverUrl);
    _baseDn = TextEditingController(text: s.baseDn);
    _defaultDomain = TextEditingController(text: s.defaultDomain);
    _bindDnFormat = TextEditingController(text: s.bindDnFormat);
    _userFilter = TextEditingController(text: s.userSearchFilter);
    _superadminGroup = TextEditingController(text: s.superadminGroup);
    _attrEmail = TextEditingController(text: s.attrEmail);
    _attrDisplayName = TextEditingController(text: s.attrDisplayName);
    _attrUsername = TextEditingController(text: s.attrUsername);
    _timeout = TextEditingController(text: '${s.connectionTimeoutSecs}');
    _serviceBindDn = TextEditingController(text: s.serviceBindDn);
    _serviceBindPassword = TextEditingController();
    _userSearchBase = TextEditingController(text: s.userSearchBase);
    _groupSearchBase = TextEditingController(text: s.groupSearchBase);
    _groupSearchFilter = TextEditingController(text: s.groupSearchFilter);
  }

  @override
  void dispose() {
    for (final c in [
      _serverUrl,
      _baseDn,
      _defaultDomain,
      _bindDnFormat,
      _userFilter,
      _superadminGroup,
      _attrEmail,
      _attrDisplayName,
      _attrUsername,
      _timeout,
      _serviceBindDn,
      _serviceBindPassword,
      _userSearchBase,
      _groupSearchBase,
      _groupSearchFilter,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  UpdateLdapSettingsRequest _build() => UpdateLdapSettingsRequest(
    enabled: _enabled,
    serverUrl: _serverUrl.text.trim(),
    useStartTls: _startTls,
    skipTlsVerify: _skipVerify,
    baseDn: _baseDn.text.trim(),
    defaultDomain: _defaultDomain.text.trim(),
    bindDnFormat: _bindDnFormat.text.trim().isEmpty
        ? '%s'
        : _bindDnFormat.text.trim(),
    userSearchFilter: _userFilter.text.trim(),
    superadminGroup: _superadminGroup.text.trim(),
    attrEmail: _attrEmail.text.trim(),
    attrDisplayName: _attrDisplayName.text.trim(),
    attrUsername: _attrUsername.text.trim(),
    connectionTimeoutSecs: int.tryParse(_timeout.text.trim()) ?? 10,
    bindMode: _bindMode,
    serviceBindDn: _serviceBindDn.text.trim(),
    serviceBindPassword: _serviceBindPassword.text.isEmpty
        ? null
        : _serviceBindPassword.text,
    userSearchBase: _userSearchBase.text.trim(),
    groupSearchBase: _groupSearchBase.text.trim(),
    groupSearchFilter: _groupSearchFilter.text.trim().isEmpty
        ? '(member=%s)'
        : _groupSearchFilter.text.trim(),
  );

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final failure = await context.read<AdminLdapCubit>().save(_build());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure == null ? l10n.adminLdapSaved : l10n.adminLdapSaveFailed,
        ),
      ),
    );
  }

  Future<void> _test() async {
    final creds = await showDialog<({String user, String pw})>(
      context: context,
      builder: (_) => const _TestCredentialsDialog(),
    );
    if (creds == null || !mounted) return;
    final result = await context.read<AdminLdapCubit>().test(
      settings: _build(),
      username: creds.user,
      password: creds.pw,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final l10n = AppLocalizations.of(dialogCtx);
        return AlertDialog(
          title: Text(
            (result?.ok ?? false)
                ? l10n.adminLdapBindSucceeded
                : l10n.adminLdapBindFailed,
          ),
          content: Text(
            result == null
                ? l10n.adminLdapRequestFailed
                : [
                    result.message,
                    if (result.email != null)
                      l10n.adminLdapEmailLine(result.email!),
                    if (result.username != null)
                      l10n.adminLdapUsernameLine(result.username!),
                    if (result.displayName != null)
                      l10n.adminLdapNameLine(result.displayName!),
                    if (result.wouldBeSuperadmin != null)
                      l10n.adminLdapSuperadminLine(
                        result.wouldBeSuperadmin.toString(),
                      ),
                  ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(l10n.adminLdapClose),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final ro = widget.readOnly;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (ro)
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Read-only'),
              subtitle: Text(
                'You are signed in via LDAP. LDAP settings can only be changed '
                'by a superadmin who signs in with a local password.',
              ),
            ),
          ),
        SwitchListTile(
          title: Text(l10n.adminLdapEnable),
          subtitle: Text(l10n.adminLdapEnableHelp),
          value: _enabled,
          onChanged: ro ? null : (v) => setState(() => _enabled = v),
        ),
        const Divider(),
        _field(
          _serverUrl,
          l10n.adminLdapServerUrl,
          hint: 'ldap://dc.example.com:389',
        ),
        SwitchListTile(
          title: Text(l10n.adminLdapUseStartTls),
          value: _startTls,
          onChanged: ro ? null : (v) => setState(() => _startTls = v),
        ),
        SwitchListTile(
          title: Text(l10n.adminLdapSkipTlsVerify),
          subtitle: Text(l10n.adminLdapSkipTlsVerifyHelp),
          value: _skipVerify,
          onChanged: ro ? null : (v) => setState(() => _skipVerify = v),
        ),
        _field(_baseDn, l10n.adminLdapBaseDn, hint: 'dc=example,dc=com'),
        _field(
          _defaultDomain,
          l10n.adminLdapDefaultDomain,
          hint: 'example.com',
        ),
        const SizedBox(height: 12),
        Text(l10n.adminLdapBindMode, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'direct',
              label: Text(l10n.adminLdapBindModeDirect),
            ),
            ButtonSegment(
              value: 'search',
              label: Text(l10n.adminLdapBindModeService),
            ),
          ],
          selected: {_bindMode},
          onSelectionChanged: ro
              ? null
              : (sel) => setState(() => _bindMode = sel.first),
        ),
        const SizedBox(height: 4),
        Text(
          _bindMode == 'search'
              ? l10n.adminLdapBindModeSearchHelp
              : l10n.adminLdapBindModeDirectHelp,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_bindMode == 'direct')
          _field(_bindDnFormat, l10n.adminLdapBindDnFormat, hint: '%s')
        else ...[
          _field(
            _serviceBindDn,
            l10n.adminLdapServiceBindDn,
            hint: 'cn=svc-search,dc=example,dc=com',
          ),
          _field(
            _serviceBindPassword,
            l10n.adminLdapServiceBindPassword,
            hint: widget.settings.serviceBindPasswordSet
                ? l10n.adminLdapServiceBindPasswordStored
                : l10n.adminLdapServiceBindPasswordNotSet,
            obscure: true,
          ),
          _field(
            _userSearchBase,
            l10n.adminLdapUserSearchBase,
            hint: l10n.adminLdapUserSearchBaseHint,
          ),
        ],
        _field(
          _userFilter,
          l10n.adminLdapUserSearchFilter,
          hint: _bindMode == 'search'
              ? '(userPrincipalName=%s)'
              : '(sAMAccountName=%s)',
        ),
        _field(
          _superadminGroup,
          l10n.adminLdapSuperadminGroup,
          hint: l10n.adminLdapSuperadminGroupHint,
        ),
        if (_bindMode == 'search') ...[
          _field(
            _groupSearchBase,
            l10n.adminLdapGroupSearchBase,
            hint: l10n.adminLdapGroupSearchBaseHint,
          ),
          _field(
            _groupSearchFilter,
            l10n.adminLdapGroupSearchFilter,
            hint: l10n.adminLdapGroupSearchFilterHint,
          ),
        ],
        const SizedBox(height: 8),
        Text(l10n.adminLdapAttributeMapping, style: theme.textTheme.titleSmall),
        _field(_attrEmail, l10n.adminLdapAttrEmail),
        _field(_attrDisplayName, l10n.adminLdapAttrDisplayName),
        _field(_attrUsername, l10n.adminLdapAttrUsername),
        _field(
          _timeout,
          l10n.adminLdapConnectionTimeout,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _test,
              icon: const Icon(Icons.network_check),
              label: Text(l10n.adminLdapTestConnection),
            ),
            const Spacer(),
            // Saving is hidden for LDAP-authenticated admins (read-only).
            if (!ro)
              FilledButton(
                onPressed: widget.saving ? null : _save,
                child: widget.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.adminLdapSave),
              ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: c,
      readOnly: widget.readOnly,
      keyboardType: keyboardType,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );
}

class _TestCredentialsDialog extends StatefulWidget {
  const _TestCredentialsDialog();

  @override
  State<_TestCredentialsDialog> createState() => _TestCredentialsDialogState();
}

class _TestCredentialsDialogState extends State<_TestCredentialsDialog> {
  final _user = TextEditingController();
  final _pw = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminLdapTestBind),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _user,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.adminLdapUsernameOrEmail,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: InputDecoration(labelText: l10n.adminLdapPassword),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminLdapCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((user: _user.text.trim(), pw: _pw.text)),
          child: Text(l10n.adminLdapTest),
        ),
      ],
    );
  }
}
