import 'package:flutter/widgets.dart';
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

  /// Resolve a single user id (null/unknown → null).
  static UserRef? user(BuildContext context, String? id) =>
      id == null ? null : of(context)[id];

  @override
  bool updateShouldNotify(MembersScope oldWidget) =>
      oldWidget.membersById != membersById;
}
