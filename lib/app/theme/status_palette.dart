import 'package:flutter/material.dart';

/// App-level status colours that are NOT taxonomy-driven. Used for "this is
/// done" / "this is blocked" affordances that don't have a server-supplied
/// hex (e.g. the connectivity banner, the demo-mode chip, dirty-form
/// indicators).
///
/// Taxonomy items still render in their own server-supplied colour — this
/// extension is for first-class app states only.
@immutable
class StatusPalette extends ThemeExtension<StatusPalette> {
  const StatusPalette({
    required this.todo,
    required this.inProgress,
    required this.inReview,
    required this.done,
    required this.blocked,
  });

  final Color todo;
  final Color inProgress;
  final Color inReview;
  final Color done;
  final Color blocked;

  static const StatusPalette light = StatusPalette(
    todo: Color(0xFF64748B), // slate-500
    inProgress: Color(0xFFF59E0B), // amber-500
    inReview: Color(0xFF0891B2), // cyan-600
    done: Color(0xFF10B981), // emerald-500
    blocked: Color(0xFFEF4444), // red-500
  );

  static const StatusPalette dark = StatusPalette(
    todo: Color(0xFF94A3B8), // slate-400
    inProgress: Color(0xFFFBBF24), // amber-400
    inReview: Color(0xFF22D3EE), // cyan-400
    done: Color(0xFF34D399), // emerald-400
    blocked: Color(0xFFF87171), // red-400
  );

  /// Resolve from a [BuildContext] — falls back to light if the theme wasn't
  /// extended (shouldn't happen since [AppTheme] always registers the
  /// extension).
  static StatusPalette of(BuildContext context) {
    return Theme.of(context).extension<StatusPalette>() ?? light;
  }

  @override
  StatusPalette copyWith({
    Color? todo,
    Color? inProgress,
    Color? inReview,
    Color? done,
    Color? blocked,
  }) =>
      StatusPalette(
        todo: todo ?? this.todo,
        inProgress: inProgress ?? this.inProgress,
        inReview: inReview ?? this.inReview,
        done: done ?? this.done,
        blocked: blocked ?? this.blocked,
      );

  @override
  StatusPalette lerp(ThemeExtension<StatusPalette>? other, double t) {
    if (other is! StatusPalette) return this;
    return StatusPalette(
      todo: Color.lerp(todo, other.todo, t)!,
      inProgress: Color.lerp(inProgress, other.inProgress, t)!,
      inReview: Color.lerp(inReview, other.inReview, t)!,
      done: Color.lerp(done, other.done, t)!,
      blocked: Color.lerp(blocked, other.blocked, t)!,
    );
  }
}
