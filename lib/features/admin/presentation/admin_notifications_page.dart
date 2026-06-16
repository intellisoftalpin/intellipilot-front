import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/admin/presentation/cubits/admin_notifications_cubit.dart';

class AdminNotificationsPage extends StatelessWidget {
  const AdminNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdminNotificationsCubit>(
      create: (_) => AdminNotificationsCubit(getIt<AdminRepository>())..load(),
      child: BlocBuilder<AdminNotificationsCubit, AdminNotificationsState>(
        builder: (context, state) => switch (state) {
          AdminNotificationsLoading() => Scaffold(
            appBar: AppBar(title: const Text('Notifications')),
            body: const Center(child: CircularProgressIndicator()),
          ),
          AdminNotificationsFailed(:final failure) => Scaffold(
            appBar: AppBar(title: const Text('Notifications')),
            body: Center(child: Text('Failed: ${failure.debugLabel}')),
          ),
          AdminNotificationsLoaded() => _NotificationsForm(state: state),
        },
      ),
    );
  }
}

class _NotificationsForm extends StatefulWidget {
  const _NotificationsForm({required this.state});
  final AdminNotificationsLoaded state;

  @override
  State<_NotificationsForm> createState() => _NotificationsFormState();
}

class _NotificationsFormState extends State<_NotificationsForm> {
  // Mail
  late bool _mailEnabled;
  late String _mailProvider;
  late final TextEditingController _fromAddr;
  late final TextEditingController _fromName;
  late final TextEditingController _smtpHost;
  late final TextEditingController _smtpPort;
  late final TextEditingController _smtpUser;
  late final TextEditingController _smtpPass;
  late bool _smtpStartTls;
  late bool _smtpSkipVerify;
  late final TextEditingController _mgKey;
  late final TextEditingController _mgDomain;
  late final TextEditingController _mgBase;
  // Matrix
  late bool _matrixEnabled;
  late final TextEditingController _matrixHs;
  late final TextEditingController _matrixRoom;
  late final TextEditingController _matrixToken;
  // Telegram
  late bool _tgEnabled;
  late final TextEditingController _tgToken;
  late final TextEditingController _tgChat;
  // Events
  late bool _mailLogin;
  late bool _mailIssueCreated;
  late bool _mailIssueResolved;
  late bool _mailDaily;
  late bool _msgLogin;
  late bool _msgIssueCreated;
  late bool _msgIssueResolved;
  late bool _msgDaily;

  @override
  void initState() {
    super.initState();
    final s = widget.state.settings;
    _mailEnabled = s.mailEnabled;
    _mailProvider = s.mailProvider == 'mailgun' ? 'mailgun' : 'smtp';
    _fromAddr = TextEditingController(text: s.mailFromAddress);
    _fromName = TextEditingController(text: s.mailFromName);
    _smtpHost = TextEditingController(text: s.smtpHost);
    _smtpPort = TextEditingController(text: s.smtpPort.toString());
    _smtpUser = TextEditingController(text: s.smtpUsername);
    _smtpPass = TextEditingController();
    _smtpStartTls = s.smtpUseStarttls;
    _smtpSkipVerify = s.smtpSkipTlsVerify;
    _mgKey = TextEditingController();
    _mgDomain = TextEditingController(text: s.mailgunDomain);
    _mgBase = TextEditingController(text: s.mailgunBaseUrl);
    _matrixEnabled = s.matrixEnabled;
    _matrixHs = TextEditingController(text: s.matrixHomeserver);
    _matrixRoom = TextEditingController(text: s.matrixRoomId);
    _matrixToken = TextEditingController();
    _tgEnabled = s.telegramEnabled;
    _tgToken = TextEditingController();
    _tgChat = TextEditingController(text: s.telegramChatId);
    _mailLogin = s.mailOnLogin;
    _mailIssueCreated = s.mailOnIssueCreated;
    _mailIssueResolved = s.mailOnIssueResolved;
    _mailDaily = s.mailOnDailyReport;
    _msgLogin = s.msgOnLogin;
    _msgIssueCreated = s.msgOnIssueCreated;
    _msgIssueResolved = s.msgOnIssueResolved;
    _msgDaily = s.msgOnDailyReport;
  }

  @override
  void dispose() {
    for (final c in [
      _fromAddr,
      _fromName,
      _smtpHost,
      _smtpPort,
      _smtpUser,
      _smtpPass,
      _mgKey,
      _mgDomain,
      _mgBase,
      _matrixHs,
      _matrixRoom,
      _matrixToken,
      _tgToken,
      _tgChat,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// All settings always travel together: the backend update is one PUT of the
  /// full object, and blank secrets are preserved server-side. So a per-tab
  /// "Save" persists the whole form — the other tabs keep their loaded values.
  NotificationSettingsUpdate _build() => NotificationSettingsUpdate(
    mailEnabled: _mailEnabled,
    mailProvider: _mailProvider,
    mailFromAddress: _fromAddr.text.trim(),
    mailFromName: _fromName.text.trim(),
    smtpHost: _smtpHost.text.trim(),
    smtpPort: int.tryParse(_smtpPort.text.trim()) ?? 587,
    smtpUsername: _smtpUser.text.trim(),
    smtpPassword: _smtpPass.text,
    smtpUseStarttls: _smtpStartTls,
    smtpSkipTlsVerify: _smtpSkipVerify,
    mailgunApiKey: _mgKey.text,
    mailgunDomain: _mgDomain.text.trim(),
    mailgunBaseUrl: _mgBase.text.trim(),
    matrixEnabled: _matrixEnabled,
    matrixHomeserver: _matrixHs.text.trim(),
    matrixRoomId: _matrixRoom.text.trim(),
    matrixAccessToken: _matrixToken.text,
    telegramEnabled: _tgEnabled,
    telegramBotToken: _tgToken.text,
    telegramChatId: _tgChat.text.trim(),
    mailOnLogin: _mailLogin,
    mailOnIssueCreated: _mailIssueCreated,
    mailOnIssueResolved: _mailIssueResolved,
    mailOnDailyReport: _mailDaily,
    msgOnLogin: _msgLogin,
    msgOnIssueCreated: _msgIssueCreated,
    msgOnIssueResolved: _msgIssueResolved,
    msgOnDailyReport: _msgDaily,
  );

  Future<void> _save(String label) async {
    final failure = await context.read<AdminNotificationsCubit>().save(
      _build(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure == null
              ? '$label saved.'
              : 'Save failed: ${failure.debugLabel}',
        ),
      ),
    );
  }

  Future<void> _test(String channel) async {
    final cubit = context.read<AdminNotificationsCubit>();
    String? to;
    if (channel == 'mail') {
      to = await _askRecipient();
      if (to == null) return;
    }
    final result = await cubit.test(channel: channel, to: to);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text((result?.ok ?? false) ? 'Test sent' : 'Test failed'),
        content: Text(result?.message ?? 'The request failed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askRecipient() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send test email'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Recipient email'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Email'),
              Tab(text: 'Matrix'),
              Tab(text: 'Telegram'),
              Tab(text: 'Events'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tab(_emailChildren()),
            _tab(_matrixChildren()),
            _tab(_telegramChildren()),
            _tab(_eventChildren()),
          ],
        ),
      ),
    );
  }

  /// A scrollable, width-constrained tab body.
  Widget _tab(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(padding: const EdgeInsets.all(24), children: children),
    ),
  );

  Widget _saveButton(String label) {
    final saving = widget.state.saving;
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: saving ? null : () => _save(label),
        icon: saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text('Save $label'),
      ),
    );
  }

  Widget _testNote() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      'Tests use the saved configuration — save before testing.',
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
    ),
  );

  Widget _field(
    TextEditingController c,
    String label, {
    bool secret = false,
    bool isSet = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      controller: c,
      obscureText: secret,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        helperText: secret
            ? (isSet ? 'Stored — leave blank to keep' : 'Not set')
            : null,
      ),
    ),
  );

  // -------------------------------------------------------------------------
  // Email tab
  // -------------------------------------------------------------------------
  List<Widget> _emailChildren() {
    final s = widget.state.settings;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enable email notifications'),
        value: _mailEnabled,
        onChanged: (v) => setState(() => _mailEnabled = v),
      ),
      const SizedBox(height: 8),
      Text('Provider', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'smtp', label: Text('SMTP')),
          ButtonSegment(value: 'mailgun', label: Text('Mailgun')),
        ],
        selected: {_mailProvider},
        onSelectionChanged: (sel) => setState(() => _mailProvider = sel.first),
      ),
      _field(_fromAddr, 'From address', keyboard: TextInputType.emailAddress),
      _field(_fromName, 'From name'),
      const SizedBox(height: 16),
      if (_mailProvider == 'smtp') ...[
        Text('SMTP', style: Theme.of(context).textTheme.titleSmall),
        _field(_smtpHost, 'SMTP host'),
        _field(_smtpPort, 'SMTP port', keyboard: TextInputType.number),
        _field(_smtpUser, 'SMTP username'),
        _field(
          _smtpPass,
          'SMTP password',
          secret: true,
          isSet: s.smtpPasswordSet,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use STARTTLS (port 587)'),
          subtitle: const Text('Off = implicit TLS (port 465)'),
          value: _smtpStartTls,
          onChanged: (v) => setState(() => _smtpStartTls = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Skip TLS verification'),
          subtitle: const Text('Self-signed certificates only'),
          value: _smtpSkipVerify,
          onChanged: (v) => setState(() => _smtpSkipVerify = v),
        ),
      ] else ...[
        Text('Mailgun', style: Theme.of(context).textTheme.titleSmall),
        _field(_mgDomain, 'Mailgun domain'),
        _field(_mgBase, 'Mailgun base URL (e.g. https://api.eu.mailgun.net)'),
        _field(
          _mgKey,
          'Mailgun API key',
          secret: true,
          isSet: s.mailgunApiKeySet,
        ),
      ],
      const SizedBox(height: 16),
      _testNote(),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => _test('mail'),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send test email'),
          ),
          const Spacer(),
          _saveButton('Email'),
        ],
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Matrix tab
  // -------------------------------------------------------------------------
  List<Widget> _matrixChildren() {
    final s = widget.state.settings;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enable Matrix'),
        subtitle: const Text(
          'Only gates automatic notifications — the test '
          'button works regardless.',
        ),
        value: _matrixEnabled,
        onChanged: (v) => setState(() => _matrixEnabled = v),
      ),
      _field(_matrixHs, 'Homeserver URL (https://chat.example.com)'),
      _field(_matrixRoom, 'Room ID (!room:example.com)'),
      _field(
        _matrixToken,
        'Access token',
        secret: true,
        isSet: s.matrixAccessTokenSet,
      ),
      const SizedBox(height: 16),
      _testNote(),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => _test('matrix'),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send test to Matrix'),
          ),
          const Spacer(),
          _saveButton('Matrix'),
        ],
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Telegram tab
  // -------------------------------------------------------------------------
  List<Widget> _telegramChildren() {
    final s = widget.state.settings;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enable Telegram'),
        subtitle: const Text(
          'Only gates automatic notifications — the test '
          'button works regardless.',
        ),
        value: _tgEnabled,
        onChanged: (v) => setState(() => _tgEnabled = v),
      ),
      _field(_tgToken, 'Bot token', secret: true, isSet: s.telegramBotTokenSet),
      _field(_tgChat, 'Chat ID'),
      const SizedBox(height: 16),
      _testNote(),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => _test('telegram'),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send test to Telegram'),
          ),
          const Spacer(),
          _saveButton('Telegram'),
        ],
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Events tab
  // -------------------------------------------------------------------------
  List<Widget> _eventChildren() => [
    Text(
      'Choose which events trigger a notification, per channel.',
      style: Theme.of(context).textTheme.bodyMedium,
    ),
    const SizedBox(height: 16),
    const Row(
      children: [
        Expanded(flex: 3, child: Text('')),
        Expanded(child: Center(child: Text('Email'))),
        Expanded(child: Center(child: Text('Messengers'))),
      ],
    ),
    _eventRow(
      'Login',
      mail: _mailLogin,
      msg: _msgLogin,
      onMail: (v) => setState(() => _mailLogin = v),
      onMsg: (v) => setState(() => _msgLogin = v),
    ),
    _eventRow(
      'Issue created',
      mail: _mailIssueCreated,
      msg: _msgIssueCreated,
      onMail: (v) => setState(() => _mailIssueCreated = v),
      onMsg: (v) => setState(() => _msgIssueCreated = v),
    ),
    _eventRow(
      'Issue resolved',
      mail: _mailIssueResolved,
      msg: _msgIssueResolved,
      onMail: (v) => setState(() => _mailIssueResolved = v),
      onMsg: (v) => setState(() => _msgIssueResolved = v),
    ),
    _eventRow(
      'Daily status report',
      mail: _mailDaily,
      msg: _msgDaily,
      onMail: (v) => setState(() => _mailDaily = v),
      onMsg: (v) => setState(() => _msgDaily = v),
    ),
    const SizedBox(height: 24),
    _saveButton('Events'),
  ];

  Widget _eventRow(
    String label, {
    required bool mail,
    required bool msg,
    required ValueChanged<bool> onMail,
    required ValueChanged<bool> onMsg,
  }) => Row(
    children: [
      Expanded(flex: 3, child: Text(label)),
      Expanded(
        child: Center(
          child: Checkbox(value: mail, onChanged: (v) => onMail(v ?? false)),
        ),
      ),
      Expanded(
        child: Center(
          child: Checkbox(value: msg, onChanged: (v) => onMsg(v ?? false)),
        ),
      ),
    ],
  );
}
