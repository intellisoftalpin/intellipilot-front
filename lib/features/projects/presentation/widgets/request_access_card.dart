import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Empty-state surface shown when the current user lacks the permission a
/// page or section needs. Phase 14 keeps this purely client-side: there's
/// no backend "request access" endpoint yet (parked for Phase 19), so the
/// CTA copies an admin email to the clipboard.
class RequestAccessCard extends StatelessWidget {
  const RequestAccessCard({
    required this.missing,
    this.adminEmail,
    super.key,
  });

  /// The permission the action would have required. Surfaced verbatim in
  /// the body so users know exactly what to ask for.
  final Permission missing;

  /// Optional project admin email pre-filled into the "copy to clipboard"
  /// helper. Resolves nothing if null — only the wire-format hint is shown.
  final String? adminEmail;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 36,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(t.requestAccessTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  t.requestAccessBody(missing.wire),
                  textAlign: TextAlign.center,
                ),
                if (adminEmail != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: adminEmail!),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(t.requestAccessCopied),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    label: Text(t.requestAccessCopyAdmin(adminEmail!)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
