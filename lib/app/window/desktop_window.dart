import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// A window button the desktop puts in a title bar.
enum WindowButton { minimize, maximize, close }

/// Which window buttons go on which side, as the desktop is configured.
@immutable
class DecorationLayout {
  const DecorationLayout({this.left = const [], this.right = const []});

  /// Parses GTK's `gtk-decoration-layout`: buttons left of the colon go on
  /// the left, the rest on the right — `appmenu:close` (GNOME's default) is
  /// a lone close button on the right. Entries the app has no use for
  /// (`appmenu`, `icon`, `menu`, `spacer`) are skipped. Without a colon every
  /// button is on the left, as GTK reads it.
  factory DecorationLayout.parse(String layout) {
    final sides = layout.split(':');
    List<WindowButton> buttons(String side) => [
      for (final name in side.split(','))
        ?switch (name.trim()) {
          'minimize' => WindowButton.minimize,
          'maximize' => WindowButton.maximize,
          'close' => WindowButton.close,
          _ => null,
        },
    ];
    return DecorationLayout(
      left: buttons(sides.first),
      right: sides.length > 1 ? buttons(sides[1]) : const [],
    );
  }

  /// When the desktop cannot be asked: the window must still be closable.
  static const fallback = DecorationLayout(right: [WindowButton.close]);

  final List<WindowButton> left;
  final List<WindowButton> right;

  @override
  bool operator ==(Object other) =>
      other is DecorationLayout &&
      listEquals(other.left, left) &&
      listEquals(other.right, right);

  @override
  int get hashCode => Object.hash(Object.hashAll(left), Object.hashAll(right));
}

/// The desktop window on Linux, where the app draws its own title bar.
///
/// GTK's title bar is hidden and its window buttons move into the app's top
/// bar, laid out the way the desktop lays them out. Elsewhere (web, mobile,
/// macOS, Windows) nothing changes and [active] is false.
abstract final class DesktopWindow {
  static const _channel = MethodChannel('intellipilot/window');

  /// Whether the app draws the title bar itself.
  static bool get active => _active;
  static bool _active = false;

  static DecorationLayout get layout => _layout;
  static DecorationLayout _layout = DecorationLayout.fallback;

  /// Whether GTK still draws the frame (shadow, resize edges) after its
  /// header bar is hidden. Under a classic window manager it does not, and
  /// the app has to offer resize edges itself.
  static bool get clientSideFrame => _clientSideFrame;
  static bool _clientSideFrame = true;

  /// Pretend to run on a desktop with [layout], for widget tests.
  @visibleForTesting
  static void debugOverride({
    required bool active,
    DecorationLayout layout = DecorationLayout.fallback,
    bool clientSideFrame = true,
  }) {
    _active = active;
    _layout = layout;
    _clientSideFrame = clientSideFrame;
  }

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  /// Hide GTK's title bar and learn the desktop's button layout. Any failure
  /// leaves the native title bar in place: a window that cannot be moved or
  /// closed is worse than one with a title bar.
  static Future<void> init() async {
    if (!_supported) return;
    try {
      await windowManager.ensureInitialized();
      final info = await _channel.invokeMapMethod<String, Object?>(
        'decoration',
      );
      if (info != null) {
        _layout = DecorationLayout.parse(info['layout'] as String? ?? '');
        _clientSideFrame = info['clientSideFrame'] as bool? ?? true;
      }
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      _active = true;
    } on Object {
      _active = false;
    }
  }
}
