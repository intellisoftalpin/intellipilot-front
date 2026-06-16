import 'package:flutter/material.dart';
import 'package:intellipilot/app/branding/brand_logo.dart';
import 'package:intellipilot/app/branding/branding_cubit.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';

/// White-label branding admin page: override the app name, the login-screen
/// message and the app icon, each resettable to the bundled default.
class AdminBrandingPage extends StatefulWidget {
  const AdminBrandingPage({super.key});

  @override
  State<AdminBrandingPage> createState() => _AdminBrandingPageState();
}

class _AdminBrandingPageState extends State<AdminBrandingPage> {
  final _repo = getIt<AdminRepository>();
  final _name = TextEditingController();
  final _message = TextEditingController();

  PlatformSettings? _settings;
  AppFailure? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await _repo.getSettings();
    if (!mounted) return;
    res.when(
      ok: (s) => setState(() {
        _settings = s;
        _loadError = null;
        _name.text = s.appName ?? '';
        _message.text = s.appMessage ?? '';
      }),
      err: (f) => setState(() => _loadError = f),
    );
  }

  /// Runs [action], reflecting its result in the page and refreshing the
  /// app-wide branding so the change shows immediately everywhere.
  Future<void> _run(
    Future<Result<PlatformSettings, AppFailure>> Function() action,
    String okMessage,
  ) async {
    setState(() => _busy = true);
    final res = await action();
    if (!mounted) return;
    await res.when(
      ok: (s) async {
        await getIt<BrandingCubit>().load();
        if (!mounted) return;
        setState(() {
          _settings = s;
          _name.text = s.appName ?? '';
          _message.text = s.appMessage ?? '';
        });
        _toast(okMessage);
      },
      err: (_) async => _toast('Update failed.', isError: true),
    );
    if (mounted) setState(() => _busy = false);
  }

  void _toast(String message, {bool isError = false}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? theme.colorScheme.error : null,
      ),
    );
  }

  Future<void> _saveText() => _run(
    () => _repo.updateBranding(
      appName: _name.text.trim(),
      appMessage: _message.text.trim(),
    ),
    'Branding saved.',
  );

  Future<void> _resetName() {
    _name.clear();
    return _run(
      () => _repo.updateBranding(appName: '', appMessage: _message.text.trim()),
      'Name reset to default.',
    );
  }

  Future<void> _pickIcon() async {
    final picker = getIt<FilePicker>();
    if (!picker.isSupported) {
      _toast('File upload is not supported on this platform.', isError: true);
      return;
    }
    final picked = await picker.pickSingleFile();
    if (picked == null || !mounted) return;
    await _run(
      () => _repo.uploadBrandingIcon(
        filename: picked.name,
        bytes: picked.bytes,
        contentType: picked.contentType,
      ),
      'Icon updated.',
    );
  }

  Future<void> _resetIcon() =>
      _run(_repo.deleteBrandingIcon, 'Icon reset to default.');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branding')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_settings == null) {
      if (_loadError != null) {
        return Center(child: Text('Failed: ${_loadError!.debugLabel}'));
      }
      return const Center(child: CircularProgressIndicator());
    }
    final settings = _settings!;
    return AbsorbPointer(
      absorbing: _busy,
      child: Opacity(
        opacity: _busy ? 0.6 : 1,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'White-label these surfaces — the login screen, the top bar and '
              'the browser tab. Empty fields fall back to the bundled defaults.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // ---- App icon ----
            Text('App icon', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                const BrandLogo(size: 64, borderRadius: 12),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.upload_file),
                            onPressed: _pickIcon,
                            label: const Text('Upload icon'),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.restart_alt),
                            onPressed: settings.hasCustomIcon
                                ? _resetIcon
                                : null,
                            label: const Text('Reset to default icon'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'PNG or other image, up to 1 MB. A square image works '
                        'best.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 40),

            // ---- App name ----
            Text('App name', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              maxLength: 64,
              decoration: const InputDecoration(
                hintText: 'IntelliPilot',
                helperText:
                    'Shown on login, in the top bar and the browser '
                    'tab. Leave empty for the default.',
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.restart_alt, size: 18),
                onPressed: settings.appName == null ? null : _resetName,
                label: const Text('Reset to default name'),
              ),
            ),
            const Divider(height: 40),

            // ---- Message ----
            Text(
              'Message to users (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLength: 500,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g. a welcome note or maintenance notice',
                helperText: 'Shown on the login screen. Leave empty to hide.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                onPressed: _saveText,
                label: const Text('Save name & message'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
