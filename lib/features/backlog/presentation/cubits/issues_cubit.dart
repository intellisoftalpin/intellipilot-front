// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

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
    required this.severities,
    required this.labels,
    required this.components,
    this.search = '',
    this.statusFilter,
    this.typeFilter,
    this.priorityFilter,
    this.severityFilter,
    this.busy = false,
    this.lastError,
  });

  final List<Issue> issues;
  final List<TaxonomyItem> statuses;
  final List<TaxonomyItem> types;
  final List<TaxonomyItem> priorities;
  final List<TaxonomyItem> severities;
  final List<Label> labels;
  final List<Component> components;

  final String search;
  final String? statusFilter;
  final String? typeFilter;
  final String? priorityFilter;
  final String? severityFilter;
  final bool busy;
  final AppFailure? lastError;

  IssuesLoaded copyWith({
    List<Issue>? issues,
    String? search,
    Object? statusFilter = _absent,
    Object? typeFilter = _absent,
    Object? priorityFilter = _absent,
    Object? severityFilter = _absent,
    bool? busy,
    AppFailure? lastError,
  }) => IssuesLoaded(
    issues: issues ?? this.issues,
    statuses: statuses,
    types: types,
    priorities: priorities,
    severities: severities,
    labels: labels,
    components: components,
    search: search ?? this.search,
    statusFilter:
        statusFilter == _absent ? this.statusFilter : statusFilter as String?,
    typeFilter: typeFilter == _absent ? this.typeFilter : typeFilter as String?,
    priorityFilter: priorityFilter == _absent
        ? this.priorityFilter
        : priorityFilter as String?,
    severityFilter: severityFilter == _absent
        ? this.severityFilter
        : severityFilter as String?,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  static const _absent = Object();

  List<Issue> get visible {
    final q = search.trim().toLowerCase();
    return issues.where((i) {
      if (statusFilter != null && i.statusId != statusFilter) return false;
      if (typeFilter != null && i.typeId != typeFilter) return false;
      if (priorityFilter != null && i.priorityId != priorityFilter) {
        return false;
      }
      if (severityFilter != null && i.severityId != severityFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return i.subject.toLowerCase().contains(q) ||
          i.description.toLowerCase().contains(q) ||
          'issue-${i.reference}'.contains(q);
    }).toList();
  }

  @override
  List<Object?> get props => [
    issues.map((i) => i.id).toList(),
    search,
    statusFilter,
    typeFilter,
    priorityFilter,
    severityFilter,
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
    required this.projectId,
  }) : _repo = repo,
       _catalog = catalog,
       super(const IssuesLoading());

  final BacklogRepository _repo;
  final CatalogRepository _catalog;
  final String projectId;

  Future<void> load() async {
    emit(const IssuesLoading());
    final issues = await _repo.listIssues(projectId);
    final statuses =
        await _catalog.listTaxonomy(projectId, TaxonomyKind.issueStatus);
    final types =
        await _catalog.listTaxonomy(projectId, TaxonomyKind.issueType);
    final priorities =
        await _catalog.listTaxonomy(projectId, TaxonomyKind.priority);
    final severities =
        await _catalog.listTaxonomy(projectId, TaxonomyKind.severity);
    final labels = await _catalog.listLabels(projectId);
    final components = await _catalog.listComponents(projectId);

    final fail = issues.failureOrNull ??
        statuses.failureOrNull ??
        types.failureOrNull ??
        priorities.failureOrNull ??
        severities.failureOrNull ??
        labels.failureOrNull ??
        components.failureOrNull;
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
        severities: severities.valueOrNull!,
        labels: labels.valueOrNull!,
        components: components.valueOrNull!,
      ),
    );
  }

  void setSearch(String q) {
    final s = state;
    if (s is IssuesLoaded) emit(s.copyWith(search: q));
  }

  void setStatusFilter(String? id) {
    final s = state;
    if (s is IssuesLoaded) emit(s.copyWith(statusFilter: id));
  }

  void setTypeFilter(String? id) {
    final s = state;
    if (s is IssuesLoaded) emit(s.copyWith(typeFilter: id));
  }

  void setPriorityFilter(String? id) {
    final s = state;
    if (s is IssuesLoaded) emit(s.copyWith(priorityFilter: id));
  }

  void setSeverityFilter(String? id) {
    final s = state;
    if (s is IssuesLoaded) emit(s.copyWith(severityFilter: id));
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
    final res =
        await _repo.deleteIssue(projectId, id, etag: fresh.etag ?? '');
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
