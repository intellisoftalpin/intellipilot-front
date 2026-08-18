import 'package:flutter/material.dart';
import 'package:intellipilot/core/ui/detail_sheet_stack.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_page.dart';

/// Horizontal inset added per nesting level, so the panel underneath keeps a
/// visible, tappable edge instead of being buried.
const double _nestInset = 48;

/// Below this the viewport is too narrow to show a stack side by side, so
/// nested sheets stay full-width and layering is purely navigational.
const double _nestMinWidth = 1024;

/// Open an epic/issue detail as a wide slide-over panel layered ON TOP of the
/// current screen (whatever is underneath stays mounted).
///
/// Sheets stack: opening an issue from inside an epic's sheet layers it above,
/// and closing it returns to the epic rather than to the list. The one thing
/// that cannot happen is re-opening something already in the stack — an epic
/// lists its tasks and a task links back to its epic, so without that guard the
/// pair could be pushed indefinitely. Tapping such a row is simply inert.
///
/// Returns when the panel is dismissed; callers can `await` it to refresh their
/// list afterwards (edits made in the panel are reflected on reload).
Future<void> showEntityDetailSheet(
  BuildContext context, {
  required String projectId,
  required EntityKind kind,
  required String entityId,
}) async {
  final key = detailSheetKey(kind.name, entityId);
  if (DetailSheetStack.contains(key)) return;

  final depth = DetailSheetStack.depth;
  DetailSheetStack.push(key);
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      // The first sheet dims the page; deeper ones dim only lightly, otherwise
      // three stacked scrims compound into an almost black screen.
      barrierColor: depth == 0 ? Colors.black54 : Colors.black26,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) {
        final width = MediaQuery.sizeOf(ctx).width;
        final inset = width >= _nestMinWidth ? _nestInset * depth : 0.0;
        final panelWidth = width < 760
            ? width
            : ((width * 0.72).clamp(760.0, 1120.0) - inset).clamp(
                360.0,
                width,
              );
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 8,
            child: SizedBox(
              width: panelWidth,
              height: double.infinity,
              child: EntityDetailPage(
                projectId: projectId,
                kind: kind,
                entityId: entityId,
                embeddedWide: true,
                onClose: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  } finally {
    // The route can go away by close button, barrier, Escape or browser Back;
    // only a finally covers all of them.
    DetailSheetStack.pop(key);
  }
}
