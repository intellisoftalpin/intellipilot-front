import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

const _base = '/api/v1/projects';

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._api);
  final ApiClient _api;

  String _taxBase(String projectId, TaxonomyKind kind) =>
      '$_base/$projectId/taxonomy/${kind.wire}';

  @override
  Future<Result<List<TaxonomyItem>, AppFailure>> listTaxonomy(
    String projectId,
    TaxonomyKind kind,
  ) async {
    final res = await _api.get(_taxBase(projectId, kind));
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['items'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => TaxonomyItem.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<TaxonomyItem, AppFailure>> createTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    CreateTaxonomyItemRequest body,
  ) async {
    final res = await _api.post(_taxBase(projectId, kind), body: body.toJson());
    return res.when(
      ok: (r) => Ok(TaxonomyItem.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<TaxonomyItem, AppFailure>> updateTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
    UpdateTaxonomyItemRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '${_taxBase(projectId, kind)}/$itemId',
        data: body.toJson(),
      );
      return Ok(TaxonomyItem.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
  ) async {
    try {
      await _api.dio.delete<dynamic>(
        '${_taxBase(projectId, kind)}/$itemId',
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> moveTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
    MoveTaxonomyItemRequest body,
  ) async {
    final res = await _api.post(
      '${_taxBase(projectId, kind)}/$itemId/move',
      body: body.toJson(),
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  // ---- labels ----

  @override
  Future<Result<List<Label>, AppFailure>> listLabels(String projectId) async {
    final res = await _api.get('$_base/$projectId/labels');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['labels'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => Label.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Label, AppFailure>> createLabel(
    String projectId,
    CreateLabelRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/labels',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(Label.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Label, AppFailure>> updateLabel(
    String projectId,
    String labelId,
    UpdateLabelRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/labels/$labelId',
        data: body.toJson(),
      );
      return Ok(Label.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteLabel(
    String projectId,
    String labelId,
  ) async {
    try {
      await _api.dio.delete<dynamic>('$_base/$projectId/labels/$labelId');
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  // ---- components ----

  @override
  Future<Result<List<Component>, AppFailure>> listComponents(
    String projectId,
  ) async {
    final res = await _api.get('$_base/$projectId/components');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['components'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => Component.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Component, AppFailure>> createComponent(
    String projectId,
    CreateComponentRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/components',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(Component.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Component, AppFailure>> updateComponent(
    String projectId,
    String componentId,
    UpdateComponentRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/components/$componentId',
        data: body.toJson(),
      );
      return Ok(Component.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteComponent(
    String projectId,
    String componentId,
  ) async {
    try {
      await _api.dio.delete<dynamic>(
        '$_base/$projectId/components/$componentId',
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  // ---- ssh keys ----

  @override
  Future<Result<List<SshKey>, AppFailure>> listSshKeys(
    String projectId,
  ) async {
    final res = await _api.get('$_base/$projectId/ssh-keys');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['ssh_keys'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => SshKey.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<SshKey, AppFailure>> createSshKey(
    String projectId,
    CreateSshKeyRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/ssh-keys',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(SshKey.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<SshKey, AppFailure>> updateSshKey(
    String projectId,
    String keyId,
    UpdateSshKeyRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/ssh-keys/$keyId',
        data: body.toJson(),
      );
      return Ok(SshKey.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteSshKey(
    String projectId,
    String keyId,
  ) => _delete('$_base/$projectId/ssh-keys/$keyId');

  // ---- repositories ----

  @override
  Future<Result<List<Repository>, AppFailure>> listRepositories(
    String projectId,
  ) async {
    final res = await _api.get('$_base/$projectId/repositories');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['repositories'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => Repository.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Repository, AppFailure>> createRepository(
    String projectId,
    CreateRepositoryRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/repositories',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(Repository.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Repository, AppFailure>> updateRepository(
    String projectId,
    String repositoryId,
    UpdateRepositoryRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/repositories/$repositoryId',
        data: body.toJson(),
      );
      return Ok(Repository.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteRepository(
    String projectId,
    String repositoryId,
  ) => _delete('$_base/$projectId/repositories/$repositoryId');

  @override
  Future<Result<RemoteBranches, AppFailure>> previewBranches(
    String projectId,
    String sshUrl,
    String sshKeyId,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/repositories/branches',
      body: {'ssh_url': sshUrl, 'ssh_key_id': sshKeyId},
    );
    return res.when(
      ok: (r) => Ok(RemoteBranches.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<RemoteBranches, AppFailure>> repositoryBranches(
    String projectId,
    String repositoryId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/repositories/$repositoryId/branches',
    );
    return res.when(
      ok: (r) => Ok(RemoteBranches.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  // ---- component <-> repository links ----

  @override
  Future<Result<List<ComponentRepositoryLink>, AppFailure>>
  listComponentRepositories(String projectId, String componentId) async {
    final res = await _api.get(
      '$_base/$projectId/components/$componentId/repositories',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['repositories'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map(
                (e) =>
                    ComponentRepositoryLink.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<ComponentRepositoryLink, AppFailure>> linkComponentRepository(
    String projectId,
    String componentId,
    String repositoryId,
    String branch,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/components/$componentId/repositories',
      body: {'repository_id': repositoryId, 'branch': branch},
    );
    return res.when(
      ok: (r) =>
          Ok(ComponentRepositoryLink.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<ComponentRepositoryLink, AppFailure>>
  updateComponentRepositoryBranch(
    String projectId,
    String componentId,
    String repositoryId,
    String branch,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/components/$componentId/repositories/$repositoryId',
        data: {'branch': branch},
      );
      return Ok(
        ComponentRepositoryLink.fromJson(response.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> unlinkComponentRepository(
    String projectId,
    String componentId,
    String repositoryId,
  ) => _delete(
    '$_base/$projectId/components/$componentId/repositories/$repositoryId',
  );

  // ---- customers ----

  @override
  Future<Result<List<Customer>, AppFailure>> listCustomers(
    String projectId,
  ) async {
    final res = await _api.get('$_base/$projectId/customers');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['customers'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Customer, AppFailure>> createCustomer(
    String projectId,
    CreateCustomerRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/customers',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(Customer.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Customer, AppFailure>> updateCustomer(
    String projectId,
    String customerId,
    UpdateCustomerRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/customers/$customerId',
        data: body.toJson(),
      );
      return Ok(Customer.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteCustomer(
    String projectId,
    String customerId,
  ) => _delete('$_base/$projectId/customers/$customerId');

  // ---- releases + versions ----

  @override
  Future<Result<List<Release>, AppFailure>> listReleases(
    String projectId,
  ) async {
    final res = await _api.get('$_base/$projectId/releases');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['releases'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => Release.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Release, AppFailure>> createRelease(
    String projectId,
    CreateReleaseRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/releases',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(Release.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Release, AppFailure>> updateRelease(
    String projectId,
    String releaseId,
    UpdateReleaseRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/releases/$releaseId',
        data: body.toJson(),
      );
      return Ok(Release.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteRelease(
    String projectId,
    String releaseId,
  ) => _delete('$_base/$projectId/releases/$releaseId');

  @override
  Future<Result<List<ReleaseVersion>, AppFailure>> listReleaseVersions(
    String projectId,
    String releaseId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/releases/$releaseId/versions',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['versions'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => ReleaseVersion.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<ReleaseVersion, AppFailure>> createReleaseVersion(
    String projectId,
    String releaseId,
    CreateReleaseVersionRequest body,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/releases/$releaseId/versions',
      body: body.toJson(),
    );
    return res.when(
      ok: (r) => Ok(ReleaseVersion.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<ReleaseVersion, AppFailure>> updateReleaseVersion(
    String projectId,
    String releaseId,
    String versionId,
    UpdateReleaseVersionRequest body,
  ) async {
    try {
      final response = await _api.dio.patch<dynamic>(
        '$_base/$projectId/releases/$releaseId/versions/$versionId',
        data: body.toJson(),
      );
      return Ok(ReleaseVersion.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteReleaseVersion(
    String projectId,
    String releaseId,
    String versionId,
  ) => _delete('$_base/$projectId/releases/$releaseId/versions/$versionId');

  // ---- component <-> release links ----

  @override
  Future<Result<List<ComponentReleaseLink>, AppFailure>> listComponentReleases(
    String projectId,
    String componentId,
  ) async {
    final res = await _api.get(
      '$_base/$projectId/components/$componentId/releases',
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['releases'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map(
                (e) => ComponentReleaseLink.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<ComponentReleaseLink, AppFailure>> linkComponentRelease(
    String projectId,
    String componentId,
    String releaseId,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/components/$componentId/releases',
      body: {'release_id': releaseId},
    );
    return res.when(
      ok: (r) =>
          Ok(ComponentReleaseLink.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> unlinkComponentRelease(
    String projectId,
    String componentId,
    String releaseId,
  ) => _delete(
    '$_base/$projectId/components/$componentId/releases/$releaseId',
  );

  @override
  Future<Result<List<ReleaseVersionRef>, AppFailure>> versionsForComponents(
    String projectId,
    List<String> componentIds,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/release-versions/for-components',
      body: {'component_ids': componentIds},
    );
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['versions'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => ReleaseVersionRef.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  // ---- issue relationships ----

  @override
  Future<Result<List<IssueLink>, AppFailure>> listIssueLinks(
    String projectId,
    String issueId,
  ) async {
    final res = await _api.get('$_base/$projectId/issues/$issueId/links');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['links'] as List<dynamic>? ?? const [];
        return Ok(
          raw
              .map((e) => IssueLink.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<IssueLink, AppFailure>> createIssueLink(
    String projectId,
    String issueId,
    String targetIssueId,
    String linkType,
  ) async {
    final res = await _api.post(
      '$_base/$projectId/issues/$issueId/links',
      body: {'target_issue_id': targetIssueId, 'link_type': linkType},
    );
    return res.when(
      ok: (r) => Ok(IssueLink.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> deleteIssueLink(
    String projectId,
    String issueId,
    String linkId,
  ) => _delete('$_base/$projectId/issues/$issueId/links/$linkId');

  // ---- issue watchers ----

  @override
  Future<Result<List<String>, AppFailure>> listWatchers(
    String projectId,
    String issueId,
  ) async {
    final res = await _api.get('$_base/$projectId/issues/$issueId/watchers');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['watchers'] as List<dynamic>? ?? const [];
        return Ok(raw.map((e) => e as String).toList());
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> addWatcher(
    String projectId,
    String issueId, {
    String? userId,
  }) async {
    final res = await _api.post(
      '$_base/$projectId/issues/$issueId/watchers',
      body: {'user_id': ?userId},
    );
    return res.when(
      ok: (_) => const Ok<Unit, AppFailure>(Unit.instance),
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> removeWatcher(
    String projectId,
    String issueId,
    String userId,
  ) => _delete('$_base/$projectId/issues/$issueId/watchers/$userId');

  // ---- kanban boards (personal + shared) ----

  @override
  Future<Result<List<Board>, AppFailure>> listBoards(String projectId) async {
    final res = await _api.get('$_base/$projectId/boards');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        final raw = body['boards'] as List<dynamic>? ?? const [];
        return Ok(
          raw.map((e) => Board.fromJson(e as Map<String, dynamic>)).toList(),
        );
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Board, AppFailure>> getBoard(
    String projectId,
    String boardId,
  ) async {
    final res = await _api.get('$_base/$projectId/boards/$boardId');
    return res.when(
      ok: (r) => Ok(Board.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Board, AppFailure>> createBoard(
    String projectId, {
    required String name,
    String color = '',
    bool shared = false,
    Map<String, dynamic> config = const {},
  }) async {
    final res = await _api.post(
      '$_base/$projectId/boards',
      body: {
        'name': name,
        'color': color,
        'shared': shared,
        'config': config,
      },
    );
    return res.when(
      ok: (r) => Ok(Board.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  @override
  Future<Result<Board, AppFailure>> updateBoard(
    String projectId,
    String boardId, {
    required String name,
    String color = '',
    Map<String, dynamic> config = const {},
  }) async {
    try {
      final response = await _api.dio.put<dynamic>(
        '$_base/$projectId/boards/$boardId',
        data: {'name': name, 'color': color, 'config': config},
      );
      return Ok(Board.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<Unit, AppFailure>> deleteBoard(
    String projectId,
    String boardId,
  ) => _delete('$_base/$projectId/boards/$boardId');

  @override
  Future<Result<String?, AppFailure>> getLastOpenedBoard(
    String projectId,
  ) async {
    final res = await _api.get('$_base/$projectId/boards/last-opened');
    return res.when(
      ok: (r) {
        final body = r.data as Map<String, dynamic>;
        return Ok(body['board_id'] as String?);
      },
      err: Err.new,
    );
  }

  @override
  Future<Result<Unit, AppFailure>> setLastOpenedBoard(
    String projectId,
    String boardId,
  ) async {
    try {
      await _api.dio.put<dynamic>(
        '$_base/$projectId/boards/$boardId/last-opened',
      );
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }

  @override
  Future<Result<BoardData, AppFailure>> fetchBoardData(
    String projectId, {
    Map<String, dynamic> filter = const {},
    String? group,
    List<String>? columns,
    int columnLimit = 50,
  }) async {
    final query = <String, dynamic>{
      for (final e in filter.entries) e.key: '${e.value}',
      'group': ?group,
      if (columns != null) 'columns': columns.join(','),
      'column_limit': '$columnLimit',
    };
    final res = await _api.get('$_base/$projectId/board', query: query);
    return res.when(
      ok: (r) => Ok(BoardData.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  /// Shared DELETE helper that tolerates the 204 No Content status.
  Future<Result<Unit, AppFailure>> _delete(String path) async {
    try {
      await _api.dio.delete<dynamic>(path);
      return const Ok<Unit, AppFailure>(Unit.instance);
    } on DioException catch (e) {
      if (e.response?.statusCode == 204) {
        return const Ok<Unit, AppFailure>(Unit.instance);
      }
      return Err(mapDioExceptionToFailure(e));
    }
  }
}
