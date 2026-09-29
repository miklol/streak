import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/state/work_controller.dart';

import 'support/app_harness.dart';

final _now = DateTime(2026, 1, 10, 9);

RecordMeta _meta(String id, {DateTime? createdAt}) =>
    RecordMeta(id: id, createdAt: createdAt ?? DateTime(2026, 1, 1));

Goal _goal({double current = 0, double target = 100}) => Goal(
  meta: _meta('goal'),
  title: 'Read books',
  measurement: GoalMeasurement.number,
  unit: 'pages',
  current: current,
  target: target,
);

GoalsController _controller() {
  final work = WorkController(now: () => _now);
  final habits = HabitsController();
  final controller = GoalsController(work, habits, now: () => _now);
  addTearDown(controller.dispose);
  addTearDown(work.dispose);
  addTearDown(habits.dispose);
  return controller;
}

Future<void> _seedWork(WorkData data) => LocalStore.updateWork((_) => data);

void main() {
  useEmptyStore();

  test(
    'new goals create typed config and initial manual checkpoints',
    () async {
      final goals = _controller();
      await goals.saveGoal(_goal(current: 25, target: 200));

      final entries = goals.entriesFor('goal');
      expect(
        entries.where((entry) => entry.kind == WorkEntryKind.scopeChange),
        hasLength(1),
      );
      final progress = entries.singleWhere(
        (entry) => entry.kind == WorkEntryKind.progress,
      );
      expect(progress.value, 25);
      expect(progress.measurementUnit, 'pages');
      expect(progress.measurementKind, GoalMeasurement.number.name);
      expect(progress.measurementSource, GoalSource.manual.name);
      expect(progress.measurementBaseline, 0);
      expect(progress.measurementTarget, 200);
    },
  );

  test('progress events keep raw values and measurement snapshots', () async {
    await _seedWork(WorkData(goals: [_goal(current: 10, target: 200)]));
    final goals = _controller();
    final first = await goals.recordProgress(
      goals.byId('goal')!,
      30,
      note: 'one more session',
      date: '08-01-2026',
    );
    await goals.recordProgress(first, 30, note: 'same value, useful note');

    final progress = goals
        .entriesFor('goal')
        .where((entry) => entry.kind == WorkEntryKind.progress)
        .toList();
    expect(progress, hasLength(2));
    expect(progress.first.value, 30);
    expect(progress.first.text, 'same value, useful note');
    expect(progress.first.measurementKind, GoalMeasurement.number.name);
    expect(progress.first.measurementSource, GoalSource.manual.name);
    expect(progress.first.measurementUnit, 'pages');
    expect(progress.first.measurementBaseline, 0);
    expect(progress.first.measurementTarget, 200);
    expect(progress.last.date, '08-01-2026');
    expect(progress.last.previousValue, 10);
  });

  test(
    'notes can be edited and tombstoned without hiding progress history',
    () async {
      await _seedWork(WorkData(goals: [_goal()]));
      final goals = _controller();
      final note = await goals.saveNote(
        goals.byId('goal')!,
        ' Draft note ',
        photos: ['photo.jpg'],
      );
      final edited = await goals.saveNote(
        goals.byId('goal')!,
        'Updated note',
        existing: note,
      );
      await goals.recordProgress(goals.byId('goal')!, 15, date: '09-01-2026');
      await goals.removeNote(edited);

      final visible = goals.entriesFor('goal');
      expect(visible, hasLength(1));
      expect(visible.single.kind, WorkEntryKind.progress);
      final tombstone = LocalStore.readWork().entries.singleWhere(
        (entry) => entry.id == note.id,
      );
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.text, 'Updated note');
    },
  );

  test(
    'target, window, status, and link mutations append neutral history',
    () async {
      final habit = testHabit(id: 'habit', name: 'Read');
      await LocalStore.writeHabit(habit);
      await _seedWork(WorkData(goals: [_goal(current: 100, target: 100)]));
      final goals = _controller();

      var goal = goals.byId('goal')!;
      goal = await goals.saveGoal(
        goal.copyWith(target: 200, endDate: '31-01-2026'),
        expectedRevision: goal.meta.revision,
      );
      final link = await goals.saveHabitLink(
        goals.buildHabitLink(goalId: goal.id, habitId: habit.id),
      );
      await goals.unlinkHabit(link);
      await goals.setStatus(goals.byId(goal.id)!, GoalStatus.paused);

      final entries = goals.entriesFor('goal');
      expect(
        entries.where((entry) => entry.kind == WorkEntryKind.scopeChange),
        hasLength(3),
      );
      expect(
        entries.where((entry) => entry.kind == WorkEntryKind.statusChange),
        hasLength(1),
      );
      expect(goals.byId('goal')!.current, 100);
      for (final entry in entries.where(
        (entry) => entry.kind == WorkEntryKind.scopeChange,
      )) {
        expect(() => jsonDecode(entry.text), returnsNormally);
        expect(entry.measurementTarget, isNotNull);
      }
    },
  );

  test('progress events are immutable through note APIs', () async {
    await _seedWork(WorkData(goals: [_goal()]));
    final goals = _controller();
    await goals.recordProgress(goals.byId('goal')!, 10);
    final progress = goals.entriesFor('goal').single;

    await expectLater(
      goals.saveNote(goals.byId('goal')!, 'try edit', existing: progress),
      throwsA(
        isA<GoalOperationException>().having(
          (error) => error.code,
          'code',
          GoalFailure.missing,
        ),
      ),
    );
    await expectLater(
      goals.removeNote(progress),
      throwsA(
        isA<GoalOperationException>().having(
          (error) => error.code,
          'code',
          GoalFailure.invalidNote,
        ),
      ),
    );
    expect(goals.entriesFor('goal').single.kind, WorkEntryKind.progress);
  });

  test('archive and pause never reset recorded outcome history', () async {
    await _seedWork(WorkData(goals: [_goal()]));
    final goals = _controller();
    var goal = await goals.recordProgress(goals.byId('goal')!, 40);
    await goals.setStatus(goal, GoalStatus.paused);
    goal = goals.byId('goal')!;
    await goals.setArchived(goal, true);
    goal = goals.byId('goal')!;
    await goals.setArchived(goal, false);

    expect(goals.byId('goal')!.current, 40);
    expect(
      goals.entriesFor('goal').where((e) => e.kind == WorkEntryKind.progress),
      hasLength(1),
    );
    expect(
      goals
          .entriesFor('goal')
          .where((e) => e.kind == WorkEntryKind.statusChange),
      hasLength(1),
    );
  });
}
