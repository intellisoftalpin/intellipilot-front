import 'package:flutter/material.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/entity_detail_page.dart';

/// Open an epic/issue detail as a wide slide-over panel layered ON TOP of the
/// current screen (the list stays mounted underneath). Replaces the old
/// full-page navigation and the cramped fixed-width side panels so detail
/// opens consistently and roomily from Backlog, Epics, Issues and the Board.
///
/// Returns when the panel is dismissed; callers can `await` it to refresh their
/// list afterwards (edits made in the panel are reflected on reload).
Future<void> showEntityDetailSheet(
  BuildContext context, {
  required String projectId,
  required EntityKind kind,
  required String entityId,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) {
      final width = MediaQuery.sizeOf(ctx).width;
      final panelWidth = width < 760
          ? width
          : (width * 0.72).clamp(760.0, 1120.0);
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
}
