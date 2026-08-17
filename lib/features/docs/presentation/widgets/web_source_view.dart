import 'package:flutter/material.dart';
import 'package:intellipilot/core/io/embedded_page.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/features/docs/data/dtos/doc_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// A web-link documentation source: the page embedded in a frame, under a bar
/// that opens it properly.
///
/// The bar is not optional decoration. A cross-origin frame gives us no way to
/// know whether the remote site refused to be embedded — many send
/// `X-Frame-Options` or a `frame-ancestors` policy, and the result is a blank
/// rectangle with no error we can observe. The escape hatch therefore sits
/// above the frame at all times, labelled with the source's own title, so a
/// blank frame is an inconvenience rather than a dead end.
class WebSourceView extends StatelessWidget {
  const WebSourceView({required this.source, super.key});

  final DocSource source;

  void _open() => openExternalUrl(source.webUrl);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LinkBar(source: source, onOpen: _open),
        Expanded(
          child: EmbeddedPage.isSupported
              ? EmbeddedPage(url: source.webUrl)
              : _Unsupported(onOpen: _open),
        ),
      ],
    );
  }
}

class _LinkBar extends StatelessWidget {
  const _LinkBar({required this.source, required this.onOpen});
  final DocSource source;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Icon(
                Icons.language,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Selectable so the address can be copied without leaving
                    // the page.
                    SelectableText(
                      source.webUrl,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: onOpen,
                label: Text(t.docsOpenInNewTab),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Non-web builds cannot embed a foreign page, so they offer the only thing
/// that does work there.
class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_in_browser,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              t.docsEmbedUnsupported,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              onPressed: onOpen,
              label: Text(t.docsOpenInNewTab),
            ),
          ],
        ),
      ),
    );
  }
}
