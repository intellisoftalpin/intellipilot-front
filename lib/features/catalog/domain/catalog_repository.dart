import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';

abstract interface class CatalogRepository {
  // ---- taxonomy ----
  Future<Result<List<TaxonomyItem>, AppFailure>> listTaxonomy(
    String projectId,
    TaxonomyKind kind,
  );
  Future<Result<TaxonomyItem, AppFailure>> createTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    CreateTaxonomyItemRequest body,
  );
  Future<Result<TaxonomyItem, AppFailure>> updateTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
    UpdateTaxonomyItemRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
  );
  Future<Result<Unit, AppFailure>> moveTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
    MoveTaxonomyItemRequest body,
  );

  // ---- labels ----
  Future<Result<List<Label>, AppFailure>> listLabels(String projectId);
  Future<Result<Label, AppFailure>> createLabel(
    String projectId,
    CreateLabelRequest body,
  );
  Future<Result<Label, AppFailure>> updateLabel(
    String projectId,
    String labelId,
    UpdateLabelRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteLabel(
    String projectId,
    String labelId,
  );

  // ---- components ----
  Future<Result<List<Component>, AppFailure>> listComponents(String projectId);
  Future<Result<Component, AppFailure>> createComponent(
    String projectId,
    CreateComponentRequest body,
  );
  Future<Result<Component, AppFailure>> updateComponent(
    String projectId,
    String componentId,
    UpdateComponentRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteComponent(
    String projectId,
    String componentId,
  );
}
