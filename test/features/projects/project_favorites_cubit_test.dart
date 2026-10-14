import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_favorites_cubit.dart';

class _FakeProjects extends Fake implements ProjectsRepository {
  _FakeProjects(this.stored);
  List<String> stored;
  bool failSave = false;
  int saves = 0;

  @override
  Future<Result<List<String>, AppFailure>> listFavoriteProjectIds() async =>
      Ok(stored);

  @override
  Future<Result<List<String>, AppFailure>> setFavoriteProjectIds(
    List<String> ids,
  ) async {
    saves++;
    if (failSave) return const Err(NetworkFailure());
    stored = ids;
    return Ok(ids);
  }
}

void main() {
  test('load reads the stored order', () async {
    final cubit = ProjectFavoritesCubit(_FakeProjects(['b', 'a']));
    await cubit.load();
    expect(cubit.state.ids, ['b', 'a']);
    expect(cubit.state.loaded, isTrue);
  });

  test('toggle stars at the end and unstars in place', () async {
    final repo = _FakeProjects(['a']);
    final cubit = ProjectFavoritesCubit(repo);
    await cubit.load();
    await cubit.toggle('b');
    expect(cubit.state.ids, ['a', 'b']);
    await cubit.toggle('a');
    expect(cubit.state.ids, ['b']);
    expect(repo.stored, ['b']);
  });

  test('starring past the cap does nothing', () async {
    final repo = _FakeProjects(['a', 'b', 'c', 'd']);
    final cubit = ProjectFavoritesCubit(repo);
    await cubit.load();
    expect(cubit.state.isFull, isTrue);
    await cubit.toggle('e');
    expect(cubit.state.ids, ['a', 'b', 'c', 'd']);
    expect(repo.saves, 0);
  });

  test('a failed save rolls back and is reported', () async {
    final repo = _FakeProjects(['a'])..failSave = true;
    final cubit = ProjectFavoritesCubit(repo);
    await cubit.load();
    await cubit.toggle('b');
    expect(cubit.state.ids, ['a']);
    expect(cubit.state.saveFailed, 1);
  });
}
