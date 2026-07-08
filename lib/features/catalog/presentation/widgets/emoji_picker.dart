import 'package:flutter/material.dart';

/// A compact picker offering a curated set of emojis useful for tagging issue
/// types and priorities, plus a "none" choice. Selecting toggles the value.
class EmojiPicker extends StatelessWidget {
  const EmojiPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  /// Curated glyphs that read well at chip size for types and priorities.
  static const List<String> suggestions = [
    '🐞',
    '✨',
    '🧰',
    '🛠️',
    '❓',
    '💡',
    '🚀',
    '🔥',
    '⚙️',
    '🧪',
    '📝',
    '📌',
    '⬆️',
    '➡️',
    '⬇️',
    '⚠️',
    '❄️',
    '🔒',
    '📈',
    '🧹',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _Cell(
          label: '∅',
          isSelected: selected.isEmpty,
          onTap: () => onChanged(''),
        ),
        for (final e in suggestions)
          _Cell(label: e, isSelected: selected == e, onTap: () => onChanged(e)),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
        ),
        child: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
