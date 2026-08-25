import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_counts_cubit.dart';

class _FakeProjects extends Fake implements ProjectsRepository {
  _FakeProjects(this.counts);
  ProjectCounts counts;
  int calls = 0;

  @override
  Future<Result<ProjectCounts, AppFailure>> getProjectCounts(
    String projectId,
  ) async {
    calls++;
    return Ok(counts);
  }
}

class _FakeEvents extends Fake implements ProjectEventsService {
  final _controller = StreamController<LiveEvent>.broadcast();

  @override
  Stream<LiveEvent> watch(String projectId) => _controller.stream;

  void fire(String event) =>
      _controller.add(LiveEvent.change({'event': event}));

  void reconnected() => _controller.add(const LiveEvent.control('connected'));

  /// Not [ProjectEventsService.dispose] — this just closes the fake's stream.
  Future<void> closeStream() => _controller.close();
}

void main() {
  group('ProjectCountsCubit', () {
    test('fetches once on creation', () async {
      final repo = _FakeProjects(
        const ProjectCounts(myIssues: 3, issues: 12, epics: 2, milestones: 1),
      );
      final cubit = ProjectCountsCubit(repo: repo, projectId: 'p1');
      await Future<void>.delayed(Duration.zero);

      expect(repo.calls, 1);
      expect(cubit.state.counts?.myIssues, 3);
      expect(cubit.state.counts?.issues, 12);
      await cubit.close();
    });

    test('a burst of events collapses into one refetch', () {
      fakeAsync((async) {
        final repo = _FakeProjects(const ProjectCounts(issues: 1));
        final events = _FakeEvents();
        final cubit = ProjectCountsCubit(
          repo: repo,
          projectId: 'p1',
          events: events,
        );
        async.elapse(const Duration(milliseconds: 10));
        expect(repo.calls, 1, reason: 'initial fetch');

        // A bulk edit: many events in quick succession.
        for (var i = 0; i < 25; i++) {
          events.fire('issue.updated');
        }
        async.elapse(const Duration(milliseconds: 10));
        expect(repo.calls, 1, reason: 'still debouncing');

        async.elapse(const Duration(seconds: 5));
        expect(repo.calls, 2, reason: 'one refetch for the whole burst');

        unawaited(events.closeStream());
        unawaited(cubit.close());
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('ignores events that cannot change a count', () {
      fakeAsync((async) {
        final repo = _FakeProjects(const ProjectCounts(issues: 1));
        final events = _FakeEvents();
        final cubit = ProjectCountsCubit(
          repo: repo,
          projectId: 'p1',
          events: events,
        );
        async.elapse(const Duration(milliseconds: 10));

        events.fire('board.changed');
        events.fire('wiki.updated');
        async.elapse(const Duration(seconds: 6));
        expect(repo.calls, 1);

        unawaited(events.closeStream());
        unawaited(cubit.close());
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('a comment refreshes: it can move the my-issues count', () {
      fakeAsync((async) {
        final repo = _FakeProjects(const ProjectCounts(myIssues: 1));
        final events = _FakeEvents();
        final cubit = ProjectCountsCubit(
          repo: repo,
          projectId: 'p1',
          events: events,
        );
        async.elapse(const Duration(milliseconds: 10));

        // A comment can add an @mention, which is one of the roles counted.
        events.fire('comment.created');
        async.elapse(const Duration(seconds: 6));
        expect(repo.calls, 2);

        unawaited(events.closeStream());
        unawaited(cubit.close());
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('a reconnect refreshes, since anything may have changed', () {
      fakeAsync((async) {
        final repo = _FakeProjects(const ProjectCounts(issues: 1));
        final events = _FakeEvents();
        final cubit = ProjectCountsCubit(
          repo: repo,
          projectId: 'p1',
          events: events,
        );
        async.elapse(const Duration(milliseconds: 10));

        events.reconnected();
        async.elapse(const Duration(seconds: 6));
        expect(repo.calls, 2);

        unawaited(events.closeStream());
        unawaited(cubit.close());
        async.elapse(const Duration(seconds: 1));
      });
    });
  });

  group('ProjectCounts', () {
    test('a missing section parses as null, not zero', () {
      // null means "you may not see this"; 0 means "there are none".
      final c = ProjectCounts.fromJson({
        'my_issues': 4,
        'issues': 0,
        'epics': null,
      });
      expect(c.myIssues, 4);
      expect(c.issues, 0);
      expect(c.epics, isNull);
      expect(c.milestones, isNull);
    });
  });
}
