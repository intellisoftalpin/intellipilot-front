// `_repo` fields kept private for clarity.
// ignore_for_file: prefer_initializing_formals

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/palette/data/dtos/palette_dtos.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
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
    this.activeProjectId,
    List<CommandResult> commands = const [],
  }) : _projects = projects,
       _backlog = backlog,
       _wiki = wiki,
       _commands = commands,
       super(const PaletteState());

  final ProjectsRepository _projects;
  final BacklogRepository _backlog;
  final WikiRepository _wiki;

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
    final projects = (await _projects.listProjects()).valueOrNull ?? const [];
    final pages = activeProjectId == null
        ? const <WikiPage>[]
        : (await _wiki.list(activeProjectId!)).valueOrNull ?? const [];
    final base = _materialise(query, projects, pages);

    final refMatch = RegExp(r'^#(\d+)$').firstMatch(query.trim());
    if (refMatch == null || activeProjectId == null) {
      emit(state.copyWith(results: base));
      return;
    }
    final ref = int.parse(refMatch.group(1)!);
    final res = await _backlog.resolveRef(activeProjectId!, ref);
    final resolved = res.valueOrNull;
    if (resolved == null) {
      emit(state.copyWith(results: base));
      return;
    }
    final kind = EntityKind.fromWire(resolved.kind);
    if (kind == null) {
      emit(state.copyWith(results: base));
      return;
    }
    final hit = EntityResult(
      projectId: activeProjectId!,
      kind: kind,
      entityId: resolved.id,
      label: '#${resolved.ref}',
      subtitle: kind.wire.replaceAll('_', ' '),
    );
    emit(state.copyWith(results: [hit, ...base]));
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
