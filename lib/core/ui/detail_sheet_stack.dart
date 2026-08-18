/// Bookkeeping for the stack of open detail slide-overs.
///
/// Detail sheets are ordinary `showGeneralDialog` routes, so layering them is
/// already native Navigator behaviour: a pushed route draws over the one
/// beneath, which stays mounted, and popping returns to it. What the Navigator
/// cannot answer is *what* is currently open, and that is what this registry
/// adds — two things depend on it:
///
///   * **Recursion.** An epic sheet lists its tasks; a task sheet links back to
///     its epic. Without a guard, tapping back and forth stacks panels for the
///     same two entities forever. [contains] lets a caller decline instead.
///   * **Layering.** [depth] tells a sheet how far in it is, so nested panels
///     can inset from the right edge and lighten their barrier rather than
///     burying the panel underneath and compounding the scrim to black.
///
/// This is deliberately a plain global rather than an inherited widget: dialog
/// routes are inserted into the Navigator's overlay, not below the widget that
/// opened them, so an ancestor lookup would not find anything.
library;

/// Identifies one open detail sheet. Two sheets are "the same" when they show
/// the same entity, which is exactly what the recursion guard needs to know.
typedef DetailSheetKey = String;

/// Build the key for an entity sheet, e.g. `issue:0192...`.
DetailSheetKey detailSheetKey(String kind, String id) => '$kind:$id';

/// The open detail sheets, outermost first.
///
/// Mutated only by the `show*DetailSheet` helpers, which pair every [push] with
/// a [pop] in a `finally` block — the route can be dismissed by the close
/// button, the barrier, Escape or the browser's Back, and only a `finally`
/// covers all four.
abstract final class DetailSheetStack {
  static final List<DetailSheetKey> _open = [];

  /// How many sheets are currently open. 0 means the next one is the first.
  static int get depth => _open.length;

  /// Whether [key] is already somewhere in the stack.
  static bool contains(DetailSheetKey key) => _open.contains(key);

  static void push(DetailSheetKey key) => _open.add(key);

  /// Remove [key]. Removes the last occurrence rather than the first so that
  /// unbalanced nesting can never strand an outer entry and lock it out for
  /// the rest of the session.
  static void pop(DetailSheetKey key) {
    final i = _open.lastIndexOf(key);
    if (i != -1) _open.removeAt(i);
  }

  /// Drop everything. For tests, and for a hard navigation that tears the
  /// whole stack down without popping each route.
  static void reset() => _open.clear();
}
