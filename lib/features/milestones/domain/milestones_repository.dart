import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';

/// Minimal milestones repo — list only for Phase 10's board picker. Full
/// milestone CRUD ships in Phase 11.
abstract interface class MilestonesRepository {
  Future<Result<List<Milestone>, AppFailure>> list(String projectId);
}
