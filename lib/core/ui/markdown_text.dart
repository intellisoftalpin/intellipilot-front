import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';

/// Block-level Markdown renderer with inline formatting, covering modern
/// GitHub-flavoured markdown without pulling in a markdown dependency.
///
/// Blocks: ATX headings `#`…`######`, setext headings (`===` / `---`
/// underlines), bullet and numbered lists **with nesting**, task lists
/// (`- [ ]` / `- [x]`), blockquotes, fenced code (``` or ~~~, with an optional
/// language label), pipe tables with per-column alignment, horizontal rules,
/// footnote definitions, and paragraphs.
///
/// Inline: `**bold**`, `*italic*` / `_italic_`, `~~strikethrough~~`,
/// `` `code` ``, `[label](url)` links, `![alt](src)` images, `[^1]` footnote
/// references, `@mentions`, and bare `https://…` / `www.…` URLs.
///
/// Links are **navigable**: in-app targets (a `/projects/...` path, or an
/// absolute URL pointing at this same origin) route through go_router so the
/// SPA never reloads; everything else goes to [openExternalUrl]. Callers that
/// need different behaviour — the external documentation viewer resolves links
/// inside its path jail — supply [onLinkTap].
///
/// Stateful purely for gesture-recognizer lifetime — each link span owns a
/// [TapGestureRecognizer] that must be disposed or it leaks.
class MarkdownText extends StatefulWidget {
  const MarkdownText(
    this.source, {
    this.mentions = const {},
    this.onLinkTap,
    this.imageBuilder,
    this.onHeadings,
    this.anchorController,
    this.selectable = true,
    super.key,
  });

  final String source;

  /// Project members keyed by lowercase `@handle`, used to render `@mentions`
  /// as chips. Unknown handles stay plain text — a mention of someone who left
  /// the project shouldn't turn into a broken widget.
  final Map<String, UserRef> mentions;

  /// Overrides link navigation. Receives the raw href exactly as written in
  /// the source, so the caller can resolve it in whatever space it belongs to.
  /// When null, links route in-app or open externally as described above.
  final void Function(String href)? onLinkTap;

  /// Overrides how an inline image is rendered. Receives the raw `src` and
  /// `alt`. Returning null falls back to the default network image. Used by
  /// the documentation viewer, which must fetch blobs through the authorized
  /// API rather than by URL.
  final Widget? Function(String src, String alt)? imageBuilder;

  /// Reports the headings found in the source, in document order, after each
  /// parse. Backs the table of contents in the documentation viewer.
  final void Function(List<MarkdownHeading> headings)? onHeadings;

  /// Lets a table of contents outside this widget scroll it to a heading.
  final MarkdownAnchorController? anchorController;

  /// Wrap the output in a [SelectionArea] so the reader can select and copy.
  ///
  /// Set false where the rendered text sits inside a click-to-edit surface:
  /// the selection area claims taps to place a caret, which otherwise swallows
  /// every click on the text and leaves only the surrounding padding working.
  final bool selectable;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

/// One heading from a parsed document.
@immutable
class MarkdownHeading {
  const MarkdownHeading({
    required this.level,
    required this.text,
    required this.anchor,
  });

  /// 1–6.
  final int level;
  final String text;

  /// Slugified form, matching the `#fragment` a link would use.
  final String anchor;

  @override
  bool operator ==(Object other) =>
      other is MarkdownHeading &&
      other.level == level &&
      other.text == text &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(level, text, anchor);
}

/// Scrolls a rendered document to one of its headings.
///
/// The renderer owns the heading keys — they are created during build and
/// replaced on every parse — so a table of contents outside the widget needs a
/// handle rather than keys of its own. Attach one instance to one
/// [MarkdownText]; it goes inert if that widget is gone.
class MarkdownAnchorController {
  void Function(String anchor)? _scrollTo;

  /// Scroll to the heading whose slug is [anchor]. A no-op when the anchor is
  /// unknown or no document is attached.
  void scrollTo(String anchor) => _scrollTo?.call(anchor);

  bool get isAttached => _scrollTo != null;
}

/// GitHub-compatible heading slug: lowercased, punctuation dropped, spaces to
/// hyphens. Shared by the renderer and by anything that links to a heading.
String markdownAnchor(String text) {
  final lower = text.toLowerCase().trim();
  final cleaned = lower.replaceAll(RegExp(r'[^\w\s-]'), '');
  return cleaned.replaceAll(RegExp(r'[\s_]+'), '-');
}

class _MarkdownTextState extends State<MarkdownText> {
  /// Recognizers backing the spans of the CURRENT build. Replaced wholesale on
  /// every rebuild; the previous generation is disposed one frame later so a
  /// recognizer never dies while it is still dispatching the tap that caused
  /// the rebuild.
  List<TapGestureRecognizer> _recognizers = [];

  /// Anchors of headings rendered in this build, so a `#fragment` link can
  /// scroll to one.
  final Map<String, GlobalKey> _anchors = {};

  List<MarkdownHeading> _reported = const [];

  @override
  void initState() {
    super.initState();
    widget.anchorController?._scrollTo = _scrollToAnchor;
  }

  @override
  void didUpdateWidget(MarkdownText old) {
    super.didUpdateWidget(old);
    if (!identical(old.anchorController, widget.anchorController)) {
      old.anchorController?._scrollTo = null;
      widget.anchorController?._scrollTo = _scrollToAnchor;
    }
  }

  @override
  void dispose() {
    widget.anchorController?._scrollTo = null;
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = [];
    super.dispose();
  }

  /// Routes a tapped link. In-app paths keep the SPA alive; anything else is
  /// handed to the platform.
  void _openLink(String rawUrl) {
    // An intra-document heading link never leaves the page.
    if (rawUrl.startsWith('#')) {
      _scrollToAnchor(rawUrl.substring(1));
      return;
    }
    if (widget.onLinkTap != null) {
      widget.onLinkTap!(rawUrl);
      return;
    }
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

  void _scrollToAnchor(String anchor) {
    final key = _anchors[markdownAnchor(anchor)];
    final target = key?.currentContext;
    if (target == null) return;
    unawaitedEnsureVisible(target);
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
    _anchors.clear();

    final ctx = _InlineCtx(
      theme: Theme.of(context),
      onTapUrl: _openLink,
      sink: _recognizers,
      mentions: widget.mentions,
      imageBuilder: widget.imageBuilder,
    );

    _reportHeadings(blocks);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _renderBlock(context, ctx, b),
          ),
      ],
    );
    if (!widget.selectable) return body;
    // One SelectionArea over all blocks: a single drag (or Ctrl/Cmd+A) selects
    // the whole text across paragraphs, lists, tables and code — per-block
    // selectable widgets would each form their own selection island. Tap
    // recognizers on link spans still fire inside it: RenderParagraph
    // hit-tests them directly.
    return SelectionArea(child: body);
  }

  /// Hand the caller the heading outline once per parse, after the frame so a
  /// listener may safely rebuild.
  void _reportHeadings(List<_Block> blocks) {
    final callback = widget.onHeadings;
    if (callback == null) return;
    final found = <MarkdownHeading>[];
    for (final b in blocks) {
      final level = _headingLevel(b.kind);
      if (level == null) continue;
      final text = b.lines.join(' ').trim();
      found.add(
        MarkdownHeading(
          level: level,
          text: text,
          anchor: markdownAnchor(text),
        ),
      );
    }
    if (_listEquals(found, _reported)) return;
    _reported = found;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(found);
    });
  }

  static bool _listEquals(List<MarkdownHeading> a, List<MarkdownHeading> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int? _headingLevel(_Kind k) => switch (k) {
    _Kind.h1 => 1,
    _Kind.h2 => 2,
    _Kind.h3 => 3,
    _Kind.h4 => 4,
    _Kind.h5 => 5,
    _Kind.h6 => 6,
    _ => null,
  };

  Widget _renderBlock(BuildContext context, _InlineCtx ctx, _Block b) {
    final theme = Theme.of(context);
    switch (b.kind) {
      case _Kind.h1:
      case _Kind.h2:
      case _Kind.h3:
      case _Kind.h4:
      case _Kind.h5:
      case _Kind.h6:
        return _heading(context, ctx, b, theme);
      case _Kind.code:
        return _CodeBlock(lines: b.lines, language: b.info);
      case _Kind.rule:
        return Divider(color: theme.colorScheme.outlineVariant, height: 24);
      case _Kind.table:
        return _MarkdownTable(
          rows: b.rows,
          aligns: b.aligns,
          renderCell: (text, style) => _richLine(context, ctx, text, style),
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
      case _Kind.numbered:
        return _list(context, ctx, b, theme);
      case _Kind.footnote:
        return _Footnotes(
          items: b.items,
          renderText: (text) =>
              _richLine(context, ctx, text, theme.textTheme.bodySmall),
        );
      case _Kind.paragraph:
        return _richLine(context, ctx, b.lines.join('\n'), null);
    }
  }

  Widget _heading(
    BuildContext context,
    _InlineCtx ctx,
    _Block b,
    ThemeData theme,
  ) {
    final text = b.lines.join('\n');
    final style = switch (b.kind) {
      _Kind.h1 => theme.textTheme.headlineSmall,
      _Kind.h2 => theme.textTheme.titleLarge,
      _Kind.h3 => theme.textTheme.titleMedium,
      _Kind.h4 => theme.textTheme.titleSmall,
      _Kind.h5 => theme.textTheme.labelLarge,
      _ => theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    };
    // A key per heading so an intra-document `#anchor` link can scroll to it.
    final key = _anchors.putIfAbsent(markdownAnchor(text), GlobalKey.new);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 8),
      child: _richLine(context, ctx, text, style),
    );
  }

  /// A list, rendered flat with per-item indentation. Nesting is expressed by
  /// [_Item.depth] rather than by nested widgets so one [SelectionArea] drag
  /// still selects across the whole list.
  Widget _list(
    BuildContext context,
    _InlineCtx ctx,
    _Block b,
    ThemeData theme,
  ) {
    // Numbering restarts per depth, so a nested list counts from 1.
    final counters = <int, int>{};
    var lastDepth = -1;
    final rows = <Widget>[];
    for (final item in b.items) {
      if (item.depth > lastDepth) counters[item.depth] = 0;
      counters[item.depth] = (counters[item.depth] ?? 0) + 1;
      lastDepth = item.depth;

      final Widget marker;
      if (item.checked != null) {
        marker = Padding(
          padding: const EdgeInsets.only(top: 2, right: 6),
          child: Icon(
            item.checked!
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            size: 16,
            color: item.checked!
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        );
      } else if (b.kind == _Kind.numbered) {
        marker = Text('${counters[item.depth]}.  ');
      } else {
        // Alternate the glyph by depth, as every markdown renderer does.
        marker = Text('${_bulletGlyph(item.depth)}  ');
      }

      rows.add(
        Padding(
          padding: EdgeInsets.only(
            left: 16.0 * item.depth,
            top: 2,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              marker,
              Expanded(
                child: _richLine(
                  context,
                  ctx,
                  item.text,
                  item.checked ?? false
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  static String _bulletGlyph(int depth) => switch (depth % 3) {
    0 => '•',
    1 => '◦',
    _ => '▪',
  };

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

/// Scroll a heading into view without awaiting, so callers stay synchronous.
void unawaitedEnsureVisible(BuildContext target) {
  Scrollable.ensureVisible(
    target,
    duration: const Duration(milliseconds: 250),
    alignment: 0.1,
  );
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
    this.imageBuilder,
  });

  final ThemeData theme;
  final void Function(String url) onTapUrl;
  final List<TapGestureRecognizer> sink;
  final Map<String, UserRef> mentions;
  final Widget? Function(String src, String alt)? imageBuilder;

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
    (m, ctx, base) {
      final src = m.group(2)!;
      final alt = m.group(1) ?? '';
      final custom = ctx.imageBuilder?.call(src, alt);
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child:
            custom ??
            _MarkdownImage(
              url: ctx.absolute(src),
              alt: alt,
              onOpen: () => ctx.onTapUrl(src),
            ),
      );
    },
  ),
  // `[^1]` — a footnote reference, rendered as a superscript marker. Must
  // precede the link matcher, whose `[..](..)` shape it would otherwise
  // partially match.
  _Matcher(
    RegExp(r'\[\^([^\]]+)\]'),
    (m, ctx, base) => WidgetSpan(
      alignment: PlaceholderAlignment.top,
      child: Transform.translate(
        offset: const Offset(0, -2),
        child: Text(
          m.group(1)!,
          style: ctx.theme.textTheme.labelSmall?.copyWith(
            color: ctx.theme.colorScheme.primary,
            fontSize: 10,
          ),
        ),
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
  // `~~strikethrough~~`
  _Matcher(
    RegExp('~~(.+?)~~'),
    (m, ctx, base) => TextSpan(
      style: const TextStyle(decoration: TextDecoration.lineThrough),
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
  // `<https://…>` — an autolink in angle brackets.
  _Matcher(
    RegExp(r'<((?:https?://|mailto:)[^>\s]+)>'),
    (m, ctx, base) => _linkSpan(m.group(1)!, m.group(1)!, ctx),
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

enum _Kind {
  h1,
  h2,
  h3,
  h4,
  h5,
  h6,
  paragraph,
  bullet,
  numbered,
  quote,
  code,
  table,
  rule,
  footnote,
}

/// Column alignment declared by a table's delimiter row.
enum _Align { left, center, right }

/// One entry of a list or footnote block.
class _Item {
  _Item(this.text, this.depth, {this.checked, this.label = ''});
  final String text;

  /// Nesting level, 0 for a top-level item.
  final int depth;

  /// Non-null for a task-list item: whether its box is ticked.
  final bool? checked;

  /// Footnote label, for [_Kind.footnote] blocks.
  final String label;
}

class _Block {
  _Block(this.kind, {this.info = ''});
  final _Kind kind;

  /// Fence info string, e.g. the language after ```.
  final String info;

  final List<String> lines = [];
  final List<_Item> items = [];
  final List<List<String>> rows = [];
  final List<_Align> aligns = [];
}

final _fenceRe = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*(\S*)\s*$');
final _atxRe = RegExp(r'^(#{1,6})\s+(.*)$');
final _ruleRe = RegExp(r'^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$');
final _bulletRe = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _numberedRe = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
final _taskRe = RegExp(r'^\[([ xX])\]\s+(.*)$');
final _footnoteRe = RegExp(r'^\[\^([^\]]+)\]:\s*(.*)$');
final _tableDelimRe = RegExp(
  r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$',
);
final _setextH1Re = RegExp(r'^\s{0,3}=+\s*$');
final _setextH2Re = RegExp(r'^\s{0,3}-{2,}\s*$');

/// Indentation, in spaces, treating a tab as four.
int _indentOf(String prefix) {
  var n = 0;
  for (final c in prefix.split('')) {
    n += c == '\t' ? 4 : 1;
  }
  return n;
}

/// Split one pipe-table row into trimmed cells, dropping the optional leading
/// and trailing pipes.
List<String> _tableCells(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((c) => c.trim()).toList();
}

List<_Align> _tableAligns(String delimiter) => _tableCells(delimiter).map((c) {
  final left = c.startsWith(':');
  final right = c.endsWith(':');
  if (left && right) return _Align.center;
  if (right) return _Align.right;
  return _Align.left;
}).toList();

List<_Block> _parse(String source) {
  final blocks = <_Block>[];
  final raw = source.split('\n');
  _Block? current;

  void flush() {
    final c = current;
    if (c != null &&
        (c.lines.isNotEmpty || c.items.isNotEmpty || c.rows.isNotEmpty)) {
      blocks.add(c);
    }
    current = null;
  }

  var i = 0;
  while (i < raw.length) {
    final line = raw[i];

    // --- fenced code, which suspends every other rule until it closes ------
    final fence = _fenceRe.firstMatch(line);
    if (fence != null) {
      flush();
      final marker = fence.group(1)!;
      final block = _Block(_Kind.code, info: fence.group(2) ?? '');
      i++;
      while (i < raw.length) {
        final inner = raw[i];
        final closing = _fenceRe.firstMatch(inner);
        // Only a fence of the same character (and at least as long) closes.
        if (closing != null &&
            closing.group(1)![0] == marker[0] &&
            closing.group(1)!.length >= marker.length) {
          i++;
          break;
        }
        block.lines.add(inner);
        i++;
      }
      // An empty fenced block is still a block: it shows the reader that the
      // author left one there.
      blocks.add(block);
      continue;
    }

    // --- tables: a header row followed by a delimiter row ------------------
    if (line.contains('|') &&
        i + 1 < raw.length &&
        _tableDelimRe.hasMatch(raw[i + 1]) &&
        raw[i + 1].contains('-')) {
      flush();
      final block = _Block(_Kind.table);
      block.rows.add(_tableCells(line));
      block.aligns.addAll(_tableAligns(raw[i + 1]));
      i += 2;
      while (i < raw.length &&
          raw[i].contains('|') &&
          raw[i].trim().isNotEmpty) {
        block.rows.add(_tableCells(raw[i]));
        i++;
      }
      blocks.add(block);
      continue;
    }

    // --- horizontal rule ---------------------------------------------------
    // Checked before the setext-h2 rule, which shares the `---` spelling: a
    // rule needs no preceding paragraph, an underline does.
    if (_ruleRe.hasMatch(line) && current?.kind != _Kind.paragraph) {
      flush();
      blocks.add(_Block(_Kind.rule)..lines.add(''));
      i++;
      continue;
    }

    // --- setext headings: an underlined paragraph --------------------------
    if (current?.kind == _Kind.paragraph &&
        current!.lines.isNotEmpty &&
        (_setextH1Re.hasMatch(line) || _setextH2Re.hasMatch(line))) {
      final text = current!.lines.removeLast();
      // Anything before the underlined line stays a paragraph of its own.
      flush();
      final kind = _setextH1Re.hasMatch(line) ? _Kind.h1 : _Kind.h2;
      blocks.add(_Block(kind)..lines.add(text));
      i++;
      continue;
    }

    // --- ATX headings ------------------------------------------------------
    final atx = _atxRe.firstMatch(line);
    if (atx != null) {
      flush();
      final level = atx.group(1)!.length;
      final kind = switch (level) {
        1 => _Kind.h1,
        2 => _Kind.h2,
        3 => _Kind.h3,
        4 => _Kind.h4,
        5 => _Kind.h5,
        _ => _Kind.h6,
      };
      // Closing hashes (`## Title ##`) are decoration, not content.
      final text = atx.group(2)!.replaceFirst(RegExp(r'\s*#*\s*$'), '');
      blocks.add(_Block(kind)..lines.add(text));
      i++;
      continue;
    }

    // --- footnote definitions ---------------------------------------------
    final footnote = _footnoteRe.firstMatch(line);
    if (footnote != null) {
      if (current?.kind != _Kind.footnote) {
        flush();
        current = _Block(_Kind.footnote);
      }
      current!.items.add(
        _Item(footnote.group(2) ?? '', 0, label: footnote.group(1)!),
      );
      i++;
      continue;
    }

    // --- blockquote --------------------------------------------------------
    if (line.startsWith('> ') || line.trim() == '>') {
      if (current?.kind != _Kind.quote) {
        flush();
        current = _Block(_Kind.quote);
      }
      current!.lines.add(line.startsWith('> ') ? line.substring(2) : '');
      i++;
      continue;
    }

    // --- lists, with nesting and task boxes --------------------------------
    final bullet = _bulletRe.firstMatch(line);
    final numbered = bullet == null ? _numberedRe.firstMatch(line) : null;
    if (bullet != null || numbered != null) {
      final kind = bullet != null ? _Kind.bullet : _Kind.numbered;
      final indent = _indentOf((bullet ?? numbered)!.group(1)!);
      var text = bullet != null ? bullet.group(2)! : numbered!.group(3)!;
      bool? checked;
      final task = _taskRe.firstMatch(text);
      if (task != null) {
        checked = task.group(1)!.toLowerCase() == 'x';
        text = task.group(2)!;
      }
      // A run of list items is one block even when bullets and numbers
      // alternate by depth; the kind of the first item names the block.
      if (current?.kind != _Kind.bullet && current?.kind != _Kind.numbered) {
        flush();
        current = _Block(kind);
      }
      // Two spaces of indent is one level, which covers both the 2-space and
      // 4-space conventions without guessing.
      current!.items.add(_Item(text, indent ~/ 2, checked: checked));
      i++;
      continue;
    }

    // --- blank line: ends whatever was open --------------------------------
    if (line.trim().isEmpty) {
      flush();
      i++;
      continue;
    }

    // --- paragraph ---------------------------------------------------------
    if (current?.kind != _Kind.paragraph) {
      flush();
      current = _Block(_Kind.paragraph);
    }
    current!.lines.add(line);
    i++;
  }
  flush();
  return blocks;
}

// ---------------------------------------------------------------------------
// Block widgets
// ---------------------------------------------------------------------------

/// A fenced code block. Scrolls horizontally rather than wrapping, so
/// indentation-sensitive content stays readable.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.lines, required this.language});
  final List<String> lines;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (language.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                language,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                lines.join('\n'),
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A GFM pipe table. Wrapped in a horizontal scroller so a wide table never
/// forces the whole page to scroll sideways.
class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({
    required this.rows,
    required this.aligns,
    required this.renderCell,
  });

  final List<List<String>> rows;
  final List<_Align> aligns;
  final Widget Function(String text, TextStyle? style) renderCell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();
    // Ragged rows are common in hand-written markdown; pad to the widest.
    final columns = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

    Alignment alignOf(int col) =>
        switch (col < aligns.length ? aligns[col] : _Align.left) {
          _Align.left => Alignment.centerLeft,
          _Align.center => Alignment.center,
          _Align.right => Alignment.centerRight,
        };

    TableRow row(List<String> cells, {required bool header}) => TableRow(
      decoration: header
          ? BoxDecoration(color: theme.colorScheme.surfaceContainerHighest)
          : null,
      children: [
        for (var c = 0; c < columns; c++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Align(
              alignment: alignOf(c),
              child: renderCell(
                c < cells.length ? cells[c] : '',
                header
                    ? theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
          children: [
            row(rows.first, header: true),
            for (final r in rows.skip(1)) row(r, header: false),
          ],
        ),
      ),
    );
  }
}

/// Footnote definitions, collected under a rule at the point they appear.
class _Footnotes extends StatelessWidget {
  const _Footnotes({required this.items, required this.renderText});
  final List<_Item> items;
  final Widget Function(String text) renderText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: theme.colorScheme.outlineVariant, height: 20),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    item.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(child: renderText(item.text)),
              ],
            ),
          ),
      ],
    );
  }
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
                errorBuilder: (context, _, _) => MarkdownImagePlaceholder(
                  icon: Icons.broken_image_outlined,
                  label: alt.isEmpty ? url : alt,
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const MarkdownImagePlaceholder(
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

/// Stand-in shown while an inline image loads, or when it cannot be shown at
/// all. Public so a custom [MarkdownText.imageBuilder] can match the look.
class MarkdownImagePlaceholder extends StatelessWidget {
  const MarkdownImagePlaceholder({
    required this.icon,
    required this.label,
    this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final box = Container(
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
    if (onTap == null) return box;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: box,
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
