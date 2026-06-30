import 'package:flutter/foundation.dart';

/// A process-wide revision counter bumped whenever the set of boards in a
/// project changes (create / delete). The left-nav Boards section listens to
/// it so a freshly created or removed board appears without a full reload.
final ValueNotifier<int> boardsNavRevision = ValueNotifier<int>(0);

void bumpBoardsNav() => boardsNavRevision.value++;
