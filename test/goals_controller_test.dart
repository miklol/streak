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
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';

import 'support/app_harness.dart';

final _now = DateTime(2026, 1, 10, 12);

RecordMeta _meta(String id, {DateTime? createdAt}) =>
    RecordMeta(id: id, createdAt: createdAt ?? DateTime(2026, 1, 1));

GoalsController _controller({DateTime? now}) {
  final clock = now ?? _now;
  final work = WorkController(now: () => clock);
  final habits = HabitsController();
  final controller = GoalsController(work, habits, now: () => clock);
  addTearDown(controller.dispose);
  addTearDown(work.dispose);
  addTearDown(habits.dispose);
  return controller;
}

Future<void> _seedWork(WorkData data) => LocalStore.updateWork((_) => data);

Future<void> _seedHabit(Habit habit) => LocalStore.writeHabit(habit);

Goal _manual(
  String id, {
  String title = 'Manual goal',
  double current = 0,
  double target = 100,
  bool pinned = false,
  int order = 0,
}) => Goal(
  meta: _meta(id),
  title: title,
  measurement: GoalMeasurement.number,
  unit: 'pages',
  current: current,
  target: target,
  pinned: pinned,
  order: order,
);

Goal _habitGoal(String id, {String unit = 'days'}) => Goal(
  meta: _meta(id),
  title: 'Habit goal',
  source: GoalSource.habits,
  measurement: GoalMeasurement.number,
  unit: unit,
  target: 10,
);

void main() {
  useEmptyStore();

  test(
    'goal CRUD survives cold start and sorts by pin, order, and id',
    () async {
      final goals = _controller();
      final third = await goals.saveGoal(_manual('c', title: 'Third'));
      final first = await goals.saveGoal(_manual('a', title: 'First'));
      final second = await goals.saveGoal(
        _manual('b', title: 'Second', pinned: true),
      );

      expect(third.order, 0);
      expect(first.order, 1);
      expect(second.order, 2);
      expect(goals.goals().map((goal) => goal.id), ['b', 'c', 'a']);

      await goals.setPinned(first, true);
      expect(goals.pinnedPersonal.map((goal) => goal.id), ['a', 'b']);

      await coldStart();
      final restarted = _controller();
      expect(restarted.byId('a')!.pinned, isTrue);
      expect(restarted.byId('b')!.order, 2);
      expect(restarted.goals().map((goal) => goal.id), ['a', 'b', 'c']);
    },
  );

  test(
    'manual progress, status changes and stale edits are revision checked',
    () async {
      await _seedWork(WorkData(goals: [_manual('goal', current: 10)]));
      final goals = _controller();
      final original = goals.byId('goal')!;
      final saved = await goals.recordProgress(
        original,
        25,
        note: 'finished a chapter',
        date: '09-01-2026',
      );

      final entry = goals.entriesFor('goal').single;
      expect(saved.current, 25);
      expect(entry.kind.name, 'progress');
      expect(entry.previousValue, 10);
      expect(entry.value, 25);
      expect(entry.text, 'finished a chapter');
      expect(entry.measurementUnit, 'pages');
      expect(entry.measurementTarget, 100);

      await expectLater(
        goals.setStatus(original, GoalStatus.paused),
        throwsA(
          isA<GoalOperationException>().having(
            (error) => error.code,
            'code',
            GoalFailure.stale,
          ),
        ),
      );
      await expectLater(
        goals.setStatus(saved, GoalStatus.achieved),
        throwsA(
          isA<GoalOperationException>().having(
            (error) => error.code,
            'code',
            GoalFailure.incomplete,
          ),
        ),
      );

      final complete = await goals.recordProgress(saved, 100);
      await goals.setStatus(complete, GoalStatus.achieved);
      expect(goals.byId('goal')!.status, GoalStatus.achieved);
      expect(
        goals.entriesFor('goal').where((e) => e.kind.name == 'statusChange'),
        hasLength(1),
      );

      await expectLater(
        goals.recordProgress(goals.byId('goal')!, 90, date: '11-01-2026'),
        throwsA(
          isA<GoalOperationException>().having(
            (error) => error.code,
            'code',
            GoalFailure.invalidMeasurement,
          ),
        ),
      );
    },
  );

  test(
    'pinned personal excludes completed, cancelled, and archived goals',
    () async {
      await _seedWork(
        WorkData(
          goals: [
            _manual('active', pinned: true),
            _manual(
              'achieved',
              pinned: true,
            ).copyWith(status: GoalStatus.achieved),
            _manual(
              'cancelled',
              pinned: true,
            ).copyWith(status: GoalStatus.cancelled),
            _manual('archived', pinned: true).copyWith(
              meta: _meta(
                'archived',
              ).revise(at: DateTime(2026, 1, 2), archived: true),
            ),
          ],
        ),
      );
      final goals = _controller();

      expect(goals.pinnedPersonal.map((goal) => goal.id), ['active']);
      expect(goals.goals(archived: true).map((goal) => goal.id), ['archived']);
    },
  );

  test(
    'completion achievement fills only explicit manual completion goals',
    () async {
      await _seedWork(
        WorkData(
          goals: [
            Goal(meta: _meta('completion'), title: 'Ship it'),
            _manual('numeric', current: 0, target: 1),
          ],
        ),
      );
      final goals = _controller();
      await goals.setStatus(goals.byId('completion')!, GoalStatus.achieved);
      expect(goals.byId('completion')!.current, 1);

      await expectLater(
        goals.setStatus(goals.byId('numeric')!, GoalStatus.achieved),
        throwsA(isA<GoalOperationException>()),
      );
      expect(goals.byId('numeric')!.current, 0);
    },
  );

  test(
    'pure progress reports setup, missing, changed, and incompatible sources',
    () async {
      final originalHabit = testHabit(id: 'habit', name: 'Read');
      final changedHabit = originalHabit.copyWith(perDayTarget: 2);
      final quantity = testHabit(
        id: 'quantity',
        name: 'Pages',
        kind: HabitKind.quantitative,
        unitLabel: 'pages',
        done: [DateTime(2026, 1, 2)],
      );
      await _seedHabit(changedHabit);
      await _seedHabit(quantity);
      final staleLink = GoalHabitLink.forHabit(
        meta: _meta('stale-link'),
        goalId: 'stale',
        habit: originalHabit,
        role: GoalHabitRole.contributor,
      );
      final missingLink = GoalHabitLink.forHabit(
        meta: _meta('missing-link'),
        goalId: 'missing',
        habit: testHabit(id: 'missing-habit', name: 'Missing'),
        role: GoalHabitRole.contributor,
      );
      final incompatibleLink = GoalHabitLink.forHabit(
        meta: _meta('bad-link'),
        goalId: 'bad',
        habit: quantity,
        role: GoalHabitRole.contributor,
        metric: HabitGoalMetric.quantity,
      );
      await _seedWork(
        WorkData(
          projects: [WorkProject(meta: _meta('empty-project'), name: 'Empty')],
          goals: [
            _habitGoal('needs'),
            _habitGoal('stale'),
            _habitGoal('missing'),
            _habitGoal('bad', unit: 'books'),
            Goal(
              meta: _meta('work-needs'),
              title: 'Work',
              source: GoalSource.work,
              measurement: GoalMeasurement.percentage,
              target: 100,
            ),
            Goal(
              meta: _meta('work-empty'),
              title: 'Empty work',
              source: GoalSource.work,
              measurement: GoalMeasurement.percentage,
              target: 100,
              projectIds: ['empty-project'],
            ),
          ],
          habitLinks: [staleLink, missingLink, incompatibleLink],
        ),
      );
      final goals = _controller();

      expect(goals.progressFor('needs').issue, GoalProgressIssue.needsHabit);
      expect(
        goals.progressFor('missing').issue,
        GoalProgressIssue.missingHabit,
      );
      expect(goals.progressFor('stale').issue, GoalProgressIssue.sourceChanged);
      expect(goals.progressFor('bad').issue, GoalProgressIssue.incompatible);
      expect(
        goals.progressFor('work-needs').issue,
        GoalProgressIssue.needsWork,
      );
      expect(
        goals.progressFor('work-empty').issue,
        GoalProgressIssue.noWorkItems,
      );
    },
  );

  test(
    'habit links are bidirectional, measured only for contributors, and durable',
    () async {
      final today = DateTime(2026, 1, 10);
      final habit = testHabit(
        id: 'habit',
        name: 'Read',
        done: [today],
      ).copyWith(createdAt: DateTime(2026, 1, 1));
      final supportHabit = testHabit(
        id: 'support',
        name: 'Stretch',
      ).copyWith(createdAt: DateTime(2026, 1, 1));
      await _seedHabit(habit);
      await _seedHabit(supportHabit);
      await _seedWork(
        WorkData(goals: [_habitGoal('measured'), _manual('manual')]),
      );
      final goals = _controller();

      final support = await goals.saveHabitLink(
        goals.buildHabitLink(goalId: 'manual', habitId: 'support'),
      );
      final contributor = await goals.saveHabitLink(
        goals.buildHabitLink(
          goalId: 'measured',
          habitId: 'habit',
          role: GoalHabitRole.contributor,
          startDate: today.dayKey,
        ),
      );

      expect(goals.linksForHabit('habit').single.id, contributor.id);
      expect(goals.linksForGoal('manual').single.id, support.id);
      expect(goals.forHabit('support').single.id, 'manual');
      expect(goals.progressFor('manual').progress!.value, 0);
      expect(goals.progressFor('measured').progress!.value, 1);

      await expectLater(
        goals.saveHabitLink(
          goals.buildHabitLink(goalId: 'measured', habitId: 'habit'),
        ),
        throwsA(
          isA<GoalOperationException>().having(
            (error) => error.code,
            'code',
            GoalFailure.invalidLink,
          ),
        ),
      );

      await goals.unlinkHabit(contributor);
      expect(goals.linksForGoal('measured'), isEmpty);
      expect(goals.progressFor('measured').issue, GoalProgressIssue.needsHabit);
      expect(
        LocalStore.readWork().habitLinks.where((link) => link.isDeleted),
        hasLength(1),
      );
      expect(LocalStore.readHabits()['habit']!.completions, hasLength(1));
    },
  );

  test(
    'explicit source refresh updates a changed contributor signature',
    () async {
      final originalHabit = testHabit(id: 'habit', name: 'Read');
      final changedHabit = originalHabit.copyWith(perDayTarget: 2);
      final link = GoalHabitLink.forHabit(
        meta: _meta('link'),
        goalId: 'goal',
        habit: originalHabit,
        role: GoalHabitRole.contributor,
      );
      await _seedHabit(changedHabit);
      await _seedWork(
        WorkData(goals: [_habitGoal('goal')], habitLinks: [link]),
      );
      final goals = _controller();
      expect(goals.progressFor('goal').issue, GoalProgressIssue.sourceChanged);

      final refreshed = goals.buildHabitLink(
        goalId: 'goal',
        habitId: 'habit',
        role: GoalHabitRole.contributor,
        startDate: link.startDate,
        existing: link,
      );
      await goals.saveHabitLink(
        refreshed,
        expectedRevision: link.meta.revision,
      );
      expect(goals.progressFor('goal').progress, isNotNull);
    },
  );

  test(
    'setSupportingGoals preserves contributors and replaces visible support set',
    () async {
      final habit = testHabit(id: 'habit', name: 'Read');
      await _seedHabit(habit);
      final contributor = GoalHabitLink.forHabit(
        meta: _meta('contributor'),
        goalId: 'measured',
        habit: habit,
        role: GoalHabitRole.contributor,
      );
      final support = GoalHabitLink(
        meta: _meta('support'),
        goalId: 'old',
        habitId: 'habit',
      );
      await _seedWork(
        WorkData(
          goals: [_habitGoal('measured'), _manual('old'), _manual('new')],
          habitLinks: [contributor, support],
        ),
      );
      final goals = _controller();

      await goals.setSupportingGoals('habit', {'new'});
      expect(
        goals
            .linksForHabit('habit')
            .map((link) => '${link.goalId}:${link.role.name}'),
        containsAll(['measured:contributor', 'new:supporting']),
      );
      expect(
        goals.linksForHabit('habit').any((link) => link.goalId == 'old'),
        isFalse,
      );
      expect(
        LocalStore.readWork().habitLinks.where((link) => link.isDeleted),
        hasLength(1),
      );
    },
  );

  test(
    'work delivery counts selected work only when the goal source is work',
    () async {
      await _seedWork(
        WorkData(
          projects: [WorkProject(meta: _meta('project'), name: 'Launch')],
          tasks: [
            WorkTask(
              meta: _meta('done'),
              title: 'Done',
              projectId: 'project',
              status: WorkTaskStatus.done,
            ),
            WorkTask(meta: _meta('open'), title: 'Open', projectId: 'project'),
          ],
          goals: [
            Goal(
              meta: _meta('work'),
              title: 'Ship',
              source: GoalSource.work,
              measurement: GoalMeasurement.percentage,
              target: 100,
              projectIds: ['project'],
            ),
            _manual('manual', current: 40).copyWith(projectIds: ['project']),
          ],
        ),
      );
      final goals = _controller();
      expect(goals.progressFor('work').progress!.value, 50);
      expect(goals.progressFor('manual').progress!.value, 40);
    },
  );

  test(
    'setSupportingGoals preserves unchanged archived relationships',
    () async {
      final habit = testHabit(id: 'habit', name: 'Read');
      await _seedHabit(habit);
      final archivedAt = DateTime(2026, 1, 2);
      final archivedSupport = _manual('archived-support').copyWith(
        meta: _meta('archived-support').revise(
          at: archivedAt,
          archived: true,
        ),
      );
      final archivedMeasured = _habitGoal('archived-measured').copyWith(
        meta: _meta('archived-measured').revise(
          at: archivedAt,
          archived: true,
        ),
      );
      final archivedNew = _manual('archived-new').copyWith(
        meta: _meta('archived-new').revise(at: archivedAt, archived: true),
      );
      final support = GoalHabitLink(
        meta: _meta('support'),
        goalId: archivedSupport.id,
        habitId: habit.id,
      );
      final contributor = GoalHabitLink.forHabit(
        meta: _meta('contributor'),
        goalId: archivedMeasured.id,
        habit: habit,
        role: GoalHabitRole.contributor,
      );
      await _seedWork(
        WorkData(
          goals: [
            archivedSupport,
            archivedMeasured,
            archivedNew,
            _manual('new'),
          ],
          habitLinks: [support, contributor],
        ),
      );
      final goals = _controller();

      await goals.setSupportingGoals('habit', {
        archivedSupport.id,
        archivedMeasured.id,
        'new',
      });
      expect(
        goals
            .linksForHabit('habit')
            .map((link) => '${link.goalId}:${link.role.name}'),
        containsAll([
          'archived-support:supporting',
          'archived-measured:contributor',
          'new:supporting',
        ]),
      );
      expect(
        goals.forHabit('habit').map((goal) => goal.id),
        containsAll(['archived-support', 'archived-measured', 'new']),
      );

      await expectLater(
        goals.setSupportingGoals('habit', {
          archivedSupport.id,
          archivedMeasured.id,
          archivedNew.id,
          'new',
        }),
        throwsA(
          isA<GoalOperationException>().having(
            (error) => error.code,
            'code',
            GoalFailure.archived,
          ),
        ),
      );
    },
  );

  test(
    'supporting link edits bypass unrelated measured source repair',
    () async {
      final originalHabit = testHabit(id: 'habit', name: 'Read');
      final changedHabit = originalHabit.copyWith(perDayTarget: 2);
      final supportHabit = testHabit(id: 'support', name: 'Stretch');
      await _seedHabit(changedHabit);
      await _seedHabit(supportHabit);
      final staleLink = GoalHabitLink.forHabit(
        meta: _meta('stale'),
        goalId: 'goal',
        habit: originalHabit,
        role: GoalHabitRole.contributor,
      );
      await _seedWork(
        WorkData(goals: [_habitGoal('goal')], habitLinks: [staleLink]),
      );
      final goals = _controller();
      final draft = goals.buildHabitLink(
        goalId: 'goal',
        habitId: supportHabit.id,
      );

      expect(
        goals.previewHabitLink(draft).issue,
        GoalProgressIssue.sourceChanged,
      );
      final saved = await goals.saveHabitLink(draft);
      expect(saved.role, GoalHabitRole.supporting);
      expect(
        goals.linksForGoal('goal').map((link) => link.id),
        contains(saved.id),
      );
      expect(goals.progressFor('goal').issue, GoalProgressIssue.sourceChanged);
    },
  );

  test(
    'supporting link saves while another contributor is missing',
    () async {
      final missingHabit = testHabit(id: 'missing', name: 'Missing');
      final supportHabit = testHabit(id: 'support', name: 'Stretch');
      await _seedHabit(supportHabit);
      final missingLink = GoalHabitLink.forHabit(
        meta: _meta('missing-link'),
        goalId: 'goal',
        habit: missingHabit,
        role: GoalHabitRole.contributor,
      );
      await _seedWork(
        WorkData(goals: [_habitGoal('goal')], habitLinks: [missingLink]),
      );
      final goals = _controller();
      final draft = goals.buildHabitLink(
        goalId: 'goal',
        habitId: supportHabit.id,
      );

      expect(
        goals.previewHabitLink(draft).issue,
        GoalProgressIssue.missingHabit,
      );
      await goals.saveHabitLink(draft);
      expect(
        goals.linksForGoal('goal').map((link) => link.habitId),
        containsAll(['missing', 'support']),
      );
    },
  );
}
