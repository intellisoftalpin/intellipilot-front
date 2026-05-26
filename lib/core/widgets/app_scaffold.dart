import 'package:flutter/material.dart';

/// Standard page scaffold with sensible defaults (centered narrow content,
/// pull-to-refresh hook). Pages that need a custom layout still use
/// [Scaffold] directly.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.constrained = true,
    this.maxContentWidth = 800,
    super.key,
  });

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// When true, wraps [body] in a centered [ConstrainedBox]. Disable for
  /// full-bleed pages (boards, dashboards).
  final bool constrained;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final content = constrained
        ? Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: body,
            ),
          )
        : body;

    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      body: SafeArea(child: content),
      floatingActionButton: floatingActionButton,
    );
  }
}
