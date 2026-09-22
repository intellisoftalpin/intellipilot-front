// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals

import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';

/// The signed-in user's permissions per project, memoised for the session.
///
/// The project navigation asks on every rebuild whether to show Meetings, and
/// that answer needs the member and role lists; without a cache every rail
/// repaint would refetch both. Superadmins hold every permission (the server
/// bypasses role checks for them), which role resolution alone would miss.
class ProjectAccessCache {
  ProjectAccessCache({
    required ProfileRepository profile,
    required ProjectsRepository projects,
  }) : _profile = profile,
       _projects = projects;

  static const _ttl = Duration(minutes: 5);

  final ProfileRepository _profile;
  final ProjectsRepository _projects;
  final Map<String, (DateTime, Future<ProjectAccess>)> _byKey = {};
  Future<UserProfile?>? _me;

  static final ProjectAccess _everything = ProjectAccess(
    permissions: Permission.values.toSet(),
    isAdmin: true,
  );

  /// Access for [projectId]. Never fails: anything unreadable is no access.
  Future<ProjectAccess> access(String projectId) async {
    try {
      final profile = await (_me ??= _profile.getProfile().then(
        (r) => r.valueOrNull,
      ));
      if (profile == null) {
        _me = null;
        return ProjectAccess.none;
      }
      if (profile.isSuperadmin) return _everything;
      final key = '${profile.id}/$projectId';
      final hit = _byKey[key];
      if (hit != null && DateTime.now().difference(hit.$1) < _ttl) {
        return await hit.$2;
      }
      final future = resolveProjectAccess(
        _projects,
        projectId: projectId,
        userId: profile.id,
      );
      _byKey[key] = (DateTime.now(), future);
      return await future;
    } on Object {
      return ProjectAccess.none;
    }
  }

  /// Forget everything — on sign-out or account switch.
  void clear() {
    _byKey.clear();
    _me = null;
  }
}
