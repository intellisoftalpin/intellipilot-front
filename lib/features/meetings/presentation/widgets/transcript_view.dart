import 'package:flutter/material.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Where one search hit sits: line [line], characters [start]..[start]+len.
class TranscriptMatch {
  const TranscriptMatch(this.line, this.start);
  final int line;
  final int start;

  @override
  bool operator ==(Object other) =>
      other is TranscriptMatch && other.line == line && other.start == start;

  @override
  int get hashCode => Object.hash(line, start);

  @override
  String toString() => 'TranscriptMatch($line, $start)';
}

/// Case-insensitive, non-overlapping occurrences of [query] in [lines].
List<TranscriptMatch> findTranscriptMatches(List<String> lines, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <TranscriptMatch>[];
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    var from = 0;
    while (true) {
      final at = lower.indexOf(q, from);
      if (at < 0) break;
      out.add(TranscriptMatch(i, at));
      from = at + q.length;
    }
  }
  return out;
}

/// A read-only transcript with in-page search: every hit highlighted, the
/// current one stronger, and previous / next to walk through them.
///
/// Built line by line with a lazy list, since transcripts of long meetings run
/// to megabytes — one giant text span would lay out all of it on every frame.
class TranscriptView extends StatefulWidget {
  const TranscriptView({required this.text, super.key});

  final String text;

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  late List<String> _lines = widget.text.split('\n');
  List<TranscriptMatch> _matches = const [];
  int _current = 0;
  final Map<int, GlobalKey> _lineKeys = {};

  static const _estimatedLineHeight = 24.0;

  @override
  void didUpdateWidget(covariant TranscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _lines = widget.text.split('\n');
      _search(_query.text);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _search(String q) {
    setState(() {
      _matches = findTranscriptMatches(_lines, q);
      _current = 0;
      _lineKeys.clear();
    });
    if (_matches.isNotEmpty) _reveal();
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _current = (_current + delta) % _matches.length;
      if (_current < 0) _current += _matches.length;
    });
    _reveal();
  }

  /// Scrolls the current hit into view: jump near it by estimate so the lazy
  /// list builds that line, then align precisely once it exists.
  void _reveal() {
    final line = _matches[_current].line;
    if (_scroll.hasClients) {
      final ctx = _lineKeys[line]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.3);
        return;
      }
      final target = (line * _estimatedLineHeight).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(target);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _lineKeys[line]?.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx, alignment: 0.3);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final q = _query.text.trim();
    final byLine = <int, List<(int, bool)>>{};
    for (var i = 0; i < _matches.length; i++) {
      final m = _matches[i];
      (byLine[m.line] ??= []).add((m.start, i == _current));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('transcript-search'),
                  controller: _query,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: t.meetingTranscriptSearch,
                  ),
                  onChanged: _search,
                  onSubmitted: (_) => _step(1),
                ),
              ),
              const SizedBox(width: 8),
              if (q.isNotEmpty)
                Text(
                  _matches.isEmpty
                      ? t.meetingTranscriptNoMatches
                      : t.meetingTranscriptMatches(
                          _current + 1,
                          _matches.length,
                        ),
                  key: const Key('transcript-match-count'),
                  style: theme.textTheme.bodySmall,
                ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: t.meetingTranscriptPrevious,
                onPressed: _matches.isEmpty ? null : () => _step(-1),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: t.meetingTranscriptNext,
                onPressed: _matches.isEmpty ? null : () => _step(1),
              ),
            ],
          ),
        ),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final hits = byLine[i];
                final line = _lines[i];
                if (hits == null) {
                  return Text(line, style: theme.textTheme.bodyMedium);
                }
                return Text.rich(
                  key: _lineKeys.putIfAbsent(i, GlobalKey.new),
                  TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: _highlight(line, q.length, hits, theme),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<TextSpan> _highlight(
    String line,
    int len,
    List<(int, bool)> hits,
    ThemeData theme,
  ) {
    final spans = <TextSpan>[];
    var pos = 0;
    for (final (start, current) in hits) {
      if (start > pos) spans.add(TextSpan(text: line.substring(pos, start)));
      spans.add(
        TextSpan(
          text: line.substring(start, start + len),
          style: TextStyle(
            backgroundColor: current
                ? theme.colorScheme.primary
                : theme.colorScheme.primaryContainer,
            color: current
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
      );
      pos = start + len;
    }
    if (pos < line.length) spans.add(TextSpan(text: line.substring(pos)));
    return spans;
  }
}
