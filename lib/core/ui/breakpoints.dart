import 'package:flutter/widgets.dart';

/// Material 3 / Material Design 3 breakpoints. Pages consult [Breakpoints.of]
/// rather than hard-coded pixel values so the rules stay consistent.
enum Breakpoint {
  /// Phone-sized (`< 600 px`).
  compact,

  /// Small tablet / split-view (`600–839 px`).
  medium,

  /// Large tablet / desktop (`≥ 840 px`).
  expanded,
}

extension BreakpointExt on Breakpoint {
  bool get isCompact => this == Breakpoint.compact;
  bool get isAtLeastMedium =>
      this == Breakpoint.medium || this == Breakpoint.expanded;
  bool get isExpanded => this == Breakpoint.expanded;
}

abstract final class Breakpoints {
  static const double compactMax = 600;
  static const double mediumMax = 840;

  static Breakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < compactMax) return Breakpoint.compact;
    if (width < mediumMax) return Breakpoint.medium;
    return Breakpoint.expanded;
  }
}

/// Convenience: picks between a [compact]/[medium]/[expanded] value based on
/// the current breakpoint. Useful for sizing constants (padding, max widths)
/// without writing the `switch` at every call site.
T responsiveValue<T>(
  BuildContext context, {
  required T compact,
  T? medium,
  T? expanded,
}) {
  final bp = Breakpoints.of(context);
  return switch (bp) {
    Breakpoint.compact => compact,
    Breakpoint.medium => medium ?? compact,
    Breakpoint.expanded => expanded ?? medium ?? compact,
  };
}
