import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Reveals one-time recovery codes. Shown once after enrollment or after
/// regeneration — the backend never returns them again.
class RecoveryCodesCard extends StatelessWidget {
  const RecoveryCodesCard({required this.codes, super.key});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lock_clock,
                  color: colors.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.recoveryCodesTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t.recoveryCodesHint,
              style: TextStyle(color: colors.onTertiaryContainer),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: codes
                  .map(
                    (c) => SelectableText(
                      c,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        color: colors.onTertiaryContainer,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: Text(t.actionCopyAll),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: codes.join('\n')),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t.copiedToClipboard)),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
