import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/data/projects_repository_impl.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    lastRequest = options;
    return respond(options);
  }
}

ResponseBody _ok(String body, {int status = 200}) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

ApiClient _client(_Adapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    uuidGen: const DefaultUuidGen(),
    tokenProvider: () => null,
    dio: dio,
  );
}

const _projectJson =
    '{"id":"p1","slug":"apollo","name":"Apollo","description":"Mission control",'
    ' "owner_id":"u1","visibility":"internal","kanban_enabled":true,'
    ' "backlog_enabled":true,"wiki_enabled":true,"epics_enabled":true,'
    ' "created_at":"2026-05-27T00:00:00Z"}';

void main() {
  group('ProjectsRepositoryImpl', () {
    test('listProjects unwraps the {projects: [...]} envelope', () async {
      final repo = ProjectsRepositoryImpl(
        _client(_Adapter((_) async => _ok('{"projects":[$_projectJson]}'))),
      );
      final res = await repo.listProjects();
      expect(res.valueOrNull, isNotNull);
      expect(res.valueOrNull!.single.slug, 'apollo');
      expect(res.valueOrNull!.single.visibility, ProjectVisibility.internal);
    });

    test('createProject sends the visibility wire string', () async {
      final adapter = _Adapter((_) async => _ok(_projectJson, status: 201));
      final repo = ProjectsRepositoryImpl(_client(adapter));
      await repo.createProject(
        const CreateProjectRequest(
          name: 'Apollo',
          description: '',
          visibility: ProjectVisibility.publicReadonly,
        ),
      );
      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.data, {
        'name': 'Apollo',
        'description': '',
        'visibility': 'public_readonly',
      });
    });

    test('listRoles parses permission wire strings', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"roles":[{"id":"r1","project_id":"p1","slug":"dev","name":"Dev",'
          '"order":3,"is_admin":false,'
          '"permissions":["epic.create","epic.modify","not_a_real_perm"]}]}',
        ),
      );
      final repo = ProjectsRepositoryImpl(_client(adapter));
      final res = await repo.listRoles('p1');
      final role = res.valueOrNull!.single;
      expect(role.permissions, {Permission.epicCreate, Permission.epicModify});
    });

    test('updateRole sends permissions as wire strings', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"id":"r1","project_id":"p1","slug":"dev","name":"Dev","order":3,'
          '"is_admin":false,"permissions":["epic.view"]}',
        ),
      );
      final repo = ProjectsRepositoryImpl(_client(adapter));
      await repo.updateRole(
        'p1',
        'r1',
        const UpdateRoleRequest(
          permissions: {Permission.epicView, Permission.issueView},
        ),
      );
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      final perms = body['permissions'] as List<dynamic>;
      expect(perms.toSet(), {'epic.view', 'issue.view'});
    });

    test('invite passes email + role slug and parses invite_token', () async {
      final adapter = _Adapter(
        (_) async => _ok(
          '{"invitation_id":"i1","invite_token":"raw-tok"}',
          status: 201,
        ),
      );
      final repo = ProjectsRepositoryImpl(_client(adapter));
      final res = await repo.invite(
        'p1',
        const InviteRequest(email: 'u@e.com', role: 'dev'),
      );
      expect(res.valueOrNull?.invitationId, 'i1');
      expect(res.valueOrNull?.inviteToken, 'raw-tok');
      expect(adapter.lastRequest?.data, {'email': 'u@e.com', 'role': 'dev'});
    });

    test('acceptInvitation returns the project_id string', () async {
      final adapter = _Adapter(
        (_) async => _ok('{"status":"joined","project_id":"p1"}'),
      );
      final repo = ProjectsRepositoryImpl(_client(adapter));
      final res = await repo.acceptInvitation('tok');
      expect(res.valueOrNull, 'p1');
    });

    test('RolePresets.maintainer is a superset of contributor', () {
      final m = RolePresets.maintainer();
      final c = RolePresets.contributor();
      expect(m.containsAll(c), isTrue);
      expect(m.contains(Permission.memberAdd), isTrue);
      expect(c.contains(Permission.memberAdd), isFalse);
    });
  });
}
