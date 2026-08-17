import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';

abstract interface class MilestonesRepository {
  Future<Result<List<Milestone>, AppFailure>> list(String projectId);
  Future<Result<Milestone, AppFailure>> get(String projectId, String id);
  Future<Result<Milestone, AppFailure>> create(
    String projectId,
    CreateMilestoneRequest body,
  );

  /// Partial edit under an optimistic-concurrency guard. [etag] is the
  /// milestone's current revision token; a stale one fails with 412.
  Future<Result<Milestone, AppFailure>> update(
    String projectId,
    String id, {
    required UpdateMilestoneRequest body,
    required String etag,
  });

  Future<Result<Unit, AppFailure>> delete(String projectId, String id);

  /// Mark completed ([completed] true) or move back to in progress.
  Future<Result<Milestone, AppFailure>> setCompleted(
    String projectId,
    String id, {
    required bool completed,
  });

  Future<Result<MilestoneStats, AppFailure>> stats(
    String projectId,
    String id,
  );

  /// The epics composing a milestone, with their task counts hydrated for the
  /// readiness rings.
  Future<Result<List<Epic>, AppFailure>> epics(
    String projectId,
    String milestoneId,
  );

  /// Replace the full set of epics belonging to a milestone.
  Future<Result<Unit, AppFailure>> setEpics(
    String projectId,
    String milestoneId,
    List<String> epicIds,
  );
}
