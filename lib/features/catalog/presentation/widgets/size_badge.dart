import 'package:flutter/material.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';

/// Renders a `size` taxonomy item (XS..XXL) as a badge whose font size and
/// padding scale with the taxonomy item's ordinal `value` (1..6), tinted by
/// the item's color. Used everywhere an issue size is shown.
class SizeBadge extends StatelessWidget {
  const SizeBadge({required this.item, super.key});

  /// The `size` taxonomy item backing this badge.
  final TaxonomyItem item;

  @override
  Widget build(BuildContext context) {
    // Ordinal drives the scale: XS(1) smallest → XXL(6) largest.
    final ordinal = (item.value ?? 1).clamp(1, 6).toDouble();
    final fontSize = 9.0 + ordinal; // 10..15
    final hPad = 4.0 + ordinal; // 5..10
    final color = _hexToColor(item.color);
    final foreground =
        color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        item.name,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: foreground.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return const Color(0xFF64748B);
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFF64748B) : Color(v);
}
