import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/services/focus_service.dart';

import 'support/app_harness.dart';

final _base = DateTime.utc(2026, 9, 9, 10);

WorkData _work() => WorkData(
  tasks: [
    WorkTask(
      meta: RecordMeta(id: 'task', createdAt: _base),
      title: 'Prepare launch notes',
    ),
  ],
);

FocusController _controller() {
  final controller = FocusController();
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  useEmptyStore();

  test('FocusTarget serializes Work snapshots and migrates legacy habits', () {
    final target = FocusTarget.fromWork(_work(), 'task');
    final copy = FocusTarget.fromMap(target.toMap());
    expect(copy.kind, FocusTargetKind.workTask);
    expect(copy.id, 'task');
    expect(copy.title, 'Prepare launch notes');
    expect(
      FocusSession(
        id: 'versioned',
        habitId: '',
        targetMinutes: 1,
        seconds: 60,
        completed: true,
        startedAt: _base,
      ).toMap()['version'],
      focusSessionSchemaVersion,
    );

    final legacy = FocusSession.fromMap({
      'id': 'old',
      'habitId': 'habit',
      'targetMinutes': 25,
      'seconds': 1500,
      'completed': true,
      'startedAt': _base.toIso8601String(),
    });

    expect(legacy.target.kind, FocusTargetKind.habit);
    expect(legacy.target.id, 'habit');
  });

  test('typed v2 sessions reject malformed target and timestamps', () {
    final valid = FocusSession(
      id: 'typed',
      habitId: '',
      target: FocusTarget.fromWork(_work(), 'task'),
      targetMinutes: 10,
      seconds: 600,
      completed: true,
      startedAt: _base,
      endedAt: _base.add(const Duration(minutes: 10)),
      spans: [
        FocusSpan(
          startedAt: _base,
          endedAt: _base.add(const Duration(minutes: 10)),
        ),
      ],
    ).toMap();
    expect(
      () => FocusSession.fromMap({...valid, 'startedAt': 'nope'}),
      throwsFormatException,
    );
    expect(
      () => FocusSession.fromMap({...valid, 'target': null}),
      throwsFormatException,
    );
    expect(
      () => FocusSession.fromMap({...valid, 'version': 99}),
      throwsFormatException,
    );
    expect(
      () => FocusSession.fromMap({
        ...valid,
        'spans': [
          {
            'startedAt': _base
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
            'endedAt': _base.add(const Duration(minutes: 10)).toIso8601String(),
          },
        ],
      }),
      throwsArgumentError,
    );
  });

  test('pure overlap helper uses spans and legacy fallback intervals', () {
    final target = FocusTarget.fromWork(_work(), 'task');
    final work = FocusSession(
      id: 'work',
      habitId: '',
      target: target,
      targetMinutes: 10,
      seconds: 300,
      completed: true,
      startedAt: _base,
      endedAt: _base.add(const Duration(minutes: 10)),
      spans: [
        FocusSpan(
          startedAt: _base.add(const Duration(minutes: 5)),
          endedAt: _base.add(const Duration(minutes: 10)),
        ),
      ],
    );
    final legacy = FocusSession(
      id: 'legacy',
      habitId: '',
      targetMinutes: 10,
      seconds: 600,
      completed: true,
      startedAt: _base.add(const Duration(hours: 1)),
    );

    expect(
      focusIntervalOverlapsSessions(
        startedAt: _base.add(const Duration(minutes: 7)),
        endedAt: _base.add(const Duration(minutes: 8)),
        sessions: [work, legacy],
      ),
      isTrue,
    );
    expect(
      focusIntervalOverlapsSessions(
        startedAt: _base.add(const Duration(hours: 1, minutes: 5)),
        endedAt: _base.add(const Duration(hours: 1, minutes: 6)),
        sessions: [work, legacy],
      ),
      isTrue,
    );
    expect(
      focusIntervalOverlapsSessions(
        startedAt: _base.add(const Duration(minutes: 1)),
        endedAt: _base.add(const Duration(minutes: 2)),
        sessions: [work, legacy],
      ),
      isFalse,
    );
  });

  test(
    'Work timers keep spans, save short sessions and do not touch habits',
    () async {
      await LocalStore.writeWork(_work(), expectedRevision: 0);
      await LocalStore.writeHabit(testHabit(id: 'habit', name: 'Read'));
      final focus = _controller();
      focus.start(
        habitId: '',
        target: FocusTarget.fromWork(LocalStore.readWork(), 'task'),
        targetMinutes: 0,
      );
      final now = DateTime.now().toUtc();
      focus.pause(at: now.add(const Duration(seconds: 2)));
      focus.resume(at: now.add(const Duration(seconds: 10)));
      final session = await focus.stop(
        completed: true,
        at: now.add(const Duration(seconds: 13)),
      );

      expect(session, isNotNull);
      expect(session!.target.kind, FocusTargetKind.workTask);
      expect(session.seconds, greaterThanOrEqualTo(5));
      expect(session.spans.length, 2);
      expect(LocalStore.readHabits()['habit']!.completions, isEmpty);
    },
  );

  test(
    'pausing a timed Work session after target caps the active span',
    () async {
      await LocalStore.writeWork(_work(), expectedRevision: 0);
      final focus = _controller();
      focus.start(
        habitId: '',
        target: FocusTarget.fromWork(LocalStore.readWork(), 'task'),
        targetMinutes: 25,
      );
      final now = DateTime.now().toUtc();
      focus.pause(at: now.add(const Duration(hours: 3)));
      final session = await focus.stop(
        completed: true,
        at: now.add(const Duration(hours: 4)),
      );

      expect(session!.seconds, 25 * 60);
      expect(session.spans.single.seconds, 25 * 60);
    },
  );

  test('restores a paused-at-zero Work target with stable identity', () async {
    final target = FocusTarget.fromWork(_work(), 'task');
    await LocalStore.writeSetting('focusActive', {
      'habitId': '',
      'target': 25,
      'focus': 25,
      'break': 0,
      'isBreak': false,
      'round': 1,
      'acc': 0,
      'since': '',
      'open': true,
      'sessionId': 'stable-session',
      'phaseId': 'stable-phase',
      'focusTarget': target.toMap(),
      'phaseStartedAt': _base.toIso8601String(),
      'spanStartedAt': '',
      'spans': const [],
    });

    final focus = _controller();

    expect(focus.isActive, isTrue);
    expect(focus.isRunning, isFalse);
    expect(focus.sessionId, 'stable-session');
    expect(focus.phaseId, 'stable-phase');
    expect(focus.target.id, 'task');
  });

  test('negative focus durations are rejected', () {
    final focus = _controller();
    expect(
      () => focus.start(habitId: '', targetMinutes: -1),
      throwsArgumentError,
    );
    expect(
      () => focus.start(habitId: '', targetMinutes: 25, breakMinutes: -1),
      throwsArgumentError,
    );
  });

  test('native actions with stale identities are ignored', () async {
    final focus = _controller()..start(habitId: '', targetMinutes: 25);

    await focus.apply(
      FocusAction(
        kind: FocusAction.pause,
        at: DateTime.now(),
        sessionId: 'other',
        phaseId: focus.phaseId,
      ),
    );
    expect(focus.isRunning, isTrue);

    await focus.apply(
      FocusAction(
        kind: FocusAction.pause,
        at: DateTime.now(),
        sessionId: focus.sessionId,
        phaseId: focus.phaseId,
      ),
    );
    expect(focus.isRunning, isFalse);
  });

  test(
    'timed Work sessions bank the target rather than app downtime',
    () async {
      await LocalStore.writeWork(_work(), expectedRevision: 0);
      final focus = _controller();
      focus.start(
        habitId: '',
        target: FocusTarget.fromWork(LocalStore.readWork(), 'task'),
        targetMinutes: 25,
      );
      final session = await focus.stop(
        completed: true,
        at: DateTime.now().add(const Duration(hours: 3)),
      );

      expect(session!.seconds, 25 * 60);
      expect(session.spans.single.seconds, 25 * 60);
    },
  );

  test('clearing habit progress preserves recorded Work time', () async {
    final target = FocusTarget.fromWork(_work(), 'task');
    await LocalStore.writeHabit(testHabit(id: 'habit', name: 'Read'));
    await LocalStore.writeFocusSession(
      FocusSession(
        id: 'habit-session',
        habitId: 'habit',
        targetMinutes: 10,
        seconds: 600,
        completed: true,
        startedAt: _base,
      ),
    );
    await LocalStore.writeFocusSession(
      FocusSession(
        id: 'work-session',
        habitId: '',
        target: target,
        targetMinutes: 10,
        seconds: 600,
        completed: true,
        startedAt: _base,
        endedAt: _base.add(const Duration(minutes: 10)),
        spans: [
          FocusSpan(
            startedAt: _base,
            endedAt: _base.add(const Duration(minutes: 10)),
          ),
        ],
      ),
    );

    await LocalStore.clearProgress();

    final sessions = LocalStore.readFocusSessions();
    expect(sessions.map((session) => session.id), ['work-session']);
    expect(sessions.single.target.kind, FocusTargetKind.workTask);
  });

  test(
    'deleting Work time writes a tombstone that blocks resurrection',
    () async {
      final target = FocusTarget.fromWork(_work(), 'task');
      final session = FocusSession(
        id: 'work-delete',
        habitId: '',
        target: target,
        targetMinutes: 10,
        seconds: 600,
        completed: true,
        startedAt: _base,
        endedAt: _base.add(const Duration(minutes: 10)),
        spans: [
          FocusSpan(
            startedAt: _base,
            endedAt: _base.add(const Duration(minutes: 10)),
          ),
        ],
      );
      await LocalStore.writeFocusSession(session);
      await LocalStore.removeFocusSessions({session.id});

      expect(LocalStore.readFocusSessions(), isEmpty);
      final deleted = LocalStore.readFocusSessions(includeDeleted: true).single;
      expect(deleted.isDeleted, isTrue);
      expect(deleted.target.kind, FocusTargetKind.workTask);
      await expectLater(
        LocalStore.writeFocusSession(session),
        throwsStateError,
      );
      expect(LocalStore.readFocusSessions(), isEmpty);
    },
  );

  test(
    'manual Work time rejects overlap, future, zero and stale edits',
    () async {
      await LocalStore.writeWork(_work(), expectedRevision: 0);
      final focus = _controller();
      final target = FocusTarget.fromWork(LocalStore.readWork(), 'task');
      final saved = await focus.saveWorkTime(
        target: target,
        startedAt: _base,
        endedAt: _base.add(const Duration(minutes: 10)),
      );

      await expectLater(
        focus.saveWorkTime(
          target: target,
          startedAt: _base.add(const Duration(minutes: 5)),
          endedAt: _base.add(const Duration(minutes: 15)),
        ),
        throwsStateError,
      );
      await expectLater(
        focus.saveWorkTime(
          target: target,
          startedAt: DateTime.now().add(const Duration(minutes: 1)),
          endedAt: DateTime.now().add(const Duration(minutes: 2)),
        ),
        throwsArgumentError,
      );
      await expectLater(
        focus.saveWorkTime(target: target, startedAt: _base, endedAt: _base),
        throwsArgumentError,
      );

      await focus.updateWorkNote(saved, 'new note');
      await expectLater(
        focus.saveWorkTime(
          target: target,
          startedAt: _base.add(const Duration(hours: 1)),
          endedAt: _base.add(const Duration(hours: 2)),
          existing: saved,
        ),
        throwsStateError,
      );
    },
  );

  test('journaled stop is recoverable across cold start', () async {
    await LocalStore.writeWork(_work(), expectedRevision: 0);
    final focus = _controller();
    focus.start(
      habitId: '',
      target: FocusTarget.fromWork(LocalStore.readWork(), 'task'),
      targetMinutes: 0,
    );
    await focus.ready;
    final stopped = await focus.stop(
      completed: true,
      at: DateTime.now().add(const Duration(seconds: 2)),
    );
    expect(stopped, isNotNull);

    await coldStart();
    expect(LocalStore.readFocusSessions().single.id, stopped!.id);
    expect(LocalStore.settingMap('focusActive')['open'], isFalse);
  });

  test('manual overlap validation is serialized through LocalStore', () async {
    await LocalStore.writeWork(_work(), expectedRevision: 0);
    final target = FocusTarget.fromWork(LocalStore.readWork(), 'task');
    final first = _controller();
    final stale = _controller();
    await first.saveWorkTime(
      target: target,
      startedAt: _base,
      endedAt: _base.add(const Duration(minutes: 10)),
    );

    await expectLater(
      stale.saveWorkTime(
        target: target,
        startedAt: _base.add(const Duration(minutes: 5)),
        endedAt: _base.add(const Duration(minutes: 15)),
      ),
      throwsStateError,
    );
  });

  test(
    'new manual Work time rejects stale or removed task snapshots',
    () async {
      await LocalStore.writeWork(_work(), expectedRevision: 0);
      final target = FocusTarget.fromWork(LocalStore.readWork(), 'task');
      final focus = _controller();

      await LocalStore.writeWork(
        LocalStore.readWork().copyWith(
          tasks: [
            LocalStore.readWork().tasks.single.copyWith(title: 'Renamed task'),
          ],
        ),
        expectedRevision: LocalStore.readWork().revision,
      );
      await expectLater(
        focus.saveWorkTime(
          target: target,
          startedAt: _base,
          endedAt: _base.add(const Duration(minutes: 10)),
        ),
        throwsStateError,
      );

      final fresh = FocusTarget.fromWork(LocalStore.readWork(), 'task');
      await LocalStore.writeWork(
        LocalStore.readWork().copyWith(
          tasks: [
            LocalStore.readWork().tasks.single.copyWith(
              meta: LocalStore.readWork().tasks.single.meta.revise(
                at: _base.add(const Duration(minutes: 1)),
                deleted: true,
              ),
            ),
          ],
        ),
        expectedRevision: LocalStore.readWork().revision,
      );
      await expectLater(
        focus.saveWorkTime(
          target: fresh,
          startedAt: _base.add(const Duration(hours: 1)),
          endedAt: _base.add(const Duration(hours: 2)),
        ),
        throwsStateError,
      );
    },
  );
}
