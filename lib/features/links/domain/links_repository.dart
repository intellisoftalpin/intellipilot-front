import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/links/data/dtos/link_dtos.dart';

abstract interface class LinksRepository {
  /// Both outgoing AND incoming links touching the given entity. The cubit
  /// renders each side with the appropriate (forward or inverse) label.
  Future<Result<List<EntityLink>, AppFailure>> listFor(
    String projectId,
    EntityKind kind,
    String entityId,
  );

  Future<Result<EntityLink, AppFailure>> create(
    String projectId,
    CreateLinkRequest body,
  );

  Future<Result<Unit, AppFailure>> delete(String projectId, String linkId);
}
