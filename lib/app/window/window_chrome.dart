import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellipilot/app/window/desktop_window.dart';
import 'package:window_manager/window_manager.dart';

/// The window buttons for one side of the title bar, drawn by the app.
///
/// Renders nothing unless [DesktopWindow.active], so title bars can include it
/// unconditionally.
class WindowControls extends StatefulWidget {
  const WindowControls.left({super.key}) : _left = true;
  const WindowControls.right({super.key}) : _left = false;

  final bool _left;

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _maximized = false;

  List<WindowButton> get _buttons => !DesktopWindow.active
      ? const []
      : widget._left
      ? DesktopWindow.layout.left
      : DesktopWindow.layout.right;

  @override
  void initState() {
    super.initState();
    if (_buttons.contains(WindowButton.maximize)) {
      windowManager.addListener(this);
      unawaited(
        windowManager.isMaximized().then((m) {
          if (mounted) setState(() => _maximized = m);
        }),
      );
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final buttons = _buttons;
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, b) in buttons.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            switch (b) {
              WindowButton.minimize => _CaptionButton(
                icon: Icons.minimize,
                onPressed: () => unawaited(windowManager.minimize()),
              ),
              WindowButton.maximize => _CaptionButton(
                icon: _maximized ? Icons.filter_none : Icons.crop_square,
                onPressed: () => unawaited(_toggleMaximize()),
              ),
              WindowButton.close => _CaptionButton(
                icon: Icons.close,
                onPressed: () => unawaited(windowManager.close()),
              ),
            },
          ],
        ],
      ),
    );
  }
}

Future<void> _toggleMaximize() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// A round, GNOME-style title bar button.
class _CaptionButton extends StatelessWidget {
  const _CaptionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 24,
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Icon(icon, size: 14, color: scheme.onSurface),
        ),
      ),
    );
  }
}

/// Moves the window when dragged and maximizes/restores it on double-click.
///
/// Meant to sit *behind* a title bar's contents: a click on a link or button
/// never reaches it, so it never competes with them for the gesture — which
/// also keeps its double-tap from delaying their taps.
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.active) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => unawaited(windowManager.startDragging()),
      onDoubleTap: () => unawaited(_toggleMaximize()),
    );
  }
}

/// Marks its subtree as the window's title bar while mounted, so
/// [BareWindowFrame] knows not to draw its own.
class TitleBarClaim extends StatefulWidget {
  const TitleBarClaim({required this.child, super.key});

  final Widget child;

  static final _claims = ValueNotifier<int>(0);

  @override
  State<TitleBarClaim> createState() => _TitleBarClaimState();
}

class _TitleBarClaimState extends State<TitleBarClaim> {
  @override
  void initState() {
    super.initState();
    // After the frame: changing the count rebuilds [BareWindowFrame], which
    // must not happen in the middle of this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TitleBarClaim._claims.value++;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TitleBarClaim._claims.value--;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The window's title bar on screens without the app's top bar — sign-in,
/// registration, the connect wizard: the window buttons in their corner and
/// a band along the top to drag the window by, both drawn over the screen.
///
/// The band leaves out the 56px where a page's back button sits, and its
/// height matches the app's top bar, so it only ever covers a page title.
class BareWindowFrame extends StatelessWidget {
  const BareWindowFrame({required this.child, super.key});

  final Widget child;

  static const _height = 52.0;
  static const _leadingGap = 56.0;

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.active) return child;
    var framed = child;
    if (!DesktopWindow.clientSideFrame) {
      // No frame from GTK means no resize edges: offer them here.
      framed = DragToResizeArea(resizeEdgeSize: 6, child: framed);
    }
    return ValueListenableBuilder<int>(
      valueListenable: TitleBarClaim._claims,
      builder: (context, claims, frameChild) => Stack(
        children: [
          frameChild!,
          if (claims == 0)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _height,
              child: Row(
                children: [
                  SizedBox(width: _leadingGap),
                  WindowControls.left(),
                  Expanded(child: WindowDragArea()),
                  WindowControls.right(),
                ],
              ),
            ),
        ],
      ),
      child: framed,
    );
  }
}
