// `_repo` fields kept private for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
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
    required WikiRepository wiki,
    required SearchRepository search,
    this.activeProjectId,
    List<CommandResult> commands = const [],
    this.searchDebounce = const Duration(milliseconds: 250),
  }) : _projects = projects,
       _wiki = wiki,
       _search = search,
       _commands = commands,
       super(const PaletteState());

  final ProjectsRepository _projects;
  final WikiRepository _wiki;
  final SearchRepository _search;

  /// Monotonic token so a slow search response for an old query can't
  /// clobber the results of a newer one — and so a keystroke inside the
  /// debounce window cancels the search for the previous one.
  int _searchSeq = 0;

  /// Slugged commands the host page contributes (e.g. "new user story" only
  /// surfaces from the backlog page).
  final List<CommandResult> _commands;

  /// The project the palette was opened from, or `null` outside a project.
  /// Its results rank first; results from every other visible project follow.
  final String? activeProjectId;

  /// Quiet time after the last keystroke before the server is searched.
  final Duration searchDebounce;

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

  /// Filter the local list for [query] at once, then — after
  /// [searchDebounce] with no newer keystroke — search the server across all
  /// projects. Keys (`PS-1262`, `ps-1262`, `PS-E-12`, `#1262`, `1262`) are
  /// resolved server-side and come back first.
  Future<void> setQuery(String query) async {
    emit(state.copyWith(query: query));
    final seq = ++_searchSeq;
    final projects = (await _projects.listProjects()).valueOrNull ?? const [];
    final pages = activeProjectId == null
        ? const <WikiPage>[]
        : (await _wiki.list(activeProjectId!)).valueOrNull ?? const [];
    final base = _materialise(query, projects, pages);
    if (seq != _searchSeq) return;
    emit(state.copyWith(results: base));

    // A lone digit is a valid key; any other one-character query is noise.
    final q = query.trim();
    if (q.length < 2 && !_digits.hasMatch(q)) return;
    if (searchDebounce > Duration.zero) {
      await Future<void>.delayed(searchDebounce);
      if (seq != _searchSeq || isClosed) return;
    }
    final searchRes = await _search.search(q, boostProjectId: activeProjectId);
    if (seq != _searchSeq || isClosed) return;
    final hits = searchRes.valueOrNull?.results ?? const <SearchResult>[];
    if (hits.isEmpty) return;
    final hitResults = [
      for (final h in hits)
        SearchHitResult(
          entityType: h.entityType,
          projectId: h.projectId,
          entityId: h.entityId,
          label: _hitLabel(h),
          subtitle: _hitSubtitle(h),
        ),
    ];
    emit(state.copyWith(results: [...hitResults, ...base]));
  }

  static final _digits = RegExp(r'^\d$');

  /// `PS-1262 Title` when the item has a key; the bare title otherwise.
  String _hitLabel(SearchResult h) {
    final key = h.key ?? (h.ref != null ? '#${h.ref}' : null);
    return key == null ? h.title : '$key ${h.title}'.trim();
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
