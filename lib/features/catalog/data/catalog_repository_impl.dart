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
}
