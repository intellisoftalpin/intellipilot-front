import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellipilot/app/build_info.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/theme/app_theme.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Fetch the backend service version from the public `/api/v1/version`
/// endpoint. Returns a display string, or [unavailable] on error.
Future<String> _fetchServerVersion(String unavailable) async {
  final res = await getIt<ApiClient>().get('/api/v1/version');
  return res.when(
    ok: (r) {
      final m = r.data as Map<String, dynamic>? ?? const {};
      final version = (m['version'] as String?) ?? '?';
      final sha = (m['git_sha'] as String?) ?? '';
      return sha.isEmpty ? version : '$version ($sha)';
    },
    err: (_) => unavailable,
  );
}

/// Jira-style About dialog: client version, build, flavor / channel, the
/// backend service version, and a copy-to-clipboard chip for the full client
/// identifier. Reachable from the Settings page.
Future<void> showIntelliPilotAboutDialog(BuildContext context) async {
  final t = AppLocalizations.of(context);
  // Kick off the fetch once, before the dialog builds, so rebuilds don't refire.
  final serverVersion = _fetchServerVersion(t.errUnknown);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text(t.aboutDialogTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row(theme, t.aboutFieldVersion, BuildInfo.version),
              const SizedBox(height: 8),
              _row(theme, t.aboutFieldBuild, BuildInfo.build),
              const SizedBox(height: 8),
              FutureBuilder<String>(
                future: serverVersion,
                builder: (c, snap) => _row(
                  theme,
                  t.aboutFieldServerVersion,
                  snap.connectionState == ConnectionState.done
                      ? (snap.data ?? '—')
                      : '…',
                ),
              ),
              const SizedBox(height: 8),
              _row(theme, t.aboutFieldFlavor, BuildInfo.flavor),
              const SizedBox(height: 8),
              _row(theme, t.aboutFieldChannel, _channelName(t)),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: SelectableText(
                  BuildInfo.clientIdentifier,
                  style: AppTheme.mono(ctx, size: 12).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 16),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: BuildInfo.clientIdentifier),
              );
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(t.aboutCopiedToClipboard)),
              );
            },
            label: Text(t.actionCopyBuildInfo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).closeButtonLabel),
          ),
        ],
      );
    },
  );
}

Widget _row(ThemeData theme, String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 120,
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
      Expanded(
        child: SelectableText(
          value,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    ],
  );
}

String _channelName(AppLocalizations t) {
  if (BuildInfo.isProd) return t.aboutChannelProd;
  if (BuildInfo.isStaging) return t.aboutChannelStaging;
  return t.aboutChannelDev;
}
