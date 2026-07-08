// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';

sealed class IssuesState extends Equatable {
  const IssuesState();
  @override
  List<Object?> get props => const [];
}

final class IssuesLoading extends IssuesState {
  const IssuesLoading();
}

final class IssuesLoaded extends IssuesState {
  const IssuesLoaded({
    required this.issues,
    required this.statuses,
    required this.types,
    required this.priorities,
    required this.sizes,
    required this.labels,
    required this.components,
    required this.epics,
    required this.milestones,
    this.releaseVersions = const [],
    this.filter = const WorkItemFilter(),
    this.total = 0,
    this.pageSize = 50,
    this.offset = 0,
    this.busy = false,
    this.lastError,
  });

  /// The issues on the CURRENT page (already server-side filtered + paginated).
  final List<Issue> issues;
  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> sizes;
  final List<Label> labels;
  final List<Component> components;
  final List<Epic> epics;
  final List<Milestone> milestones;

  /// Every release version in the project, enriched with its parent
  /// release's name and color — resolves each issue's fix-version badge.
  final List<ReleaseVersionRef> releaseVersions;

  final WorkItemFilter filter;

  /// Total matching issues across all pages (for the paginator).
  final int total;
  final int pageSize;
  final int offset;
  final bool busy;
  final AppFailure? lastError;

  IssuesLoaded copyWith({
    List<Issue>? issues,
    WorkItemFilter? filter,
    int? total,
    int? pageSize,
    int? offset,
    bool? busy,
    AppFailure? lastError,
  }) => IssuesLoaded(
    issues: issues ?? this.issues,
    statuses: statuses,
    types: types,
    priorities: priorities,
    sizes: sizes,
    labels: labels,
    components: components,
    epics: epics,
    milestones: milestones,
    releaseVersions: releaseVersions,
    filter: filter ?? this.filter,
    total: total ?? this.total,
    pageSize: pageSize ?? this.pageSize,
    offset: offset ?? this.offset,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  /// The page's issues. Filtering happens server-side now, so this is the list
  /// as returned (kept as `visible` for call-site compatibility).
  List<Issue> get visible => issues;

  /// Number of pages (≥ 1).
  int get pageCount =>
      pageSize <= 0 ? 1 : (total / pageSize).ceil().clamp(1, 1 << 30);

  /// Current 0-based page index.
  int get pageIndex => pageSize <= 0 ? 0 : offset ~/ pageSize;

  @override
  List<Object?> get props => [
    issues.map((i) => i.id).toList(),
    filter,
    total,
    pageSize,
    offset,
    busy,
    lastError,
  ];
}

final class IssuesFailed extends IssuesState {
  const IssuesFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class IssuesCubit extends Cubit<IssuesState> {
  IssuesCubit({
    required BacklogRepository repo,
    required CatalogRepository catalog,
    required MilestonesRepository milestones,
    required WorkItemFilterStore filterStore,
    required this.projectId,
    WorkItemFilter? initialFilter,
  }) : _repo = repo,
       _catalog = catalog,
       _milestones = milestones,
       _filterStore = filterStore,
       _filter = initialFilter ?? filterStore.load(_view, projectId),
       _pageSize = filterStore.loadPageSize(_view, projectId),
       super(const IssuesLoading());

  static const _view = 'issues';
  static const _pageSizeOptions = [25, 50, 100, 200];

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final MilestonesRepository _milestones;
  final WorkItemFilterStore _filterStore;
  final String projectId;
  WorkItemFilter _filter;
  int _pageSize;
  int _offset = 0;
  Timer? _searchDebounce;

  WorkItemFilter get filter => _filter;
  static List<int> get pageSizeOptions => _pageSizeOptions;

  Future<void> load() async {
    emit(const IssuesLoading());
    final page = await _repo.listIssuesPaged(
      projectId,
      filter: _filter.toJson(),
      limit: _pageSize,
      offset: _offset,
    );
    final statuses = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueStatus,
    );
    final types = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.issueType,
    );
    final priorities = await _catalog.listTaxonomy(
      projectId,
      TaxonomyKind.priority,
    );
    final sizes = await _catalog.listTaxonomy(projectId, TaxonomyKind.size);
    final labels = await _catalog.listLabels(projectId);
    final components = await _catalog.listComponents(projectId);
    final epics = await _repo.listEpics(projectId);
    final milestones = await _milestones.list(projectId);
    final releaseVersions = await _catalog.listAllReleaseVersions(projectId);

    final fail =
        page.failureOrNull ??
        statuses.failureOrNull ??
        types.failureOrNull ??
        priorities.failureOrNull ??
        sizes.failureOrNull ??
        labels.failureOrNull ??
        components.failureOrNull ??
        epics.failureOrNull;
    if (fail != null) {
      emit(IssuesFailed(fail));
      return;
    }
    final pg = page.valueOrNull!;
    emit(
      IssuesLoaded(
        issues: pg.items,
        statuses: statuses.valueOrNull!,
        types: types.valueOrNull!,
        priorities: priorities.valueOrNull!,
        sizes: sizes.valueOrNull!,
        labels: labels.valueOrNull!,
        components: components.valueOrNull!,
        epics: epics.valueOrNull!,
        milestones: milestones.valueOrNull ?? const [],
        releaseVersions: releaseVersions.valueOrNull ?? const [],
        filter: _filter,
        total: pg.total,
        pageSize: _pageSize,
        offset: _offset,
      ),
    );
  }

  /// Re-fetch just the current page (after a filter/page/size change), keeping
  /// the already-loaded catalog lists.
  Future<void> _reloadPage() async {
    final s = state;
    if (s is! IssuesLoaded) {
      await load();
      return;
    }
    emit(s.copyWith(busy: true, lastError: null));
    final page = await _repo.listIssuesPaged(
      projectId,
      filter: _filter.toJson(),
      limit: _pageSize,
      offset: _offset,
    );
    final pg = page.valueOrNull;
    if (pg == null) {
      emit(s.copyWith(busy: false, lastError: page.failureOrNull));
      return;
    }
    emit(
      s.copyWith(
        issues: pg.items,
        total: pg.total,
        pageSize: _pageSize,
        offset: _offset,
        busy: false,
      ),
    );
  }

  /// Apply a filter immediately (dropdowns) and jump back to page 1.
  void setFilter(WorkItemFilter f) {
    _searchDebounce?.cancel();
    _filter = f;
    _offset = 0;
    unawaited(_filterStore.save(_view, projectId, f));
    unawaited(_reloadPage());
  }

  /// Update just the search term, debounced (one request per typing burst).
  void setSearch(String query) {
    final s = state;
    if (s is IssuesLoaded) {
      emit(s.copyWith(filter: _filter.copyWith(search: query)));
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      setFilter(_filter.copyWith(search: query));
    });
  }

  /// Jump to a 0-based page index.
  void setPage(int index) {
    final s = state;
    if (s is! IssuesLoaded) return;
    final clamped = index.clamp(0, (s.pageCount - 1).clamp(0, 1 << 30));
    _offset = clamped * _pageSize;
    unawaited(_reloadPage());
  }

  /// Change the page size, persist it, and return to page 1.
  void setPageSize(int size) {
    if (size <= 0) return;
    _pageSize = size;
    _offset = 0;
    unawaited(_filterStore.savePageSize(_view, projectId, size));
    unawaited(_reloadPage());
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }

  Future<void> create(CreateIssueRequest body) async {
    final s = state;
    if (s is! IssuesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createIssue(projectId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> update(String id, UpdateIssueRequest body) async {
    final s = state;
    if (s is! IssuesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getIssue(projectId, id);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.updateIssue(
      projectId,
      id,
      body: body,
      etag: fresh.etag ?? '',
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> delete(String id) async {
    final s = state;
    if (s is! IssuesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final got = await _repo.getIssue(projectId, id);
    final fresh = got.valueOrNull;
    if (fresh == null) {
      emit(s.copyWith(busy: false, lastError: got.failureOrNull));
      return;
    }
    final res = await _repo.deleteIssue(projectId, id, etag: fresh.etag ?? '');
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
