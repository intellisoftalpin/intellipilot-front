import 'package:intellipilot/core/models/user_ref.dart';

/// Fixed id of the INTELLIBOT system actor — mirrors
/// `intellipilot_core::app_token::INTELLIBOT_USER_ID` (and the row seeded by
/// migration V004). Anything an app token does is attributed to this id, so the
/// UI resolves it to a recognisable "INTELLIBOT" identity wherever an actor or
/// owner is shown.
const kIntellibotUserId = 'b0700000-0000-7000-8000-000000000000';

/// A synthetic [UserRef] for the INTELLIBOT actor, used when resolving an owner
/// / author id that isn't a normal project member.
UserRef intellibotRef() => UserRef(
  id: kIntellibotUserId,
  username: 'INTELLIBOT',
  fullName: 'INTELLIBOT',
  email: '',
  card: UserCard.fromJson(const <String, dynamic>{}),
);
