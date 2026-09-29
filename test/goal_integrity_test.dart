import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/data/progress_result.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';

import 'support/app_harness.dart';

final _now = DateTime(2026, 9, 10, 12);
RecordMeta _meta(String id) => RecordMeta(id: id, createdAt: _now);

GoalsController _controller({bool realClock = false}) {
  final work = WorkController();
  final habits = HabitsController();
  final goals = GoalsController(
    work,
    habits,
    now: realClock ? null : () => _now,
  );
  addTearDown(() {
    goals.dispose();
    work.dispose();
    habits.dispose();
  });
  return goals;
}

Goal _goal({GoalSource source = GoalSource.manual}) => Goal(
  meta: _meta('goal'),
  title: 'Read regularly',
  source: source,
  measurement: GoalMeasurement.number,
  unit: 'days',
  target: 10,
);

Matcher _failure(GoalFailure code) => throwsA(
  isA<GoalOperationException>().having((error) => error.code, 'code', code),
);

void main() {
  useEmptyStore();

  test(
    'related goals follow project and subtask relationships without changing measurements',
    () async {
      await LocalStore.updateWork(
        (_) => WorkData(
          areas: [WorkArea(meta: _meta('area'), name: 'Studio')],
          projects: [
            WorkProject(meta: _meta('project'), name: 'Launch', areaId: 'area'),
          ],
          tasks: [
            WorkTask(
              meta: _meta('parent'),
              title: 'Build',
              projectId: 'project',
            ),
            WorkTask(
              meta: _meta('child'),
              title: 'Write',
              projectId: 'project',
              parentTaskId: 'parent',
            ),
          ],
          goals: [
            _goal().copyWith(
              meta: _meta('project-goal'),
              scope: GoalScope.work,
              projectIds: ['project'],
            ),
            _goal().copyWith(
              meta: _meta('parent-goal'),
              scope: GoalScope.work,
              taskIds: ['parent'],
            ),
            _goal().copyWith(
              meta: _meta('child-goal'),
              scope: GoalScope.work,
              taskIds: ['child'],
            ),
            _goal().copyWith(meta: _meta('unrelated'), scope: GoalScope.work),
          ],
        ),
      );
      final goals = _controller();
      final related = {'project-goal', 'parent-goal', 'child-goal'};
      expect(
        goals.forWork(taskId: 'child').map((goal) => goal.id).toSet(),
        related,
      );
      expect(
        goals.forWork(taskId: 'parent').map((goal) => goal.id).toSet(),
        related,
      );
      expect(
        goals.forWork(projectId: 'project').map((goal) => goal.id).toSet(),
        related,
      );
      expect(
        goals
            .goals(scope: GoalScope.work, areaId: 'area')
            .map((goal) => goal.id)
            .toSet(),
        related,
      );
      expect(
        goals.goals(scope: GoalScope.work, areaId: 'another-area'),
        isEmpty,
      );
      expect(goals.progressFor('project-goal').progress!.value, 0);
      await goals.setArchived(goals.byId('child-goal')!, true);
      expect(
        goals.forWork(taskId: 'child').map((goal) => goal.id).toSet(),
        related,
      );
      expect(goals.goals(scope: GoalScope.work, areaId: 'area'), hasLength(2));
    },
  );

  test(
    'changing units never labels the previous raw value with the new unit',
    () async {
      final goals = _controller();
      final original = await goals.saveGoal(
        _goal().copyWith(current: 120, target: 600, unit: 'minutes'),
      );
      await goals.saveGoal(
        original.copyWith(current: 2, target: 10, unit: 'hours'),
        expectedRevision: original.meta.revision,
      );
      final changed = goals
          .entriesFor('goal')
          .singleWhere(
            (entry) =>
                entry.kind == WorkEntryKind.progress &&
                entry.measurementUnit == 'hours',
          );
      expect(changed.value, 2);
      expect(changed.previousValue, isNull);
      expect(
        goals
            .entriesFor('goal')
            .singleWhere(
              (entry) =>
                  entry.kind == WorkEntryKind.progress &&
                  entry.measurementUnit == 'minutes',
            )
            .value,
        120,
      );
    },
  );

  test(
    'editing note text retains existing evidence unless explicitly removed',
    () async {
      final goals = _controller();
      final goal = await goals.saveGoal(_goal());
      final note = await goals.saveNote(
        goal,
        'Original',
        photos: ['evidence.png'],
      );
      final edited = await goals.saveNote(goal, 'Reworded', existing: note);
      expect(edited.photos, ['evidence.png']);
      final cleared = await goals.saveNote(
        goal,
        'Text only',
        existing: edited,
        photos: [],
      );
      expect(cleared.photos, isEmpty);
    },
  );

  test('goal forms cannot bypass explicit achievement requirements', () async {
    final goals = _controller();
    await expectLater(
      goals.saveGoal(_goal().copyWith(status: GoalStatus.achieved)),
      _failure(GoalFailure.incomplete),
    );
    final original = await goals.saveGoal(_goal());
    await expectLater(
      goals.saveGoal(
        original.copyWith(status: GoalStatus.achieved),
        expectedRevision: original.meta.revision,
      ),
      _failure(GoalFailure.incomplete),
    );
    final complete = await goals.saveGoal(
      Goal(
        meta: _meta('binary'),
        title: 'Publish',
        status: GoalStatus.achieved,
      ),
    );
    expect(complete.current, 1);
  });

  test('a changed connection invalidates an older goal form', () async {
    await LocalStore.writeHabit(testHabit(id: 'habit', name: 'Read'));
    final goals = _controller();
    final original = await goals.saveGoal(_goal());
    await goals.saveHabitLink(
      goals.buildHabitLink(goalId: 'goal', habitId: 'habit'),
    );
    await expectLater(
      goals.saveGoal(
        original.copyWith(title: 'Old form'),
        expectedRevision: original.meta.revision,
        links: [],
      ),
      _failure(GoalFailure.stale),
    );
    expect(goals.linksForGoal('goal'), hasLength(1));
  });

  test('a supplied link list cannot overwrite a newer link revision', () async {
    await LocalStore.writeHabit(testHabit(id: 'habit', name: 'Read'));
    final goals = _controller();
    await goals.saveGoal(_goal(source: GoalSource.habits));
    final support = await goals.saveHabitLink(
      goals.buildHabitLink(goalId: 'goal', habitId: 'habit'),
    );
    await goals.saveHabitLink(
      goals.buildHabitLink(
        goalId: 'goal',
        habitId: 'habit',
        existing: support,
        role: GoalHabitRole.contributor,
      ),
      expectedRevision: support.meta.revision,
    );
    final latest = goals.byId('goal')!;
    await expectLater(
      goals.saveGoal(
        latest,
        expectedRevision: latest.meta.revision,
        links: [support],
      ),
      _failure(GoalFailure.stale),
    );
    expect(goals.linksForGoal('goal').single.role, GoalHabitRole.contributor);
  });

  test(
    'a deleted connection cannot be revived through a supplied link list',
    () async {
      await LocalStore.writeHabit(testHabit(id: 'habit', name: 'Read'));
      final goals = _controller();
      await goals.saveGoal(_goal());
      final link = await goals.saveHabitLink(
        goals.buildHabitLink(goalId: 'goal', habitId: 'habit'),
      );
      await goals.unlinkHabit(link);
      final latest = goals.byId('goal')!;
      await expectLater(
        goals.saveGoal(
          latest,
          expectedRevision: latest.meta.revision,
          links: [link],
        ),
        _failure(GoalFailure.missing),
      );
      expect(goals.linksForGoal('goal'), isEmpty);
    },
  );

  test('saving a Work goal reads the current transaction graph', () async {
    final goals = _controller();
    await LocalStore.updateWork(
      (data) => data.copyWith(
        tasks: [
          WorkTask(
            meta: _meta('task'),
            title: 'Delivered',
            status: WorkTaskStatus.done,
          ),
        ],
      ),
    );
    await goals.saveGoal(
      Goal(
        meta: _meta('goal'),
        title: 'Deliver',
        scope: GoalScope.work,
        source: GoalSource.work,
        measurement: GoalMeasurement.percentage,
        target: 100,
        status: GoalStatus.achieved,
        taskIds: ['task'],
      ),
    );
    expect(goals.progressFor('goal').progress!.value, 100);
  });

  test('achievement never uses a cached Work delivery value', () async {
    final task = WorkTask(
      meta: _meta('task'),
      title: 'Delivered',
      status: WorkTaskStatus.done,
    );
    final goal = Goal(
      meta: _meta('goal'),
      title: 'Deliver',
      scope: GoalScope.work,
      source: GoalSource.work,
      measurement: GoalMeasurement.percentage,
      target: 100,
      taskIds: ['task'],
    );
    await LocalStore.updateWork((_) => WorkData(tasks: [task], goals: [goal]));
    final goals = _controller();
    await LocalStore.updateWork(
      (data) => data.copyWith(
        tasks: [
          task.copyWith(
            meta: task.meta.revise(at: _now),
            status: WorkTaskStatus.notStarted,
          ),
        ],
      ),
    );
    await expectLater(
      goals.setStatus(goal, GoalStatus.achieved),
      _failure(GoalFailure.incomplete),
    );
  });

  test(
    'supporting Work links do not require repairing a different source',
    () async {
      final habit = testHabit(id: 'habit', name: 'Read');
      await LocalStore.writeHabit(habit);
      final goal = _goal(source: GoalSource.habits);
      final link = GoalHabitLink.forHabit(
        meta: _meta('link'),
        goalId: 'goal',
        habit: habit,
        role: GoalHabitRole.contributor,
      );
      await LocalStore.updateWork(
        (_) => WorkData(
          goals: [goal],
          habitLinks: [link],
          tasks: [WorkTask(meta: _meta('task'), title: 'Choose the next book')],
        ),
      );
      await LocalStore.writeHabit(
        habit.copyWith(interval: HabitInterval.weekly, targetFrequency: 3),
      );
      final goals = _controller();
      expect(goals.progressFor('goal').issue, GoalProgressIssue.sourceChanged);
      await goals.saveGoal(
        goal.copyWith(taskIds: ['task']),
        expectedRevision: goal.meta.revision,
      );
      expect(goals.byId('goal')!.taskIds, ['task']);
      expect(goals.progressFor('goal').issue, GoalProgressIssue.sourceChanged);
    },
  );

  test(
    'goal history timestamps use wall time with the cutoff applied once',
    () async {
      final previousCutoff = AppClock.cutoffHour;
      AppClock.cutoffHour = 4;
      addTearDown(() => AppClock.cutoffHour = previousCutoff);
      final goals = _controller(realClock: true);
      final before = DateTime.now().toUtc();
      await goals.saveGoal(_goal());
      final after = DateTime.now().toUtc();
      final event = goals.entriesFor('goal').single;
      expect(event.meta.createdAt.isBefore(before), isFalse);
      expect(event.meta.createdAt.isAfter(after), isFalse);
      expect(event.date, AppClock.today().dayKey);
    },
  );
}
