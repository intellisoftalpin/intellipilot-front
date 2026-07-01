import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/search/data/dtos/search_dtos.dart';
import 'package:intellipilot/features/search/domain/search_repository.dart';

class SearchRepositoryImpl implements SearchRepository {
  SearchRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<Result<SearchResponse, AppFailure>> search(
    String query, {
    String? projectId,
    List<String>? types,
  }) async {
    final res = await _api.get(
      '/api/v1/search',
      query: {
        'q': query,
        'project_id': ?projectId,
        'types': ?(types == null || types.isEmpty ? null : types.join(',')),
      },
    );
    return res.when(
      ok: (r) => Ok(SearchResponse.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }
}
