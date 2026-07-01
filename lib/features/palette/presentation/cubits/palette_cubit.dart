// `_repo` fields kept private for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/palette/data/dtos/palette_dtos.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/search/data/dtos/search_dtos.dart';
import 'package:intellipilot/features/search/domain/search_repository.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';

class PaletteState extends Equatable {
  const PaletteState({
    this.query = '',
    this.results = const [],
    this.busy = false,
  });
  final String query;
  final List<PaletteResult> results;
  final bool busy;

  PaletteState copyWith({
    String? query,
    List<PaletteResult>? results,
    bool? busy,
  }) => PaletteState(
    query: query ?? this.query,
    results: results ?? this.results,
    busy: busy ?? this.busy,
  );

  @override
  List<Object?> get props => [query, results, busy];
}

class PaletteCubit extends Cubit<PaletteState> {
  PaletteCubit({
    required ProjectsRepository projects,
    required BacklogRepository backlog,
    required WikiRepository wiki,
    required SearchRepository search,
    this.activeProjectId,
    List<CommandResult> commands = const [],
  }) : _projects = projects,
       _backlog = backlog,
       _wiki = wiki,
       _search = search,
       _commands = commands,
       super(const PaletteState());

  final ProjectsRepository _projects;
  final BacklogRepository _backlog;
  final WikiRepository _wiki;
  final SearchRepository _search;

  /// Monotonic token so a slow search response for an old query can't
  /// clobber the results of a newer one.
  int _searchSeq = 0;

  /// Slugged commands the host page contributes (e.g. "new user story" only
  /// surfaces from the backlog page).
  final List<CommandResult> _commands;

  /// `null` when the palette is opened outside a project context — disables
  /// the `#ref` lookup + wiki search.
  final String? activeProjectId;

  /// Prime the palette with commands + a snapshot of cached projects so a
  /// freshly-opened palette already has something to filter through.
  Future<void> prime() async {
    emit(state.copyWith(busy: true));
    final projects = (await _projects.listProjects()).valueOrNull ?? const [];
    final pages = activeProjectId == null
        ? const <WikiPage>[]
        : (await _wiki.list(activeProjectId!)).valueOrNull ?? const [];
    final results = _materialise('', projects, pages);
    emit(state.copyWith(busy: false, results: results));
  }

  /// Build the filtered result list for [query]. Synchronous unless the
  /// query is a `#NNN` reference — in which case we round-trip the resolver
  /// to find the matching entity in [activeProjectId].
  Future<void> setQuery(String query) async {
    emit(state.copyWith(query: query));
    final seq = ++_searchSeq;
    final projects = (await _projects.listProjects()).valueOrNull ?? const [];
    final pages = activeProjectId == null
        ? const <WikiPage>[]
        : (await _wiki.list(activeProjectId!)).valueOrNull ?? const [];
    final base = _materialise(query, projects, pages);

    // Local `#NNN` reference resolver — kept for instant in-project lookups.
    final local = <PaletteResult>[];
    final refMatch = RegExp(r'^#(\d+)$').firstMatch(query.trim());
    if (refMatch != null && activeProjectId != null) {
      final ref = int.parse(refMatch.group(1)!);
      final resolved = (await _backlog.resolveRef(
        activeProjectId!,
        ref,
      )).valueOrNull;
      final kind = resolved == null ? null : EntityKind.fromWire(resolved.kind);
      if (resolved != null && kind != null) {
        local.add(
          EntityResult(
            projectId: activeProjectId!,
            kind: kind,
            entityId: resolved.id,
            label: '#${resolved.ref}',
            subtitle: kind.wire.replaceAll('_', ' '),
          ),
        );
      }
    }
    if (seq != _searchSeq) return;
    emit(state.copyWith(results: [...local, ...base]));

    // Remote full-text search (issues / epics / wiki / comments).
    final q = query.trim();
    if (q.length < 2) return;
    final searchRes = await _search.search(q, projectId: activeProjectId);
    if (seq != _searchSeq) return;
    final hits = searchRes.valueOrNull?.results ?? const <SearchResult>[];
    if (hits.isEmpty) return;
    final hitResults = [
      for (final h in hits)
        SearchHitResult(
          entityType: h.entityType,
          projectId: h.projectId,
          entityId: h.entityId,
          label: h.ref != null ? '#${h.ref} ${h.title}'.trim() : h.title,
          subtitle: _hitSubtitle(h),
        ),
    ];
    emit(state.copyWith(results: [...local, ...hitResults, ...base]));
  }

  String _hitSubtitle(SearchResult h) {
    final text = h.snippet
        .replaceAll(RegExp('<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? h.entityType : '${h.entityType} · $text';
  }

  List<PaletteResult> _materialise(
    String query,
    List<Project> projects,
    List<WikiPage> pages,
  ) {
    final needle = query.trim().toLowerCase();
    bool matches(String s) =>
        needle.isEmpty || s.toLowerCase().contains(needle);

    return [
      for (final p in projects)
        if (matches(p.name) || matches(p.slug))
          ProjectResult(
            projectId: p.id,
            label: p.name,
            subtitle: '/${p.slug}',
          ),
      for (final w in pages)
        if (matches(w.title) || matches(w.slug))
          WikiResult(
            projectId: w.projectId,
            pageId: w.id,
            label: w.title,
            subtitle: '/${w.slug}',
          ),
      for (final c in _commands)
        if (matches(c.label)) c,
    ];
  }
}
