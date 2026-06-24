import 'package:flutter/widgets.dart';
import 'package:intellipilot/core/models/intellibot.dart';
import 'package:intellipilot/core/models/user_ref.dart';

/// Provides the project's members (keyed by user id) to descendant widgets so
/// lists/cards can render an assignee avatar + hover card without each one
/// fetching members itself.
class MembersScope extends InheritedWidget {
  const MembersScope({
    required this.membersById,
    required super.child,
    super.key,
  });

  final Map<String, UserRef> membersById;

  /// The members map from the nearest scope, or empty when none is present.
  static Map<String, UserRef> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MembersScope>()
          ?.membersById ??
      const {};

  /// Resolve a single user id (null/unknown → null). The INTELLIBOT system
  /// actor resolves to a synthetic ref even though it is never a project member,
  /// so app-token actions render as "INTELLIBOT" wherever an actor is shown.
  static UserRef? user(BuildContext context, String? id) {
    if (id == null) return null;
    final found = of(context)[id];
    if (found != null) return found;
    if (id == kIntellibotUserId) return intellibotRef();
    return null;
  }

  @override
  bool updateShouldNotify(MembersScope oldWidget) =>
      oldWidget.membersById != membersById;
}
