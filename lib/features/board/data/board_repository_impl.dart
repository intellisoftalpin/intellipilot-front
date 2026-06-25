import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/board/data/dtos/board_dtos.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';

class BoardRepositoryImpl implements BoardRepository {
  BoardRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<BoardSnapshot, AppFailure>> load(
    String projectId,
    String milestoneId,
  ) async {
    final res = await _api.get(
      '/api/v1/projects/$projectId/milestones/$milestoneId/board',
    );
    return res.when(
      ok: (r) => Ok(BoardSnapshot.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }
}
