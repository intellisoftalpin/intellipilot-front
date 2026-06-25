import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/palette/presentation/cmd_k_dialog.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// One shortcut definition. Rendered by the help dialog from the same
/// registry the listener uses, so the docs can't drift from behaviour.
class ShortcutDef {
  const ShortcutDef({
    required this.keys,
    required this.descriptionKey,
  });

  /// Human-readable keystroke (e.g. `"Ctrl+K"` or `"g p"`). Localisation
  /// would split this further; for now the binding is English-only.
  final String keys;

  /// ARB lookup function — kept as a getter so changes to AppLocalizations
  /// don't require a rebuild of the registry.
  final String Function(AppLocalizations t) descriptionKey;
}

final List<ShortcutDef> kShortcutRegistry = [
  ShortcutDef(
    keys: 'Ctrl/Cmd+K',
    descriptionKey: (t) => t.shortcutPaletteDescription,
  ),
  ShortcutDef(
    keys: '?',
    descriptionKey: (t) => t.shortcutHelpDescription,
  ),
  ShortcutDef(
    keys: 'g p',
    descriptionKey: (t) => t.shortcutGoProjectsDescription,
  ),
  ShortcutDef(
    keys: 'g s',
    descriptionKey: (t) => t.shortcutGoSettingsDescription,
  ),
  ShortcutDef(
    keys: 'g b',
    descriptionKey: (t) => t.shortcutGoBoardDescription,
  ),
  ShortcutDef(
    keys: 'g w',
    descriptionKey: (t) => t.shortcutGoWikiDescription,
  ),
];

/// Wraps the routed child in a single keyboard listener. The listener is
/// gated on focused-text-field state so typing in a comment/title doesn't
/// fire `g p` etc.
class GlobalShortcutsShell extends StatefulWidget {
  const GlobalShortcutsShell({required this.child, super.key});
  final Widget child;

  @override
  State<GlobalShortcutsShell> createState() => _GlobalShortcutsShellState();
}

class _GlobalShortcutsShellState extends State<GlobalShortcutsShell> {
  /// True while the leading `g` of a `g X` chord has been typed and we're
  /// waiting for the second key. Reset after ~700ms.
  bool _awaitingChord = false;
  DateTime _chordStart = DateTime.fromMillisecondsSinceEpoch(0);
  static const _chordWindow = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Skip if a text field is focused — let it consume the keystroke.
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.widget is EditableText) return false;
    final isEditable =
        focus != null &&
        focus.context != null &&
        _isTextEditingContext(focus.context!);
    if (isEditable) return false;

    final ctx = _navContext();
    if (ctx == null) return false;

    final isCmdK =
        (event.logicalKey == LogicalKeyboardKey.keyK) &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
    if (isCmdK) {
      _awaitingChord = false;
      unawaited(_openPalette(ctx));
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.slash &&
        HardwareKeyboard.instance.isShiftPressed) {
      _awaitingChord = false;
      unawaited(_showHelp(ctx));
      return true;
    }

    // `g X` chord handling.
    if (_awaitingChord) {
      final age = DateTime.now().difference(_chordStart);
      if (age > _chordWindow) {
        _awaitingChord = false;
        return false;
      }
      _awaitingChord = false;
      switch (event.logicalKey.keyLabel.toLowerCase()) {
        case 'p':
          ctx.go(Routes.projects);
          return true;
        case 's':
          ctx.go(Routes.settings);
          return true;
        case 'b':
          final pid = _projectIdFromRoute(ctx);
          if (pid != null) {
            ctx.go(Routes.projectBoardFor(pid));
            return true;
          }
        case 'w':
          final pid = _projectIdFromRoute(ctx);
          if (pid != null) {
            ctx.go(Routes.projectWikiFor(pid));
            return true;
          }
      }
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyG) {
      _awaitingChord = true;
      _chordStart = DateTime.now();
      return true;
    }
    return false;
  }

  bool _isTextEditingContext(BuildContext ctx) {
    var found = false;
    ctx.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  BuildContext? _navContext() {
    // Prefer the deepest Navigator context — that's the one carrying the
    // current route.
    final state = Navigator.maybeOf(context);
    return state?.context;
  }

  String? _projectIdFromRoute(BuildContext ctx) {
    final uri = GoRouterState.of(ctx).uri;
    final segs = uri.pathSegments;
    final i = segs.indexOf('projects');
    if (i >= 0 && segs.length > i + 1) return segs[i + 1];
    return null;
  }

  Future<void> _openPalette(BuildContext ctx) {
    return openCmdKDialog(ctx, activeProjectId: _projectIdFromRoute(ctx));
  }

  Future<void> _showHelp(BuildContext ctx) {
    final t = AppLocalizations.of(ctx);
    return showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(t.shortcutHelpTitle),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in kShortcutRegistry)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(ctx).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s.keys,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(s.descriptionKey(t))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(t.actionDone),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
