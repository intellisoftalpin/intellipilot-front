import 'package:intellipilot/app/router/short_links.dart';
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
    String? boostProjectId,
    List<String>? types,
  }) async {
    final res = await _api.get(
      '/api/v1/search',
      query: {
        'q': query,
        'project_id': ?_asId(projectId),
        'boost_project_id': ?_asId(boostProjectId),
        'types': ?(types == null || types.isEmpty ? null : types.join(',')),
      },
    );
    return res.when(
      ok: (r) => Ok(SearchResponse.fromJson(r.data as Map<String, dynamic>)),
      err: Err.new,
    );
  }

  /// Drops anything that is not a project id.
  ///
  /// The server types both project parameters as ids and answers 400 to
  /// anything else — rejecting the *whole* search, not just the filter. A
  /// caller that passed the URL's short project ref (a prefix) therefore made
  /// the palette look empty inside every project. Callers resolve refs now;
  /// this makes a slip degrade to an unranked search instead of no search.
  String? _asId(String? value) =>
      value != null && looksLikeUuid(value) ? value : null;
}
