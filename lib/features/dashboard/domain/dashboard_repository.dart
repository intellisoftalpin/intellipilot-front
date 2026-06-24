import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/dashboard/data/dtos/dashboard_dtos.dart';

/// Read-only access to the dashboard aggregation endpoints.
abstract class DashboardRepository {
  /// `GET /api/v1/me/dashboard` — the current user's cross-project home.
  Future<Result<HomeDashboard, AppFailure>> getHome();

  /// `GET /api/v1/projects/{id}/dashboard` — one project's dashboard.
  Future<Result<ProjectDashboard, AppFailure>> getProject(String projectId);
}
