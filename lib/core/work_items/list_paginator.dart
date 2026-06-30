import 'package:flutter/material.dart';

/// A compact, modern paginator: an "X–Y of N" count, a rows-per-page selector,
/// and numbered page buttons (with ellipses for large ranges). Stateless — the
/// owner holds the current page/size and reacts to [onPage] / [onPageSize].
class ListPaginator extends StatelessWidget {
  const ListPaginator({
    required this.total,
    required this.pageIndex,
    required this.pageCount,
    required this.pageSize,
    required this.pageSizeOptions,
    required this.onPage,
    required this.onPageSize,
    super.key,
  });

  final int total;

  /// 0-based current page.
  final int pageIndex;
  final int pageCount;
  final int pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  /// Page indices to render, `null` marking an ellipsis gap.
  static List<int?> _pages(int current, int count) {
    final wanted = <int>{
      0,
      count - 1,
      current - 1,
      current,
      current + 1,
    }.where((p) => p >= 0 && p < count).toList()..sort();
    final out = <int?>[];
    int? prev;
    for (final p in wanted) {
      if (prev != null && p - prev > 1) out.add(null);
      out.add(p);
      prev = p;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = total == 0 ? 0 : pageIndex * pageSize + 1;
    final end = ((pageIndex + 1) * pageSize).clamp(0, total);

    return Material(
      elevation: 0,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              Text(
                '$start–$end of $total',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Text('Rows:', style: theme.textTheme.bodySmall),
              const SizedBox(width: 6),
              DropdownButton<int>(
                value: pageSizeOptions.contains(pageSize)
                    ? pageSize
                    : pageSizeOptions.first,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final s in pageSizeOptions)
                    DropdownMenuItem(value: s, child: Text('$s')),
                ],
                onChanged: (v) {
                  if (v != null) onPageSize(v);
                },
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous',
                visualDensity: VisualDensity.compact,
                onPressed: pageIndex > 0 ? () => onPage(pageIndex - 1) : null,
              ),
              for (final p in _pages(pageIndex, pageCount))
                if (p == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…'),
                  )
                else
                  _PageButton(
                    label: '${p + 1}',
                    selected: p == pageIndex,
                    onTap: () => onPage(p),
                  ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next',
                visualDensity: VisualDensity.compact,
                onPressed: pageIndex < pageCount - 1
                    ? () => onPage(pageIndex + 1)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 32,
        width: 32,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 32),
            backgroundColor: selected
                ? theme.colorScheme.primary
                : Colors.transparent,
            foregroundColor: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: selected ? null : onTap,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}
