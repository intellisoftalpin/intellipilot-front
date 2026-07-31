import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/activity/presentation/cubits/activity_stream_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockActivityRepo extends Mock implements ActivityRepository {}

Comment _comment(String id) => Comment(
  id: id,
  targetType: 'issue',
  targetId: 'e1',
  body: 'hello',
  bodyHtml: '<p>hello</p>',
  createdAt: DateTime.utc(2026),
);

ActivityStreamCubit _cubit(ActivityRepository repo) => ActivityStreamCubit(
  repo: repo,
  projectId: 'p1',
  kind: EntityKind.issue,
  entityId: 'e1',
);

void main() {
  late _MockActivityRepo repo;

  setUpAll(() => registerFallbackValue(EntityKind.issue));

  setUp(() {
    repo = _MockActivityRepo();
    when(
      () => repo.listComments(any(), any(), any()),
    ).thenAnswer((_) async => Ok([_comment('c1')]));
    when(
      () => repo.listHistory(any(), any(), any()),
    ).thenAnswer((_) async => const Ok(<HistoryEvent>[]));
  });

  test('load() defaults the filter to comments, not all', () async {
    final cubit = _cubit(repo);
    await cubit.load();
    final state = cubit.state;
    expect(state, isA<ActivityStreamLoaded>());
    expect((state as ActivityStreamLoaded).filter, ActivityFilter.comments);
    await cubit.close();
  });

  test('a reload keeps the filter the user selected', () async {
    final cubit = _cubit(repo);
    await cubit.load();
    cubit.setFilter(ActivityFilter.history);

    await cubit.load();

    expect(
      (cubit.state as ActivityStreamLoaded).filter,
      ActivityFilter.history,
      reason: 'reloading after a comment post must not reset the filter',
    );
    await cubit.close();
  });

  test('a failed load surfaces the failure state', () async {
    when(
      () => repo.listComments(any(), any(), any()),
    ).thenAnswer((_) async => const Err(ServerFailure()));
    final cubit = _cubit(repo);
    await cubit.load();
    expect(cubit.state, isA<ActivityStreamFailed>());
    await cubit.close();
  });
}
