import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';

/// Single repository covering every Phase-5 endpoint:
/// `/projects`, `/projects/:id/{roles,members,invitations}`,
/// `/invitations/accept`. Keeps the call surface in one place so cubits don't
/// each take three DI dependencies.
abstract interface class ProjectsRepository {
  // ---- projects ----
  Future<Result<List<Project>, AppFailure>> listProjects();
  Future<Result<Project, AppFailure>> getProject(String id);
  Future<Result<Project, AppFailure>> createProject(CreateProjectRequest body);
  Future<Result<Project, AppFailure>> updateProject(
    String id,
    UpdateProjectRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteProject(String id);

  /// Hard-purge every issue in the project (irreversible). Returns the count.
  Future<Result<int, AppFailure>> purgeIssues(String projectId);

  /// Hard-purge every epic in the project (issues kept, detached). Returns the
  /// count.
  Future<Result<int, AppFailure>> purgeEpics(String projectId);

  // ---- roles ----
  Future<Result<List<Role>, AppFailure>> listRoles(String projectId);
  Future<Result<Role, AppFailure>> createRole(
    String projectId,
    CreateRoleRequest body,
  );
  Future<Result<Role, AppFailure>> updateRole(
    String projectId,
    String roleId,
    UpdateRoleRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteRole(String projectId, String roleId);

  // ---- members ----
  Future<Result<List<Membership>, AppFailure>> listMembers(String projectId);
  Future<Result<Unit, AppFailure>> changeMemberRole(
    String projectId,
    String userId,
    String roleSlug,
  );
  Future<Result<Unit, AppFailure>> removeMember(
    String projectId,
    String userId,
  );

  /// Add an existing user to the project directly. Provide [userId] (from the
  /// user picker) or [identifier] (exact email / username), plus a [roleSlug].
  Future<Result<Unit, AppFailure>> addMember(
    String projectId, {
    required String roleSlug,
    String? userId,
    String? identifier,
  });

  // ---- invitations ----
  Future<Result<List<Invitation>, AppFailure>> listInvitations(
    String projectId,
  );
  Future<Result<InviteResponse, AppFailure>> invite(
    String projectId,
    InviteRequest body,
  );
  Future<Result<String, AppFailure>> acceptInvitation(String token);
}
