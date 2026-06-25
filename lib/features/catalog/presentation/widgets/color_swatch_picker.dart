import 'package:flutter/material.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';

/// A flat grid of colour swatches drawn from [ColorPalette.swatches]. The
/// surrounding form owns the selection and is notified through [onChanged];
/// the widget is purely presentational.
class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({
    required this.selectedHex,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String selectedHex;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selectedNorm = selectedHex.toLowerCase();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in ColorPalette.swatches)
          _Swatch(
            hex: hex,
            selected: hex.toLowerCase() == selectedNorm,
            enabled: enabled,
            onTap: () => onChanged(hex),
          ),
      ],
    );
  }
}

/// Renders a single colour chip as a circle (or a faint placeholder for
/// missing/empty colour).
class HexColorDot extends StatelessWidget {
  const HexColorDot({required this.hex, this.size = 14, super.key});
  final String hex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color =
        _parseHex(hex) ?? Theme.of(context).colorScheme.outlineVariant;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.hex,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(hex) ?? Colors.grey;
    return Tooltip(
      message: hex,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 22,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 3,
                  )
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : null,
        ),
      ),
    );
  }
}

Color? _parseHex(String hex) {
  var trimmed = hex.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('#')) trimmed = trimmed.substring(1);
  if (trimmed.length == 6) trimmed = 'ff$trimmed';
  if (trimmed.length != 8) return null;
  final parsed = int.tryParse(trimmed, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
