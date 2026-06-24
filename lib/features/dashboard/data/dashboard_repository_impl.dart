import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';
import 'package:intellipilot/features/dashboard/domain/dashboard_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<Result<HomeDashboard, AppFailure>> getHome() async {
    final res = await _api.get('/api/v1/me/dashboard');
    return res.when(
      ok: (r) => Ok(HomeDashboard.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<ProjectDashboard, AppFailure>> getProject(
    String projectId,
  ) async {
    final res = await _api.get('/api/v1/projects/$projectId/dashboard');
    return res.when(
      ok: (r) => Ok(ProjectDashboard.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }
}
