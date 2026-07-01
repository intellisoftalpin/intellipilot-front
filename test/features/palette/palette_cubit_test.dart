import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/palette/data/dtos/palette_dtos.dart';
import 'package:intellipilot/features/palette/presentation/cubits/palette_cubit.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/search/data/dtos/search_dtos.dart';
import 'package:intellipilot/features/search/domain/search_repository.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';

class _FakeProjects implements ProjectsRepository {
  _FakeProjects(this._items);
  final List<Project> _items;

  @override
  Future<Result<List<Project>, AppFailure>> listProjects() async => Ok(_items);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBacklog implements BacklogRepository {
  _FakeBacklog(this.resolved);
  final ResolvedRef? resolved;

  @override
  Future<Result<ResolvedRef, AppFailure>> resolveRef(
    String projectId,
    int reference,
  ) async {
    if (resolved == null) {
      return const Err<ResolvedRef, AppFailure>(UnknownFailure());
    }
    return Ok(resolved!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeWiki implements WikiRepository {
  _FakeWiki(this._items);
  final List<WikiPage> _items;

  @override
  Future<Result<List<WikiPage>, AppFailure>> list(String projectId) async =>
      Ok(_items);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSearch implements SearchRepository {
  const _FakeSearch();

  @override
  Future<Result<SearchResponse, AppFailure>> search(
    String query, {
    String? projectId,
    List<String>? types,
  }) async => const Ok<SearchResponse, AppFailure>(
    SearchResponse(results: [], fuzzy: false),
  );
}

Project _project(String id, String name, String slug) => Project(
  id: id,
  ownerId: 'u',
  name: name,
  slug: slug,
  description: '',
  visibility: ProjectVisibility.private,
  backlogEnabled: true,
  kanbanEnabled: true,
  wikiEnabled: true,
  epicsEnabled: true,
  createdAt: DateTime.utc(2026),
);

WikiPage _wikiPage(String id, String projectId, String title, String slug) =>
    WikiPage(
      id: id,
      projectId: projectId,
      slug: slug,
      title: title,
      body: '',
      bodyHtml: '',
      version: 1,
      createdAt: DateTime.utc(2026),
      modifiedAt: DateTime.utc(2026),
    );

void main() {
  group('PaletteCubit', () {
    test('free-text query matches projects and wiki pages', () async {
      final cubit = PaletteCubit(
        projects: _FakeProjects([
          _project('p1', 'Auth', 'auth'),
          _project('p2', 'Billing', 'billing'),
        ]),
        backlog: _FakeBacklog(null),
        wiki: _FakeWiki([_wikiPage('w1', 'p1', 'Auth playbook', 'playbook')]),
        search: const _FakeSearch(),
        activeProjectId: 'p1',
      );
      await cubit.setQuery('auth');
      final out = cubit.state.results;
      expect(out.whereType<ProjectResult>().length, 1);
      expect(out.whereType<WikiResult>().length, 1);
    });

    test('#NNN query produces an EntityResult via the ref resolver', () async {
      final cubit = PaletteCubit(
        projects: _FakeProjects(const []),
        backlog: _FakeBacklog(
          const ResolvedRef(kind: 'issue', id: 'u1', ref: 42),
        ),
        wiki: _FakeWiki(const []),
        search: const _FakeSearch(),
        activeProjectId: 'p1',
      );
      await cubit.setQuery('#42');
      final hit = cubit.state.results.whereType<EntityResult>().firstOrNull;
      expect(hit?.entityId, 'u1');
      expect(hit?.kind, EntityKind.issue);
    });

    test('#NNN with no active project falls back to free-text', () async {
      final cubit = PaletteCubit(
        projects: _FakeProjects([_project('p1', 'X', 'x')]),
        backlog: _FakeBacklog(
          const ResolvedRef(kind: 'issue', id: 't', ref: 1),
        ),
        wiki: _FakeWiki(const []),
        search: const _FakeSearch(),
        activeProjectId: null,
      );
      await cubit.setQuery('#1');
      expect(cubit.state.results.whereType<EntityResult>().isEmpty, true);
    });
  });
}
