import 'package:flutter/material.dart';

/// Tiny block-level Markdown renderer. Handles the cases that show up in
/// IntelliPilot comments and wiki pages without pulling in a full markdown
/// dependency: ATX headings (`#`, `##`, `###`), bullet lists (`- `, `* `),
/// numbered lists (`1. `), code blocks (triple backticks), and paragraphs.
/// Inline formatting (`**bold**`, `_italic_`, links) is intentionally
/// out-of-scope — switch to `flutter_html` rendering the server-supplied
/// `body_html` when richer formatting is needed.
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
        return SelectableText(b.lines.join('\n'),
            style: theme.textTheme.headlineSmall);
      case _Kind.h2:
        return SelectableText(b.lines.join('\n'),
            style: theme.textTheme.titleLarge);
      case _Kind.h3:
        return SelectableText(b.lines.join('\n'),
            style: theme.textTheme.titleMedium);
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
                    Expanded(child: SelectableText(l)),
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
                    Expanded(child: SelectableText(b.lines[i])),
                  ],
                ),
              ),
          ],
        );
      case _Kind.paragraph:
        return SelectableText(b.lines.join('\n'));
    }
  }
}

enum _Kind { h1, h2, h3, paragraph, bullet, numbered, code }

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
