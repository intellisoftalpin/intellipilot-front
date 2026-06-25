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
    this.filter = const WorkItemFilter(),
    this.busy = false,
    this.lastError,
  });

  final List<Issue> issues;
  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> sizes;
  final List<Label> labels;
  final List<Component> components;
  final List<Epic> epics;
  final List<Milestone> milestones;

  final WorkItemFilter filter;
  final bool busy;
  final AppFailure? lastError;

  IssuesLoaded copyWith({
    List<Issue>? issues,
    WorkItemFilter? filter,
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
    filter: filter ?? this.filter,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  List<Issue> get visible {
    final closed = {
      for (final s in statuses)
        if (s.isClosed ?? false) s.id,
    };
    return issues
        .where((i) => filter.matches(i, closedStatusIds: closed))
        .toList();
  }

  @override
  List<Object?> get props => [
    issues.map((i) => i.id).toList(),
    filter,
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
       super(const IssuesLoading());

  static const _view = 'issues';

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final MilestonesRepository _milestones;
  final WorkItemFilterStore _filterStore;
  final String projectId;
  WorkItemFilter _filter;

  WorkItemFilter get filter => _filter;

  Future<void> load() async {
    emit(const IssuesLoading());
    final issues = await _repo.listIssues(projectId);
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

    final fail =
        issues.failureOrNull ??
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
    emit(
      IssuesLoaded(
        issues: issues.valueOrNull!,
        statuses: statuses.valueOrNull!,
        types: types.valueOrNull!,
        priorities: priorities.valueOrNull!,
        sizes: sizes.valueOrNull!,
        labels: labels.valueOrNull!,
        components: components.valueOrNull!,
        epics: epics.valueOrNull!,
        milestones: milestones.valueOrNull ?? const [],
        filter: _filter,
      ),
    );
  }

  void setFilter(WorkItemFilter f) {
    _filter = f;
    unawaited(_filterStore.save(_view, projectId, f));
    final s = state;
    if (s is IssuesLoaded) emit(s.copyWith(filter: f));
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
