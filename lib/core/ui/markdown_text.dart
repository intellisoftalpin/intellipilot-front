import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';

/// Block-level Markdown renderer with inline formatting. Handles the cases
/// that show up in IntelliPilot descriptions, comments and wiki pages without
/// pulling in a full markdown dependency: ATX headings (`#`, `##`, `###`),
/// bullet lists (`- `, `* `), numbered lists (`1. `), blockquotes (`> `),
/// fenced code blocks (triple backticks), and paragraphs.
///
/// Inline formatting is applied to every non-code block: `**bold**`,
/// `*italic*` / `_italic_`, `` `code` ``, `[label](url)` links, and bare
/// `https://…` / `www.…` URLs.
///
/// Links are **navigable**: in-app targets (a `/projects/...` path, or an
/// absolute URL pointing at this same origin) route through go_router so the
/// SPA never reloads; everything else goes to [openExternalUrl].
///
/// Stateful purely for gesture-recognizer lifetime — each link span owns a
/// [TapGestureRecognizer] that must be disposed or it leaks.
class MarkdownText extends StatefulWidget {
  const MarkdownText(this.source, {this.mentions = const {}, super.key});
  final String source;

  /// Project members keyed by lowercase `@handle`, used to render `@mentions`
  /// as chips. Unknown handles stay plain text — a mention of someone who left
  /// the project shouldn't turn into a broken widget.
  final Map<String, UserRef> mentions;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  /// Recognizers backing the spans of the CURRENT build. Replaced wholesale on
  /// every rebuild; the previous generation is disposed one frame later so a
  /// recognizer never dies while it is still dispatching the tap that caused
  /// the rebuild.
  List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = [];
    super.dispose();
  }

  /// Routes a tapped link. In-app paths keep the SPA alive; anything else is
  /// handed to the platform.
  void _openLink(String rawUrl) {
    final url = rawUrl.startsWith('www.') ? 'https://$rawUrl' : rawUrl;
    if (rawUrl.startsWith('/')) {
      context.go(rawUrl);
      return;
    }
    final uri = Uri.tryParse(url);
    final isHttp =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (isHttp && kIsWeb && uri.origin == Uri.base.origin) {
      final buf = StringBuffer(uri.path.isEmpty ? '/' : uri.path);
      if (uri.hasQuery) buf.write('?${uri.query}');
      if (uri.fragment.isNotEmpty) buf.write('#${uri.fragment}');
      context.go(buf.toString());
      return;
    }
    openExternalUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(widget.source);
    if (blocks.isEmpty) return const SizedBox.shrink();

    // Retire the previous generation of recognizers after this frame settles.
    final retired = _recognizers;
    if (retired.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in retired) {
          r.dispose();
        }
      });
    }
    _recognizers = [];
    final ctx = _InlineCtx(
      theme: Theme.of(context),
      onTapUrl: _openLink,
      sink: _recognizers,
      mentions: widget.mentions,
    );

    // One SelectionArea over all blocks: a single drag (or Ctrl/Cmd+A) selects
    // the whole text across paragraphs, lists, and code — per-block selectable
    // widgets would each form their own selection island. Tap recognizers on
    // link spans still fire inside it: RenderParagraph hit-tests them directly.
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in blocks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _renderBlock(context, ctx, b),
            ),
        ],
      ),
    );
  }

  Widget _renderBlock(BuildContext context, _InlineCtx ctx, _Block b) {
    final theme = Theme.of(context);
    switch (b.kind) {
      case _Kind.h1:
        return _richLine(
          context,
          ctx,
          b.lines.join('\n'),
          theme.textTheme.headlineSmall,
        );
      case _Kind.h2:
        return _richLine(
          context,
          ctx,
          b.lines.join('\n'),
          theme.textTheme.titleLarge,
        );
      case _Kind.h3:
        return _richLine(
          context,
          ctx,
          b.lines.join('\n'),
          theme.textTheme.titleMedium,
        );
      case _Kind.code:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            b.lines.join('\n'),
            style: TextStyle(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface,
            ),
          ),
        );
      case _Kind.quote:
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          child: _richLine(
            context,
            ctx,
            b.lines.join('\n'),
            theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      case _Kind.bullet:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in b.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: _richLine(context, ctx, l, null)),
                  ],
                ),
              ),
          ],
        );
      case _Kind.numbered:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < b.lines.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}.  '),
                    Expanded(child: _richLine(context, ctx, b.lines[i], null)),
                  ],
                ),
              ),
          ],
        );
      case _Kind.paragraph:
        return _richLine(context, ctx, b.lines.join('\n'), null);
    }
  }

  /// A line/paragraph with inline markdown applied over [base]. Selection is
  /// provided by the enclosing [SelectionArea], not per widget.
  Widget _richLine(
    BuildContext context,
    _InlineCtx ctx,
    String text,
    TextStyle? base,
  ) {
    final effective = base ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(style: effective, children: _inline(text, ctx, effective)),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline formatting
// ---------------------------------------------------------------------------

/// Per-build context handed to the inline tokenizer: the theme it styles
/// against, the tap handler links fire, and the sink that collects created
/// recognizers so the [State] can dispose them.
class _InlineCtx {
  const _InlineCtx({
    required this.theme,
    required this.onTapUrl,
    required this.sink,
    required this.mentions,
  });

  final ThemeData theme;
  final void Function(String url) onTapUrl;
  final List<TapGestureRecognizer> sink;
  final Map<String, UserRef> mentions;

  /// Turns a relative attachment path into something `Image.network` can
  /// fetch. Resolved lazily and defensively: this is a core widget that must
  /// keep rendering where DI was never configured (tests, isolated previews),
  /// and there an absolute URL simply isn't available.
  String absolute(String url) {
    if (!url.startsWith('/')) return url;
    if (!getIt.isRegistered<ApiConfig>()) return url;
    return '${getIt<ApiConfig>().baseUrl}$url';
  }
}

class _Matcher {
  const _Matcher(this.re, this.build);
  final RegExp re;
  final InlineSpan Function(RegExpMatch m, _InlineCtx ctx, TextStyle? base)
  build;
}

/// Builds the tappable span for a link. [label] is what the user reads,
/// [url] where it points.
InlineSpan _linkSpan(
  String label,
  String url,
  _InlineCtx ctx,
) {
  final recognizer = TapGestureRecognizer()..onTap = () => ctx.onTapUrl(url);
  ctx.sink.add(recognizer);
  return TextSpan(
    text: label,
    recognizer: recognizer,
    mouseCursor: SystemMouseCursors.click,
    style: TextStyle(
      color: ctx.theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: ctx.theme.colorScheme.primary,
    ),
  );
}

final _matchers = <_Matcher>[
  // `![alt](url)` — inline image. MUST precede the link matcher: they share
  // the `[..](..)` tail, and without this an image would render as a link
  // labelled with its alt text and a stray `!` in front of it.
  _Matcher(
    RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)'),
    (m, ctx, base) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _MarkdownImage(
        url: ctx.absolute(m.group(2)!),
        alt: m.group(1) ?? '',
        onOpen: () => ctx.onTapUrl(m.group(2)!),
      ),
    ),
  ),
  // `@handle` — rendered as a member chip when the handle resolves.
  _Matcher(
    RegExp('@([A-Za-z0-9._-]{2,64})'),
    (m, ctx, base) {
      final user = ctx.mentions[m.group(1)!.toLowerCase()];
      if (user == null) return TextSpan(text: m.group(0));
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _MentionChip(user: user),
      );
    },
  ),
  // `[label](url)` — navigable. Listed first so it wins the earliest-match
  // tie-break against the bare-URL matcher for the URL inside its parens.
  _Matcher(
    RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'),
    (m, ctx, base) => _linkSpan(m.group(1)!, m.group(2)!, ctx),
  ),
  // `**bold**` — may contain further inline markup.
  _Matcher(
    RegExp(r'\*\*(.+?)\*\*'),
    (m, ctx, base) => TextSpan(
      style: const TextStyle(fontWeight: FontWeight.w700),
      children: _inline(m.group(1)!, ctx, base),
    ),
  ),
  // `` `code` `` — literal monospace.
  _Matcher(
    RegExp('`([^`]+)`'),
    (m, ctx, base) => TextSpan(
      text: m.group(1),
      style: TextStyle(
        fontFamily: 'monospace',
        backgroundColor: ctx.theme.colorScheme.surfaceContainerHighest,
      ),
    ),
  ),
  // `*italic*`
  _Matcher(
    RegExp(r'\*(.+?)\*'),
    (m, ctx, base) => TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      children: _inline(m.group(1)!, ctx, base),
    ),
  ),
  // `_italic_`
  _Matcher(
    RegExp('_(.+?)_'),
    (m, ctx, base) => TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      children: _inline(m.group(1)!, ctx, base),
    ),
  ),
  // Bare `https://…` / `www.…` autolink. The trailing character class excludes
  // sentence punctuation so `see https://example.com.` doesn't swallow the
  // full stop into the link.
  _Matcher(
    RegExp(r'(?:https?://|www\.)[^\s<>\[\]()]*[^\s<>\[\]().,;:!?]'),
    (m, ctx, base) => _linkSpan(m.group(0)!, m.group(0)!, ctx),
  ),
];

/// Tokenise [text] into styled spans, always emitting the earliest match so
/// overlapping markers (e.g. bold before italic) resolve predictably.
List<InlineSpan> _inline(String text, _InlineCtx ctx, TextStyle? base) {
  final spans = <InlineSpan>[];
  var rest = text;
  while (rest.isNotEmpty) {
    _Matcher? bestMatcher;
    RegExpMatch? best;
    for (final m in _matchers) {
      final match = m.re.firstMatch(rest);
      if (match != null && (best == null || match.start < best.start)) {
        best = match;
        bestMatcher = m;
      }
    }
    if (best == null || bestMatcher == null) {
      spans.add(TextSpan(text: rest));
      break;
    }
    if (best.start > 0) {
      spans.add(TextSpan(text: rest.substring(0, best.start)));
    }
    spans.add(bestMatcher.build(best, ctx, base));
    rest = rest.substring(best.end);
  }
  return spans;
}

// ---------------------------------------------------------------------------
// Block parsing
// ---------------------------------------------------------------------------

enum _Kind { h1, h2, h3, paragraph, bullet, numbered, quote, code }

class _Block {
  _Block(this.kind);
  final _Kind kind;
  final List<String> lines = [];
}

List<_Block> _parse(String source) {
  final blocks = <_Block>[];
  final raw = source.split('\n');
  _Block? current;
  var inCode = false;

  void flush() {
    if (current != null && current!.lines.isNotEmpty) {
      blocks.add(current!);
    }
    current = null;
  }

  for (final line in raw) {
    if (line.trim() == '```') {
      flush();
      if (!inCode) {
        current = _Block(_Kind.code);
        inCode = true;
      } else {
        inCode = false;
      }
      continue;
    }
    if (inCode) {
      current ??= _Block(_Kind.code);
      current!.lines.add(line);
      continue;
    }
    if (line.startsWith('### ')) {
      flush();
      current = _Block(_Kind.h3)..lines.add(line.substring(4));
      flush();
      continue;
    }
    if (line.startsWith('## ')) {
      flush();
      current = _Block(_Kind.h2)..lines.add(line.substring(3));
      flush();
      continue;
    }
    if (line.startsWith('# ')) {
      flush();
      current = _Block(_Kind.h1)..lines.add(line.substring(2));
      flush();
      continue;
    }
    if (line.startsWith('> ') || line.trim() == '>') {
      if (current?.kind != _Kind.quote) {
        flush();
        current = _Block(_Kind.quote);
      }
      current!.lines.add(line.startsWith('> ') ? line.substring(2) : '');
      continue;
    }
    if (line.startsWith('- ') || line.startsWith('* ')) {
      if (current?.kind != _Kind.bullet) {
        flush();
        current = _Block(_Kind.bullet);
      }
      current!.lines.add(line.substring(2));
      continue;
    }
    final numbered = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
    if (numbered != null) {
      if (current?.kind != _Kind.numbered) {
        flush();
        current = _Block(_Kind.numbered);
      }
      current!.lines.add(numbered.group(2) ?? '');
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    if (current?.kind != _Kind.paragraph) {
      flush();
      current = _Block(_Kind.paragraph);
    }
    current!.lines.add(line);
  }
  flush();
  return blocks;
}

// ---------------------------------------------------------------------------
// Inline widgets
// ---------------------------------------------------------------------------

/// An inline image from `![alt](url)`. Capped so a full-resolution screenshot
/// pasted into a comment doesn't take over the page; tap opens it full size.
class _MarkdownImage extends StatelessWidget {
  const _MarkdownImage({
    required this.url,
    required this.alt,
    required this.onOpen,
  });
  final String url;
  final String alt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320, maxWidth: 520),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                // Same-origin on web, so the session cookie rides along.
                errorBuilder: (context, _, _) => _ImagePlaceholder(
                  icon: Icons.broken_image_outlined,
                  label: alt.isEmpty ? url : alt,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const _ImagePlaceholder(
                    icon: Icons.image_outlined,
                    label: '',
                  );
                },
                semanticLabel: alt.isEmpty ? null : alt,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 160,
      height: 90,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.outline),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A resolved `@handle`, rendered as an avatar + name chip.
class _MentionChip extends StatelessWidget {
  const _MentionChip({required this.user});
  final UserRef user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.fromLTRB(2, 1, 6, 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(user: user, size: 14),
          const SizedBox(width: 4),
          Text(
            user.displayName,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
