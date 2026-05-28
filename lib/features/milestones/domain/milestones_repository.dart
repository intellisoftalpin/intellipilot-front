import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';

abstract interface class MilestonesRepository {
  Future<Result<List<Milestone>, AppFailure>> list(String projectId);
  Future<Result<Milestone, AppFailure>> get(String projectId, String id);
  Future<Result<Milestone, AppFailure>> create(
    String projectId,
    CreateMilestoneRequest body,
  );
  Future<Result<Milestone, AppFailure>> update(
    String projectId,
    String id, {
    required UpdateMilestoneRequest body,
  });
  Future<Result<Unit, AppFailure>> delete(String projectId, String id);
  Future<Result<Unit, AppFailure>> close(String projectId, String id);
  Future<Result<MilestoneStats, AppFailure>> stats(
    String projectId,
    String id,
  );
}
