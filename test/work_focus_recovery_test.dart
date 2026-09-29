import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_stats.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/island/data/island_ledger.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';

import 'support/app_harness.dart';

Future<FocusController> _endingPomodoro() async {
  final start = DateTime.now().toUtc().subtract(const Duration(seconds: 61));
  final work = WorkData(
    tasks: [
      WorkTask(
        meta: RecordMeta(id: 'task', createdAt: start),
        title: 'Write notes',
      ),
    ],
  );
  await LocalStore.writeWork(
    work,
    expectedRevision: LocalStore.readWork().revision,
  );
  await LocalStore.writeSetting('focusActive', {
    'habitId': '',
    'target': 1,
    'focus': 1,
    'break': 1,
    'isBreak': false,
    'round': 1,
    'acc': 0,
    'since': start.toIso8601String(),
    'open': true,
    'sessionId': 'timer',
    'phaseId': 'phase',
    'focusTarget': FocusTarget.fromWork(work, 'task').toMap(),
    'phaseStartedAt': start.toIso8601String(),
    'spanStartedAt': start.toIso8601String(),
    'spans': [],
  }, flush: true);
  final focus = FocusController();
  addTearDown(focus.dispose);
  return focus;
}

void main() {
  useEmptyStore();

  test(
    'stopping during a Pomodoro commit saves the phase exactly once',
    () async {
      final focus = await _endingPomodoro();
      final stopped = Completer<void>();
      var requested = false;
      final subscription = Hive.box('focus')
          .watch(key: '__pending_focus_transition')
          .listen((event) {
            if (event.deleted || requested) return;
            requested = true;
            focus
                .stop(completed: true)
                .then(
                  (_) => stopped.complete(),
                  onError: stopped.completeError,
                );
          });
      addTearDown(subscription.cancel);
      await stopped.future.timeout(const Duration(seconds: 6));
      expect(focus.isActive, isFalse);
      expect(LocalStore.readFocusSessions(), hasLength(1));
      expect(LocalStore.readFocusSessions().single.seconds, 60);
      await coldStart();
      expect(LocalStore.settingMap('focusActive')['open'], isFalse);
      expect(LocalStore.readFocusSessions(), hasLength(1));
    },
  );

  test('a failed phase write keeps its Work time and can be retried', () async {
    final focus = await _endingPomodoro();
    await Hive.box('focus').close();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(focus.lastPersistenceError, isNotNull);
    expect(focus.isBreak, isFalse);
    expect(focus.phaseId, 'phase');
    await LocalStore.init();
    await focus.retryPersistence();
    expect(focus.lastPersistenceError, isNull);
    final session = await focus.stop(completed: true);
    expect(session?.seconds, 60);
    expect(LocalStore.readFocusSessions(), hasLength(1));
  });

  test(
    'Work focus cannot award habit rewards and uses the logical reporting day',
    () {
      final start = DateTime(2026, 9, 10, 1);
      final target = FocusTarget(
        kind: FocusTargetKind.workTask,
        id: 'task',
        title: 'Work',
      );
      final session = FocusSession(
        id: 'work',
        habitId: '',
        target: target,
        targetMinutes: 20,
        seconds: 1200,
        completed: true,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 20)),
        spans: [
          FocusSpan(
            startedAt: start,
            endedAt: start.add(const Duration(minutes: 20)),
          ),
        ],
      );
      expect(IslandLedger.of([], [session], []).earned, 0);
      final previous = AppClock.cutoffHour;
      AppClock.cutoffHour = 4;
      addTearDown(() => AppClock.cutoffHour = previous);
      final stats = FocusStats.compute(
        sessions: [session],
        range: FocusRange.week,
        now: DateTime(2026, 9, 9, 22),
        weekStart: DateTime.monday,
      );
      expect(stats.todaySeconds, 1200);
      expect(stats.series.reduce((a, b) => a + b), 1200);
    },
  );

  test(
    'reloading after a full wipe cannot restart a removed Work timer',
    () async {
      final focus = await _endingPomodoro();
      await LocalStore.wipeEverything();
      focus.reload();
      expect(focus.isActive, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(LocalStore.readFocusSessions(), isEmpty);
    },
  );
}
