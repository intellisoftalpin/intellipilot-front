import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

class MilestonesRepositoryImpl implements MilestonesRepository {
  MilestonesRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<List<Milestone>, AppFailure>> list(String projectId) async {
    final res = await _api.get('/api/v1/projects/$projectId/milestones');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['milestones'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => Milestone.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }
}
