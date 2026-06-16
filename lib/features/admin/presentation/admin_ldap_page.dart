import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_ldap_cubit.dart';

class AdminLdapPage extends StatelessWidget {
  const AdminLdapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminLdapCubit>(
      create: (_) => AdminLdapCubit(getIt<AdminRepository>())..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('LDAP / Directory')),
        body: BlocBuilder<AdminLdapCubit, AdminLdapState>(
          builder: (context, state) => switch (state) {
            AdminLdapLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
            AdminLdapFailed(:final failure) => Center(
              child: Text('Failed to load: ${failure.debugLabel}'),
            ),
            AdminLdapLoaded(:final settings, :final saving) => _LdapForm(
              key: ValueKey(settings.updatedAt),
              settings: settings,
              saving: saving,
            ),
          },
        ),
      ),
    );
  }
}

class _LdapForm extends StatefulWidget {
  const _LdapForm({required this.settings, required this.saving, super.key});
  final LdapSettings settings;
  final bool saving;

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
    final failure = await context.read<AdminLdapCubit>().save(_build());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure == null ? 'LDAP settings saved.' : 'Save failed.',
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
      builder: (dialogCtx) => AlertDialog(
        title: Text((result?.ok ?? false) ? 'Bind succeeded' : 'Bind failed'),
        content: Text(
          result == null
              ? 'The request failed.'
              : [
                  result.message,
                  if (result.email != null) 'Email: ${result.email}',
                  if (result.username != null) 'Username: ${result.username}',
                  if (result.displayName != null) 'Name: ${result.displayName}',
                  if (result.wouldBeSuperadmin != null)
                    'Superadmin: ${result.wouldBeSuperadmin}',
                ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('Enable LDAP authentication'),
          subtitle: const Text(
            'When enabled, all users EXCEPT local superadmins must sign in '
            'through the directory. Keep at least one local superadmin so you '
            'can always reach this page.',
          ),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const Divider(),
        _field(_serverUrl, 'Server URL', hint: 'ldap://dc.example.com:389'),
        SwitchListTile(
          title: const Text('Use StartTLS'),
          value: _startTls,
          onChanged: (v) => setState(() => _startTls = v),
        ),
        SwitchListTile(
          title: const Text('Skip TLS certificate verification'),
          subtitle: const Text('Lab / self-signed only.'),
          value: _skipVerify,
          onChanged: (v) => setState(() => _skipVerify = v),
        ),
        _field(_baseDn, 'Base DN', hint: 'dc=example,dc=com'),
        _field(_defaultDomain, 'Default domain', hint: 'example.com'),
        const SizedBox(height: 12),
        Text('Bind mode', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'direct', label: Text('Direct bind')),
            ButtonSegment(value: 'search', label: Text('Service account')),
          ],
          selected: {_bindMode},
          onSelectionChanged: (sel) => setState(() => _bindMode = sel.first),
        ),
        const SizedBox(height: 4),
        Text(
          _bindMode == 'search'
              ? 'A service account searches for the user, then we bind as the '
                    'found DN. Use this for OpenLDAP where the login name is not '
                    'the entry RDN.'
              : 'Bind directly as the user via the Bind DN format below. Use '
                    'this for Active Directory (user@domain).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_bindMode == 'direct')
          _field(_bindDnFormat, 'Bind DN format', hint: '%s')
        else ...[
          _field(
            _serviceBindDn,
            'Service bind DN',
            hint: 'cn=svc-search,dc=example,dc=com',
          ),
          _field(
            _serviceBindPassword,
            'Service bind password',
            hint: widget.settings.serviceBindPasswordSet
                ? 'Stored — leave blank to keep'
                : 'Not set',
            obscure: true,
          ),
          _field(
            _userSearchBase,
            'User search base',
            hint: 'leave empty to use Base DN',
          ),
        ],
        _field(
          _userFilter,
          'User search filter',
          hint: _bindMode == 'search'
              ? '(userPrincipalName=%s)'
              : '(sAMAccountName=%s)',
        ),
        _field(
          _superadminGroup,
          'Superadmin group (CN or DN)',
          hint: 'leave empty to disable',
        ),
        if (_bindMode == 'search') ...[
          _field(
            _groupSearchBase,
            'Group search base',
            hint: 'ou=groups,dc=example,dc=com (empty disables group search)',
          ),
          _field(
            _groupSearchFilter,
            'Group search filter',
            hint: '(member=%s)  — %s is the user DN',
          ),
        ],
        const SizedBox(height: 8),
        Text('Attribute mapping', style: theme.textTheme.titleSmall),
        _field(_attrEmail, 'Email attribute'),
        _field(_attrDisplayName, 'Display-name attribute'),
        _field(_attrUsername, 'Username attribute'),
        _field(
          _timeout,
          'Connection timeout (seconds)',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _test,
              icon: const Icon(Icons.network_check),
              label: const Text('Test connection'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: widget.saving ? null : _save,
              child: widget.saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
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
    return AlertDialog(
      title: const Text('Test bind'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _user,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Username or email'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((user: _user.text.trim(), pw: _pw.text)),
          child: const Text('Test'),
        ),
      ],
    );
  }
}
