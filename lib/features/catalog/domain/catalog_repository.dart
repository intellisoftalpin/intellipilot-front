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

  // ---- ssh keys ----
  Future<Result<List<SshKey>, AppFailure>> listSshKeys(String projectId);
  Future<Result<SshKey, AppFailure>> createSshKey(
    String projectId,
    CreateSshKeyRequest body,
  );
  Future<Result<SshKey, AppFailure>> updateSshKey(
    String projectId,
    String keyId,
    UpdateSshKeyRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteSshKey(String projectId, String keyId);

  // ---- repositories ----
  Future<Result<List<Repository>, AppFailure>> listRepositories(
    String projectId,
  );
  Future<Result<Repository, AppFailure>> createRepository(
    String projectId,
    CreateRepositoryRequest body,
  );
  Future<Result<Repository, AppFailure>> updateRepository(
    String projectId,
    String repositoryId,
    UpdateRepositoryRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteRepository(
    String projectId,
    String repositoryId,
  );

  /// Preview branches for a not-yet-saved repository (drives the
  /// default-branch picker during creation).
  Future<Result<RemoteBranches, AppFailure>> previewBranches(
    String projectId,
    String sshUrl,
    String sshKeyId,
  );

  /// Live branches for a saved repository.
  Future<Result<RemoteBranches, AppFailure>> repositoryBranches(
    String projectId,
    String repositoryId,
  );

  // ---- component <-> repository links ----
  Future<Result<List<ComponentRepositoryLink>, AppFailure>>
  listComponentRepositories(String projectId, String componentId);
  Future<Result<ComponentRepositoryLink, AppFailure>> linkComponentRepository(
    String projectId,
    String componentId,
    String repositoryId,
    String branch,
  );
  Future<Result<ComponentRepositoryLink, AppFailure>>
  updateComponentRepositoryBranch(
    String projectId,
    String componentId,
    String repositoryId,
    String branch,
  );
  Future<Result<Unit, AppFailure>> unlinkComponentRepository(
    String projectId,
    String componentId,
    String repositoryId,
  );

  // ---- customers ----
  Future<Result<List<Customer>, AppFailure>> listCustomers(String projectId);
  Future<Result<Customer, AppFailure>> createCustomer(
    String projectId,
    CreateCustomerRequest body,
  );
  Future<Result<Customer, AppFailure>> updateCustomer(
    String projectId,
    String customerId,
    UpdateCustomerRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteCustomer(
    String projectId,
    String customerId,
  );

  // ---- releases + versions ----
  Future<Result<List<Release>, AppFailure>> listReleases(String projectId);
  Future<Result<Release, AppFailure>> createRelease(
    String projectId,
    CreateReleaseRequest body,
  );
  Future<Result<Release, AppFailure>> updateRelease(
    String projectId,
    String releaseId,
    UpdateReleaseRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteRelease(
    String projectId,
    String releaseId,
  );

  Future<Result<List<ReleaseVersion>, AppFailure>> listReleaseVersions(
    String projectId,
    String releaseId,
  );
  Future<Result<ReleaseVersion, AppFailure>> createReleaseVersion(
    String projectId,
    String releaseId,
    CreateReleaseVersionRequest body,
  );
  Future<Result<ReleaseVersion, AppFailure>> updateReleaseVersion(
    String projectId,
    String releaseId,
    String versionId,
    UpdateReleaseVersionRequest body,
  );
  Future<Result<Unit, AppFailure>> deleteReleaseVersion(
    String projectId,
    String releaseId,
    String versionId,
  );

  // ---- component <-> release links ----
  Future<Result<List<ComponentReleaseLink>, AppFailure>> listComponentReleases(
    String projectId,
    String componentId,
  );
  Future<Result<ComponentReleaseLink, AppFailure>> linkComponentRelease(
    String projectId,
    String componentId,
    String releaseId,
  );
  Future<Result<Unit, AppFailure>> unlinkComponentRelease(
    String projectId,
    String componentId,
    String releaseId,
  );

  /// Release versions available for the given components — drives the issue
  /// fix-version picker.
  Future<Result<List<ReleaseVersionRef>, AppFailure>> versionsForComponents(
    String projectId,
    List<String> componentIds,
  );

  // ---- issue relationships ----
  Future<Result<List<IssueLink>, AppFailure>> listIssueLinks(
    String projectId,
    String issueId,
  );
  Future<Result<IssueLink, AppFailure>> createIssueLink(
    String projectId,
    String issueId,
    String targetIssueId,
    String linkType,
  );
  Future<Result<Unit, AppFailure>> deleteIssueLink(
    String projectId,
    String issueId,
    String linkId,
  );

  // ---- issue watchers ----
  Future<Result<List<String>, AppFailure>> listWatchers(
    String projectId,
    String issueId,
  );

  /// Adds a watcher. Omit [userId] to watch as self.
  Future<Result<Unit, AppFailure>> addWatcher(
    String projectId,
    String issueId, {
    String? userId,
  });
  Future<Result<Unit, AppFailure>> removeWatcher(
    String projectId,
    String issueId,
    String userId,
  );

  // ---- kanban board views (per user) ----
  Future<Result<List<BoardView>, AppFailure>> listBoardViews(String projectId);
  Future<Result<BoardView, AppFailure>> createBoardView(
    String projectId,
    String name,
    Map<String, dynamic> config,
  );
  Future<Result<BoardView, AppFailure>> updateBoardView(
    String projectId,
    String viewId,
    String name,
    Map<String, dynamic> config,
  );
  Future<Result<Unit, AppFailure>> deleteBoardView(
    String projectId,
    String viewId,
  );

  /// The user's remembered last-used board config (null if none).
  Future<Result<Map<String, dynamic>?, AppFailure>> getLastUsedBoard(
    String projectId,
  );
  Future<Result<Unit, AppFailure>> setLastUsedBoard(
    String projectId,
    Map<String, dynamic> config,
  );
}
