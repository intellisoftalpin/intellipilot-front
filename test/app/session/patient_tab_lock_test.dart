import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/session/session_sync.dart';

/// In-memory stand-in for the Web Locks API: one exclusive lock, a FIFO
/// queue, abortable pending requests and `steal`.
class _FakeLocks implements LockRequester {
  _Request? _holder;
  final _queue = <_Request>[];
  int steals = 0;

  /// A tab that took the lock and will never give it back — the frozen
  /// background tab.
  void holdForever() {
    _holder = _Request(() => Completer<void>().future);
  }

  @override
  Future<bool> request(
    Future<void> Function() onGranted, {
    Future<void>? abandonWhen,
    bool steal = false,
  }) {
    final r = _Request(onGranted);
    if (steal) {
      steals++;
      _holder = null;
      _grant(r);
    } else if (_holder == null) {
      _grant(r);
    } else {
      _queue.add(r);
      unawaited(
        abandonWhen?.then((_) {
          if (_queue.remove(r)) r.result.complete(false);
        }),
      );
    }
    return r.result.future;
  }

  void _grant(_Request r) {
    _holder = r;
    unawaited(
      r.onGranted().whenComplete(() {
        if (identical(_holder, r)) {
          _holder = null;
          if (_queue.isNotEmpty) _grant(_queue.removeAt(0));
        }
        r.result.complete(true);
      }),
    );
  }
}

class _Request {
  _Request(this.onGranted);
  final Future<void> Function() onGranted;
  final result = Completer<bool>();
}

void main() {
  test('a free lock runs the body without stealing', () {
    fakeAsync((async) {
      final locks = _FakeLocks();
      final lock = PatientTabLock(locks);
      String? got;
      unawaited(lock.run(() async => 'ok').then((v) => got = v));
      async.flushMicrotasks();
      expect(got, 'ok');
      expect(locks.steals, 0);
    });
  });

  test('a lock held forever is stolen after maxWait, not waited on', () {
    fakeAsync((async) {
      final locks = _FakeLocks()..holdForever();
      final lock = PatientTabLock(locks, maxWait: const Duration(seconds: 5));
      String? got;
      unawaited(lock.run(() async => 'ok').then((v) => got = v));

      async.elapse(const Duration(seconds: 4));
      expect(got, isNull, reason: 'still queued politely');

      async.elapse(const Duration(seconds: 2));
      expect(got, 'ok');
      expect(locks.steals, 1);
    });
  });

  test('a holder that releases in time is waited for, never robbed', () {
    fakeAsync((async) {
      final locks = _FakeLocks();
      final lock = PatientTabLock(locks, maxWait: const Duration(seconds: 5));
      final order = <String>[];

      unawaited(
        lock.run(() async {
          order.add('first start');
          await Future<void>.delayed(const Duration(seconds: 2));
          order.add('first end');
        }),
      );
      unawaited(lock.run(() async => order.add('second')));

      async.elapse(const Duration(seconds: 10));
      expect(order, ['first start', 'first end', 'second']);
      expect(locks.steals, 0);
    });
  });

  test('body errors reach the caller', () {
    fakeAsync((async) {
      final lock = PatientTabLock(_FakeLocks());
      Object? error;
      unawaited(
        lock
            .run<void>(() async => throw StateError('boom'))
            .catchError((Object e) => error = e),
      );
      async.flushMicrotasks();
      expect(error, isA<StateError>());
    });
  });

  test('a failing lock API still runs the body', () {
    fakeAsync((async) {
      final lock = PatientTabLock(_BrokenLocks());
      String? got;
      unawaited(lock.run(() async => 'ok').then((v) => got = v));
      async.flushMicrotasks();
      expect(got, 'ok');
    });
  });
}

class _BrokenLocks implements LockRequester {
  @override
  Future<bool> request(
    Future<void> Function() onGranted, {
    Future<void>? abandonWhen,
    bool steal = false,
  }) async => throw StateError('no locks');
}
