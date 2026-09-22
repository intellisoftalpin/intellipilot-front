import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
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

/// Records every call and answers with [hits].
class _FakeSearch implements SearchRepository {
  _FakeSearch([this.hits = const []]);
  final List<SearchResult> hits;
  final calls = <({String query, String? projectId, String? boostProjectId})>[];

  @override
  Future<Result<SearchResponse, AppFailure>> search(
    String query, {
    String? projectId,
    String? boostProjectId,
    List<String>? types,
  }) async {
    calls.add((
      query: query,
      projectId: projectId,
      boostProjectId: boostProjectId,
    ));
    return Ok<SearchResponse, AppFailure>(
      SearchResponse(results: hits, fuzzy: false),
    );
  }
}

SearchResult _hit({
  required String type,
  required String id,
  required String title,
  String projectId = 'p2',
  int? ref,
  String? key,
  bool keyMatch = false,
}) => SearchResult(
  entityType: type,
  entityId: id,
  projectId: projectId,
  title: title,
  snippet: '',
  rank: 1,
  ref: ref,
  key: key,
  keyMatch: keyMatch,
);

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
  PaletteCubit cubit({
    List<Project> projects = const [],
    List<WikiPage> pages = const [],
    _FakeSearch? search,
    String? activeProjectId = 'p1',
    Duration debounce = Duration.zero,
  }) => PaletteCubit(
    projects: _FakeProjects(projects),
    wiki: _FakeWiki(pages),
    search: search ?? _FakeSearch(),
    activeProjectId: activeProjectId,
    searchDebounce: debounce,
  );

  group('PaletteCubit', () {
    test('free-text query matches projects and wiki pages', () async {
      final c = cubit(
        projects: [
          _project('p1', 'Auth', 'auth'),
          _project('p2', 'Billing', 'billing'),
        ],
        pages: [_wikiPage('w1', 'p1', 'Auth playbook', 'playbook')],
      );
      await c.setQuery('auth');
      final out = c.state.results;
      expect(out.whereType<ProjectResult>().length, 1);
      expect(out.whereType<WikiResult>().length, 1);
    });

    test('searches every project, ranking the active one first', () async {
      final search = _FakeSearch();
      await cubit(search: search).setQuery('PS-1262');
      expect(search.calls.single.query, 'PS-1262');
      expect(search.calls.single.projectId, isNull, reason: 'not a filter');
      expect(search.calls.single.boostProjectId, 'p1');
    });

    test('hits are labelled with their key, epics distinct', () async {
      final c = cubit(
        search: _FakeSearch([
          _hit(
            type: 'issue',
            id: 'i1',
            title: 'Login broken',
            ref: 1262,
            key: 'PS-1262',
            keyMatch: true,
          ),
          _hit(
            type: 'epic',
            id: 'e1',
            title: 'Auth rework',
            ref: 12,
            key: 'PS-E-12',
          ),
          _hit(type: 'wiki', id: 'w1', title: 'Runbook'),
          _hit(type: 'meeting', id: 'm1', title: 'Pricing review'),
        ]),
      );
      await c.setQuery('1262');
      final hits = c.state.results.whereType<SearchHitResult>().toList();
      expect(hits.map((h) => h.label), [
        'PS-1262 Login broken',
        'PS-E-12 Auth rework',
        'Runbook',
        'Pricing review',
      ]);
      expect(hits.map((h) => h.entityType), [
        'issue',
        'epic',
        'wiki',
        'meeting',
      ]);
      expect(hits.first.projectId, 'p2', reason: 'opens in its own project');
    });

    test('a lone digit searches; a lone letter does not', () async {
      final search = _FakeSearch();
      final c = cubit(search: search);
      await c.setQuery('7');
      await c.setQuery('a');
      expect(search.calls.map((e) => e.query), ['7']);
    });

    test('typing inside the debounce window searches only once', () async {
      final search = _FakeSearch();
      final c = cubit(
        search: search,
        debounce: const Duration(milliseconds: 20),
      );
      final first = c.setQuery('dep');
      final second = c.setQuery('deplo');
      await Future.wait([first, second]);
      expect(search.calls.map((e) => e.query), ['deplo']);
    });

    test('outside a project nothing is boosted', () async {
      final search = _FakeSearch();
      await cubit(search: search, activeProjectId: null).setQuery('#1');
      expect(search.calls.single.boostProjectId, isNull);
      expect(search.calls.single.query, '#1');
    });
  });
}
