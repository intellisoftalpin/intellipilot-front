import 'package:flutter/material.dart';

/// Block-level Markdown renderer with inline formatting. Handles the cases
/// that show up in IntelliPilot descriptions, comments and wiki pages without
/// pulling in a full markdown dependency: ATX headings (`#`, `##`, `###`),
/// bullet lists (`- `, `* `), numbered lists (`1. `), blockquotes (`> `),
/// fenced code blocks (triple backticks), and paragraphs.
///
/// Inline formatting is applied to every non-code block: `**bold**`,
/// `*italic*` / `_italic_`, `` `code` ``, and `[label](url)` links (links are
/// styled but not navigable — descriptions are read-only prose).
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(source);
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _renderBlock(context, b),
          ),
      ],
    );
  }

  Widget _renderBlock(BuildContext context, _Block b) {
    final theme = Theme.of(context);
    switch (b.kind) {
      case _Kind.h1:
        return _richLine(context, b.lines.join('\n'), theme.textTheme.headlineSmall);
      case _Kind.h2:
        return _richLine(context, b.lines.join('\n'), theme.textTheme.titleLarge);
      case _Kind.h3:
        return _richLine(context, b.lines.join('\n'), theme.textTheme.titleMedium);
      case _Kind.code:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
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
                    Expanded(child: _richLine(context, l, null)),
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
                    Expanded(child: _richLine(context, b.lines[i], null)),
                  ],
                ),
              ),
          ],
        );
      case _Kind.paragraph:
        return _richLine(context, b.lines.join('\n'), null);
    }
  }

  /// A selectable line/paragraph with inline markdown applied over [base].
  Widget _richLine(BuildContext context, String text, TextStyle? base) {
    final theme = Theme.of(context);
    final effective = base ?? DefaultTextStyle.of(context).style;
    return SelectableText.rich(
      TextSpan(style: effective, children: _inline(text, theme, effective)),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline formatting
// ---------------------------------------------------------------------------

class _Matcher {
  const _Matcher(this.re, this.build);
  final RegExp re;
  final InlineSpan Function(RegExpMatch m, ThemeData theme, TextStyle? base)
      build;
}

final _matchers = <_Matcher>[
  // `[label](url)` — styled, not navigable.
  _Matcher(
    RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'),
    (m, theme, base) => TextSpan(
      text: m.group(1),
      style: TextStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
    ),
  ),
  // `**bold**` — may contain further inline markup.
  _Matcher(
    RegExp(r'\*\*(.+?)\*\*'),
    (m, theme, base) => TextSpan(
      style: const TextStyle(fontWeight: FontWeight.w700),
      children: _inline(m.group(1)!, theme, base),
    ),
  ),
  // `` `code` `` — literal monospace.
  _Matcher(
    RegExp('`([^`]+)`'),
    (m, theme, base) => TextSpan(
      text: m.group(1),
      style: TextStyle(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
    ),
  ),
  // `*italic*`
  _Matcher(
    RegExp(r'\*(.+?)\*'),
    (m, theme, base) => TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      children: _inline(m.group(1)!, theme, base),
    ),
  ),
  // `_italic_`
  _Matcher(
    RegExp('_(.+?)_'),
    (m, theme, base) => TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      children: _inline(m.group(1)!, theme, base),
    ),
  ),
];

/// Tokenise [text] into styled spans, always emitting the earliest match so
/// overlapping markers (e.g. bold before italic) resolve predictably.
List<InlineSpan> _inline(String text, ThemeData theme, TextStyle? base) {
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
    spans.add(bestMatcher.build(best, theme, base));
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
