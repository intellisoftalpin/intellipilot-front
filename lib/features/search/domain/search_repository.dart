import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/search/data/dtos/search_dtos.dart';

/// Full-text search across issues, epics, wiki pages and comments.
abstract interface class SearchRepository {
  /// Backed by `GET /api/v1/search?q=&project_id=&boost_project_id=&types=`.
  ///
  /// [projectId] restricts results to one project; [boostProjectId] searches
  /// everywhere but ranks that project first. A query that reads as a key
  /// (`PS-1262`, `PS-E-12`, `#1262`, `1262`) returns the exact item(s) first.
  Future<Result<SearchResponse, AppFailure>> search(
    String query, {
    String? projectId,
    String? boostProjectId,
    List<String>? types,
  });
}
