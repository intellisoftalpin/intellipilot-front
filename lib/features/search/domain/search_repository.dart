import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/search/data/dtos/search_dtos.dart';

/// Full-text search across issues, epics, wiki pages and comments.
abstract interface class SearchRepository {
  /// Backed by `GET /api/v1/search?q=&project_id=&types=`.
  Future<Result<SearchResponse, AppFailure>> search(
    String query, {
    String? projectId,
    List<String>? types,
  });
}
