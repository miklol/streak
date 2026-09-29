import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/data/goal_progress.dart';
import 'package:streak/features/habits/data/completion.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/data/substep.dart';
import 'package:streak/features/habits/data/vacation.dart';

RecordMeta _meta(String id, {DateTime? createdAt}) =>
    RecordMeta(id: id, createdAt: createdAt ?? DateTime(2026, 1, 1));

Goal _goal({
  GoalSource source = GoalSource.habits,
  GoalMeasurement measurement = GoalMeasurement.number,
  double baseline = 0,
  double current = 0,
  double target = 100,
  String unit = 'days',
  String currency = '',
  String? startDate = '01-01-2026',
  String? endDate,
}) => Goal(
  meta: _meta('goal'),
  title: 'An outcome',
  source: source,
  measurement: measurement,
  baseline: baseline,
  current: current,
  target: target,
  unit: unit,
  currency: currency,
  startDate: startDate,
  endDate: endDate,
);

Habit _habit({
  String id = 'habit',
  HabitKind kind = HabitKind.positive,
  QuantKind quantKind = QuantKind.generic,
  double perDayTarget = 1,
  String unit = '',
  Map<String, Completion> completions = const {},
  HabitInterval interval = HabitInterval.daily,
  int targetFrequency = 1,
  int scheduleEvery = 3,
  List<int> scheduleWeekdays = const [],
  List<int> restDays = const [],
  List<VacationPeriod> vacations = const [],
  List<Substep> substeps = const [],
  DateTime? createdAt,
  DateTime? archivedAt,
}) => Habit(
  id: id,
  name: 'Source',
  color: const Color(0xFF123456),
  order: 0,
  kind: kind,
  quantKind: quantKind,
  perDayTarget: perDayTarget,
  unitLabel: unit,
  completions: completions,
  interval: interval,
  targetFrequency: targetFrequency,
  scheduleEvery: scheduleEvery,
  scheduleWeekdays: scheduleWeekdays,
  restDays: restDays,
  vacations: vacations,
  substeps: substeps,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  archivedAt: archivedAt,
);

Map<String, Completion> _records(Map<String, double> amounts) => {
  for (final entry in amounts.entries)
    entry.key: Completion(date: entry.key, count: entry.value),
};

GoalHabitLink _link(
  Habit habit, {
  HabitGoalMetric metric = HabitGoalMetric.completedDays,
  String? startDate = '01-01-2026',
  String? endDate,
  String? unit,
}) => GoalHabitLink.forHabit(
  meta: _meta('link-${habit.id}'),
  goalId: 'goal',
  habit: habit,
  role: GoalHabitRole.contributor,
  metric: metric,
  startDate: startDate,
  endDate: endDate,
  unit: unit,
);

GoalProgress _progress(
  Habit habit, {
  Goal? goal,
  GoalHabitLink? link,
  DateTime? asOf,
}) => GoalProgress.compute(
  goal: goal ?? _goal(),
  links: [link ?? _link(habit)],
  habits: {habit.id: habit},
  asOf: asOf ?? DateTime(2026, 1, 10, 12),
);

GoalProgress _consistency(Habit habit, DateTime asOf) => _progress(
  habit,
  goal: _goal(measurement: GoalMeasurement.percentage, unit: ''),
  link: _link(habit, metric: HabitGoalMetric.consistency),
  asOf: asOf,
);

void main() {
  group('Goal records', () {
    test('all fields and enum names survive a JSON round trip', () {
      final goal = Goal(
        meta: RecordMeta(
          id: 'goal',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 2, 1),
          revision: 3,
          archivedAt: DateTime(2026, 2, 2),
          deletedAt: DateTime(2026, 2, 3),
        ),
        title: 'Revenue',
        scope: GoalScope.work,
        status: GoalStatus.paused,
        measurement: GoalMeasurement.currency,
        source: GoalSource.manual,
        areaId: 'area',
        projectId: 'project',
        description: 'Description',
        category: 'Business',
        why: 'A reason',
        icon: 'bank',
        color: 0xFFAABBCC,
        baseline: 100,
        current: 150.25,
        target: 1000,
        unit: 'USD',
        currency: 'USD',
        startDate: '01-01-2026',
        endDate: '31-12-2026',
        taskIds: ['task'],
        projectIds: ['supporting-project'],
        photos: ['photo.jpg'],
      );
      final restored = Goal.fromMap(
        RecordReader.object(jsonDecode(jsonEncode(goal.toMap()))),
      );
      expect(restored.toMap(), goal.toMap());
      expect(restored.toMap()['scope'], 'work');
      expect(restored.toMap()['status'], 'paused');
      expect(restored.toMap()['measurement'], 'currency');
      expect(restored.toMap()['source'], 'manual');
      expect(restored.isArchived, isTrue);
      expect(restored.isDeleted, isTrue);
    });

    test('all enum cases round trip', () {
      for (final scope in GoalScope.values) {
        for (final status in GoalStatus.values) {
          final goal = Goal(
            meta: _meta('g'),
            title: 'Goal',
            scope: scope,
            status: status,
          );
          expect(Goal.fromMap(goal.toMap()).toMap(), goal.toMap());
        }
      }
      for (final measurement in GoalMeasurement.values) {
        final goal = Goal(
          meta: _meta('g'),
          title: 'Goal',
          measurement: measurement,
          target: measurement == GoalMeasurement.completion ? 1 : 100,
          unit: measurement == GoalMeasurement.number ? 'pages' : '',
          currency: measurement == GoalMeasurement.currency ? 'EUR' : '',
        );
        expect(Goal.fromMap(goal.toMap()).measurement, measurement);
      }
      for (final source in GoalSource.values) {
        final goal = _goal(
          source: source,
          measurement: GoalMeasurement.percentage,
          unit: '',
        );
        expect(Goal.fromMap(goal.toMap()).source, source);
      }
    });

    test(
      'collections are defensive copies and cannot be changed through maps',
      () {
        final tasks = ['task'];
        final projects = ['project'];
        final photos = ['image.jpg'];
        final goal = Goal(
          meta: _meta('goal'),
          title: 'Goal',
          taskIds: tasks,
          projectIds: projects,
          photos: photos,
        );
        tasks.clear();
        projects.clear();
        photos.clear();
        expect(goal.taskIds, ['task']);
        expect(goal.projectIds, ['project']);
        expect(goal.photos, ['image.jpg']);
        expect(() => goal.taskIds.add('other'), throwsUnsupportedError);
        expect(() => goal.projectIds.clear(), throwsUnsupportedError);
        expect(() => goal.photos[0] = 'other.jpg', throwsUnsupportedError);
        (goal.toMap()['taskIds'] as List).clear();
        expect(goal.taskIds, ['task']);
      },
    );

    test(
      'copyWith revises metadata and clears optional context and windows',
      () {
        final goal = _goal().copyWith(
          scope: GoalScope.work,
          areaId: 'area',
          projectId: 'project',
          endDate: '01-02-2026',
        );
        final edited = goal.copyWith(
          meta: goal.meta.revise(at: DateTime(2026, 1, 2)),
          title: 'Updated',
          scope: GoalScope.personal,
          clearAreaId: true,
          clearProjectId: true,
          clearStartDate: true,
          clearEndDate: true,
        );
        expect(edited.meta.revision, 2);
        expect(edited.title, 'Updated');
        expect([
          edited.areaId,
          edited.projectId,
          edited.startDate,
          edited.endDate,
        ], everyElement(isNull));
        expect(goal.areaId, 'area');
      },
    );

    test('malformed schema, enums, dates, units and nonfinite values fail', () {
      final valid = _goal().toMap();
      final invalid = <String, Object?>{
        'scope': 'other',
        'status': 1,
        'measurement': 'unknown',
        'source': null,
        'title': '  ',
        'id': '',
        'color': -1,
        'baseline': double.nan,
        'current': double.infinity,
        'target': 0,
        'unit': '',
        'currency': 'USD',
        'startDate': '2026-01-01',
        'endDate': '31-02-2026',
        'revision': 0,
        'createdAt': 'yesterday',
        'taskIds': [17],
        'projectIds': ['same', 'same'],
        'photos': [''],
      };
      for (final entry in invalid.entries) {
        expect(
          () => Goal.fromMap({...valid, entry.key: entry.value}),
          throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
          reason: entry.key,
        );
      }
      expect(
        () => _goal(startDate: '05-01-2026', endDate: '04-01-2026'),
        throwsArgumentError,
      );
      expect(() => _goal().copyWith(areaId: 'area'), throwsArgumentError);
      expect(() => _goal().copyWith(color: 0x100000000), throwsArgumentError);
      expect(() => _goal(baseline: -1e308, target: 1e308), throwsArgumentError);
      expect(
        () => _goal(current: double.negativeInfinity),
        throwsArgumentError,
      );
    });

    test(
      'completion, percentage and currency have explicit bounded meanings',
      () {
        final completion = Goal(meta: _meta('g'), title: 'Milestone');
        expect(completion.toMap()['target'], 1);
        expect(() => completion.copyWith(current: 0.5), throwsArgumentError);
        expect(() => completion.copyWith(target: 2), throwsArgumentError);
        expect(() => completion.copyWith(unit: 'days'), throwsArgumentError);
        expect(
          () => completion.copyWith(source: GoalSource.habits),
          throwsArgumentError,
        );
        expect(
          () => _goal(
            measurement: GoalMeasurement.percentage,
            unit: '',
            current: 101,
          ),
          throwsArgumentError,
        );
        expect(
          () => _goal(
            measurement: GoalMeasurement.currency,
            unit: '',
            currency: 'usd',
          ),
          throwsArgumentError,
        );
        expect(
          () => _goal(
            measurement: GoalMeasurement.currency,
            unit: 'EUR',
            currency: 'USD',
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('GoalHabitLink records', () {
    test(
      'support is the default and needs neither a signature nor a window',
      () {
        final habit = _habit();
        final link = GoalHabitLink.forHabit(
          meta: _meta('link'),
          goalId: 'goal',
          habit: habit,
        );
        expect(link.role, GoalHabitRole.supporting);
        expect(link.sourceSignature, isNull);
        expect(link.startDate, isNull);
        expect(GoalHabitLink.fromMap(link.toMap()).toMap(), link.toMap());
      },
    );

    test('contributors round trip settings and all metadata', () {
      final habit = _habit(
        kind: HabitKind.quantitative,
        quantKind: QuantKind.time,
        interval: HabitInterval.weekly,
        targetFrequency: 2,
        restDays: [DateTime.sunday],
        vacations: [
          VacationPeriod(
            start: DateTime(2026, 1, 3),
            end: DateTime(2026, 1, 4),
          ),
        ],
      );
      final link =
          _link(
            habit,
            metric: HabitGoalMetric.duration,
            unit: 'hours',
            endDate: '01-02-2026',
          ).copyWith(
            meta: _meta(
              'new-link',
            ).revise(at: DateTime(2026, 1, 2), archived: true),
          );
      final restored = GoalHabitLink.fromMap(
        RecordReader.object(jsonDecode(jsonEncode(link.toMap()))),
      );
      expect(restored.toMap(), link.toMap());
      expect(restored.toMap()['metric'], 'duration');
      expect(restored.toMap()['role'], 'contributor');
      expect(restored.isArchived, isTrue);
      expect(() => restored.validateHabit(habit), returnsNormally);
      final support = restored.copyWith(
        role: GoalHabitRole.supporting,
        clearStartDate: true,
        clearEndDate: true,
        clearSourceSignature: true,
      );
      expect([
        support.startDate,
        support.endDate,
        support.sourceSignature,
      ], everyElement(isNull));
    });

    test(
      'new contributions start at link creation unless history is selected',
      () {
        final link = GoalHabitLink.forHabit(
          meta: _meta('link', createdAt: DateTime(2026, 1, 8)),
          goalId: 'goal',
          habit: _habit(),
          role: GoalHabitRole.contributor,
        );
        expect(link.startDate, '08-01-2026');
        expect(link.unit, 'days');
      },
    );

    test('all contributor metrics serialize by name', () {
      for (final metric in HabitGoalMetric.values) {
        final habit = _habit(
          kind: HabitKind.quantitative,
          quantKind: metric == HabitGoalMetric.duration
              ? QuantKind.time
              : QuantKind.generic,
          unit: 'pages',
        );
        final link = _link(habit, metric: metric);
        expect(link.toMap()['metric'], metric.name);
        expect(GoalHabitLink.fromMap(link.toMap()).toMap(), link.toMap());
      }
    });

    test('invalid contributor configurations and schema are rejected', () {
      final valid = _link(_habit()).toMap();
      final invalid = <String, Object?>{
        'goalId': '',
        'habitId': '',
        'role': 'measured',
        'metric': 2,
        'startDate': null,
        'endDate': '2026-01-20',
        'unit': 'pages',
        'sourceSignature': null,
      };
      for (final entry in invalid.entries) {
        expect(
          () => GoalHabitLink.fromMap({...valid, entry.key: entry.value}),
          throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
          reason: entry.key,
        );
      }
      expect(
        () => _link(_habit(), metric: HabitGoalMetric.quantity),
        throwsArgumentError,
      );
      expect(
        () => _link(_habit(), metric: HabitGoalMetric.duration),
        throwsArgumentError,
      );
      expect(
        () =>
            _link(_habit(), metric: HabitGoalMetric.consistency, unit: 'days'),
        throwsArgumentError,
      );
      expect(
        () => _link(_habit(perDayTarget: double.nan)),
        throwsArgumentError,
      );
      expect(
        () =>
            _link(_habit(interval: HabitInterval.everyXDays, scheduleEvery: 0)),
        throwsArgumentError,
      );
      expect(
        () => _link(_habit(interval: HabitInterval.weekdays)),
        throwsArgumentError,
      );
      expect(() => _link(_habit(restDays: [8])), throwsArgumentError);
      expect(
        () => _link(_habit(interval: HabitInterval.weekly, targetFrequency: 8)),
        throwsArgumentError,
      );
    });

    test(
      'signatures ignore appearance and logs but detect measurement edits',
      () {
        final habit = _habit(
          kind: HabitKind.quantitative,
          unit: 'pages',
          restDays: [DateTime.saturday, DateTime.sunday],
        );
        final link = _link(habit, metric: HabitGoalMetric.quantity);
        final appearance = habit.copyWith(
          name: 'Renamed',
          color: const Color(0xFF000000),
          completions: _records({'02-01-2026': 20}),
          restDays: [DateTime.sunday, DateTime.saturday],
          archivedAt: DateTime(2026, 1, 5),
        );
        expect(() => link.validateHabit(appearance), returnsNormally);
        for (final changed in [
          habit.copyWith(unitLabel: 'books'),
          habit.copyWith(perDayTarget: 5),
          habit.copyWith(interval: HabitInterval.weekly),
          habit.copyWith(restDays: []),
          habit.copyWith(
            vacations: [VacationPeriod(start: DateTime(2026, 1, 2))],
          ),
          habit.copyWith(createdAt: DateTime(2026, 1, 2)),
        ]) {
          expect(() => link.validateHabit(changed), throwsStateError);
        }
        final checklist = _habit(
          substeps: [const Substep(id: 'one', title: 'One')],
        );
        expect(
          () => _link(checklist).validateHabit(
            checklist.copyWith(
              substeps: [const Substep(id: 'two', title: 'Two')],
            ),
          ),
          throwsStateError,
        );
      },
    );
  });

  group('manual and work progress', () {
    test('standalone milestone state is independent of status', () {
      final goal = Goal(
        meta: _meta('goal'),
        title: 'Finish',
        status: GoalStatus.achieved,
      );
      final progress = GoalProgress.compute(goal: goal, asOf: DateTime(2026));
      expect(progress.value, 0);
      expect(progress.reachedTarget, isFalse);
      expect(
        GoalProgress.compute(
          goal: goal.copyWith(current: 1),
          asOf: DateTime(2026),
        ).reachedTarget,
        isTrue,
      );
    });

    test('raw manual values, decreasing targets and over-target clamping', () {
      for (final values in [
        [0.0, 25.0, 100.0, 0.25],
        [10.0, 30.0, 20.0, 1.0],
        [100.0, 40.0, 20.0, 0.75],
        [100.0, 10.0, 20.0, 1.0],
        [100.0, 120.0, 20.0, 0.0],
        [0.0, -10.0, 100.0, 0.0],
      ]) {
        final goal = _goal(
          source: GoalSource.manual,
          baseline: values[0],
          current: values[1],
          target: values[2],
        );
        final progress = GoalProgress.compute(goal: goal, asOf: DateTime(2026));
        expect(progress.value, values[1]);
        expect(progress.fraction, values[3]);
      }
    });

    test('support links never modify a manually measured outcome', () {
      final goal = _goal(source: GoalSource.manual, current: 20);
      final link = GoalHabitLink(
        meta: _meta('link'),
        goalId: goal.id,
        habitId: 'missing',
      );
      final progress = GoalProgress.compute(
        goal: goal,
        links: [link],
        asOf: DateTime(2026),
      );
      expect(progress.value, 20);
      expect(progress.fraction, 0.2);
    });

    test('work receives only a validated normalized delivery fraction', () {
      final goal = _goal(
        source: GoalSource.work,
        measurement: GoalMeasurement.percentage,
        unit: '',
      );
      final progress = GoalProgress.compute(
        goal: goal,
        asOf: DateTime(2026),
        workFraction: 0.4,
      );
      expect(progress.value, 40);
      expect(progress.fraction, 0.4);
      for (final fraction in [null, -0.1, 1.1, double.nan, double.infinity]) {
        expect(
          () => GoalProgress.compute(
            goal: goal,
            asOf: DateTime(2026),
            workFraction: fraction,
          ),
          throwsArgumentError,
        );
      }
      expect(() => goal.copyWith(target: 50), throwsArgumentError);
      expect(() => _goal(source: GoalSource.work), throwsArgumentError);
    });
  });

  group('fresh canonical habit contributions', () {
    test('completed days use the daily target, not taps or partial counts', () {
      final habit = _habit(
        perDayTarget: 2,
        completions: {
          '01-01-2026': const Completion(
            date: '01-01-2026',
            count: 8,
            marks: [60, 61, 62],
          ),
          '02-01-2026': const Completion(date: '02-01-2026', count: 1),
          '03-01-2026': const Completion(date: '03-01-2026', count: 2),
        },
      );
      expect(_progress(habit).value, 2);
    });

    test('checklists require all step IDs regardless of the stored count', () {
      final habit = _habit(
        substeps: [
          const Substep(id: 'one', title: 'One'),
          const Substep(id: 'two', title: 'Two'),
        ],
        completions: {
          '01-01-2026': const Completion(
            date: '01-01-2026',
            count: 99,
            steps: {'one'},
          ),
          '02-01-2026': const Completion(
            date: '02-01-2026',
            count: 2,
            steps: {'one', 'two'},
          ),
        },
      );
      expect(_progress(habit).value, 1);
    });

    test(
      'date windows intersect and exclude before creation and future logs',
      () {
        final habit = _habit(
          createdAt: DateTime(2026, 1, 3),
          completions: _records({
            '01-01-2026': 1,
            '02-01-2026': 1,
            '03-01-2026': 1,
            '04-01-2026': 1,
            '05-01-2026': 1,
            '06-01-2026': 1,
          }),
        );
        expect(
          _progress(
            habit,
            goal: _goal(startDate: '02-01-2026', endDate: '05-01-2026'),
            link: _link(habit, startDate: '01-01-2026', endDate: '06-01-2026'),
            asOf: DateTime(2026, 1, 4, 12),
          ).value,
          2,
        );
        expect(
          _progress(
            habit,
            link: _link(habit, startDate: '04-01-2026', endDate: '04-01-2026'),
          ).value,
          1,
        );
        expect(_progress(habit, goal: _goal(startDate: '01-02-2026')).value, 0);
      },
    );

    test(
      'goal creation is a safe default, with explicit opt-in for old logs',
      () {
        final habit = _habit(
          completions: _records({'02-01-2026': 1, '09-01-2026': 1}),
        );
        final goal = _goal(
          startDate: null,
        ).copyWith(meta: _meta('goal', createdAt: DateTime(2026, 1, 8)));
        expect(_progress(habit, goal: goal).value, 1);
        expect(
          _progress(habit, goal: goal.copyWith(startDate: '01-01-2026')).value,
          2,
        );
      },
    );

    test('undo and backfill recompute even with the same Habit instance', () {
      final records = _records({'01-01-2026': 1});
      final habit = _habit(completions: records);
      final link = _link(habit);
      expect(_progress(habit, link: link).value, 1);
      records['02-01-2026'] = const Completion(date: '02-01-2026');
      expect(_progress(habit, link: link).value, 2);
      records.remove('01-01-2026');
      expect(_progress(habit, link: link).value, 1);
      final before = jsonEncode(habit.toMap());
      _progress(habit, goal: _goal(target: 1), link: link);
      expect(jsonEncode(habit.toMap()), before);
    });

    test(
      'quantities retain partial and off-schedule activity with exact units',
      () {
        final habit = _habit(
          kind: HabitKind.quantitative,
          unit: 'pages',
          perDayTarget: 20,
          restDays: [DateTime.saturday],
          completions: _records({'01-01-2026': 2.5, '03-01-2026': 30}),
        );
        final link = _link(habit, metric: HabitGoalMetric.quantity);
        final progress = _progress(
          habit,
          goal: _goal(unit: 'pages', target: 30),
          link: link,
        );
        expect(progress.value, 32.5);
        expect(progress.fraction, 1);
        expect(
          () => _progress(
            habit,
            goal: _goal(unit: 'books'),
            link: link,
          ),
          throwsArgumentError,
        );
        expect(
          () => _link(habit, metric: HabitGoalMetric.quantity, unit: 'books'),
          throwsStateError,
        );
      },
    );

    test(
      'duration converts native minutes once and never treats focus as extra time',
      () {
        final habit = _habit(
          kind: HabitKind.quantitative,
          quantKind: QuantKind.time,
          perDayTarget: 60,
          completions: _records({'01-01-2026': 90, '02-01-2026': 30}),
        ).copyWith(focusMinutes: 90);
        expect(
          _progress(
            habit,
            goal: _goal(unit: 'hours', target: 10),
            link: _link(habit, metric: HabitGoalMetric.duration, unit: 'hours'),
          ).value,
          2,
        );
        expect(
          _progress(
            habit,
            goal: _goal(unit: 'minutes', target: 200),
            link: _link(habit, metric: HabitGoalMetric.duration),
          ).value,
          120,
        );
        expect(
          () => _link(habit, metric: HabitGoalMetric.quantity),
          throwsArgumentError,
        );
        expect(
          () => _link(habit, metric: HabitGoalMetric.duration, unit: 'seconds'),
          throwsArgumentError,
        );
      },
    );

    test(
      'duration sums native minutes before converting across records and habits',
      () {
        final habits = [
          for (var i = 1; i <= 6; i++)
            _habit(
              id: 'time-$i',
              kind: HabitKind.quantitative,
              quantKind: QuantKind.time,
              completions: _records({'01-01-2026': 10}),
            ),
        ];
        final progress = GoalProgress.compute(
          goal: _goal(unit: 'hours', target: 1),
          links: [
            for (final habit in habits)
              _link(habit, metric: HabitGoalMetric.duration, unit: 'hours'),
          ],
          habits: {for (final habit in habits) habit.id: habit},
          asOf: DateTime(2026, 1, 10),
        );
        expect(progress.value, 1);
        expect(progress.reachedTarget, isTrue);
      },
    );

    test('currency quantities must name the exact currency', () {
      final habit = _habit(
        kind: HabitKind.quantitative,
        unit: 'USD',
        completions: _records({'01-01-2026': 25}),
      );
      final link = _link(habit, metric: HabitGoalMetric.quantity);
      final goal = _goal(
        measurement: GoalMeasurement.currency,
        unit: '',
        currency: 'USD',
      );
      expect(_progress(habit, goal: goal, link: link).value, 25);
      expect(
        () => _progress(
          habit,
          goal: goal.copyWith(currency: 'EUR'),
          link: link,
        ),
        throwsArgumentError,
      );
    });

    test(
      'support and deleted links do not contribute; archived logs remain',
      () {
        final habit = _habit(
          completions: _records({'01-01-2026': 1}),
          archivedAt: DateTime(2026, 1, 2),
        );
        final support = GoalHabitLink(
          meta: _meta('support'),
          goalId: 'goal',
          habitId: 'missing',
        );
        final removed = support.copyWith(
          habitId: habit.id,
          meta: support.meta.revise(at: DateTime(2026, 1, 2), deleted: true),
        );
        final progress = GoalProgress.compute(
          goal: _goal(),
          links: [_link(habit), support, removed],
          habits: {habit.id: habit},
          asOf: DateTime(2026, 1, 10),
        );
        expect(progress.value, 1);
      },
    );

    test(
      'missing sources, duplicate pairs and incompatible metrics fail explicitly',
      () {
        final habit = _habit();
        final link = _link(habit);
        expect(
          () => GoalProgress.compute(goal: _goal(), asOf: DateTime(2026)),
          throwsStateError,
        );
        expect(
          () => GoalProgress.compute(
            goal: _goal(),
            links: [link],
            asOf: DateTime(2026),
          ),
          throwsStateError,
        );
        expect(
          () => GoalProgress.compute(
            goal: _goal(),
            links: [
              link,
              link.copyWith(meta: _meta('other')),
            ],
            habits: {habit.id: habit},
            asOf: DateTime(2026),
          ),
          throwsStateError,
        );
        expect(
          () => _progress(habit.copyWith(perDayTarget: 2), link: link),
          throwsStateError,
        );
        expect(
          () => _progress(
            habit,
            link: link.copyWith(sourceSignature: 'unknown-version'),
          ),
          throwsStateError,
        );
        expect(() => link.validateHabit(_habit(id: 'wrong')), throwsStateError);
        final quantity = _habit(
          id: 'quantity',
          kind: HabitKind.quantitative,
          unit: 'days',
        );
        expect(
          () => GoalProgress.compute(
            goal: _goal(),
            links: [
              link,
              _link(quantity, metric: HabitGoalMetric.quantity),
            ],
            habits: {habit.id: habit, quantity.id: quantity},
            asOf: DateTime(2026, 1, 10),
          ),
          throwsArgumentError,
        );
        expect(
          () => _progress(habit, goal: _goal(baseline: 100, target: 0)),
          throwsArgumentError,
        );
      },
    );

    test('compatible sources sum once per distinct habit', () {
      final one = _habit(id: 'one', completions: _records({'01-01-2026': 10}));
      final two = _habit(id: 'two', completions: _records({'01-01-2026': 20}));
      expect(
        GoalProgress.compute(
          goal: _goal(),
          links: [_link(one), _link(two)],
          habits: {one.id: one, two.id: two},
          asOf: DateTime(2026, 1, 10),
        ).value,
        2,
      );
    });

    test(
      'noncanonical or nonfinite Completion records cannot manufacture progress',
      () {
        for (final records in [
          {'2026-01-01': const Completion(date: '2026-01-01')},
          {'01-01-2026': const Completion(date: '02-01-2026')},
          {
            '01-01-2026': const Completion(
              date: '01-01-2026',
              count: double.nan,
            ),
          },
          {'01-01-2026': const Completion(date: '01-01-2026', count: -1)},
        ]) {
          expect(
            () => _progress(_habit(completions: records)),
            throwsA(anyOf(isA<ArgumentError>(), isA<StateError>())),
          );
        }
        final huge = _habit(
          kind: HabitKind.quantitative,
          unit: 'items',
          completions: _records({'01-01-2026': 1e308, '02-01-2026': 1e308}),
        );
        expect(
          () => _progress(
            huge,
            goal: _goal(unit: 'items'),
            link: _link(huge, metric: HabitGoalMetric.quantity),
          ),
          throwsStateError,
        );
      },
    );

    test('negative habits credit only finished eligible clean days', () {
      final habit = _habit(
        kind: HabitKind.negative,
        restDays: [DateTime.saturday, DateTime.sunday],
        completions: _records({'02-01-2026': 1}),
      );
      expect(_progress(habit, asOf: DateTime(2026, 1, 5, 23)).value, 1);
      expect(_progress(habit, asOf: DateTime(2026, 1, 1, 23)).value, 0);
      expect(
        _progress(
          habit,
          goal: _goal(endDate: '31-12-2026'),
          asOf: DateTime(2026, 1, 3),
        ).value,
        1,
      );
      expect(
        _progress(
          habit.copyWith(archivedAt: DateTime(2026, 1, 3)),
          asOf: DateTime(2026, 1, 20),
        ).value,
        1,
      );
      final paused = habit.copyWith(
        vacations: [VacationPeriod(start: DateTime(2026, 1, 1))],
      );
      expect(_progress(paused).value, 0);
    });

    test('logical asOf does not receive the custom cutoff twice', () {
      final previous = AppClock.cutoffHour;
      AppClock.cutoffHour = 4;
      addTearDown(() => AppClock.cutoffHour = previous);
      final wall = DateTime(2026, 1, 3, 2);
      final logical = wall.subtract(Duration(hours: AppClock.cutoffHour));
      final habit = _habit(
        completions: _records({'02-01-2026': 1, '03-01-2026': 1}),
      );
      expect(_progress(habit, asOf: logical).value, 1);
    });

    test('creation before the cutoff starts on the persisted logical day', () {
      final previous = AppClock.cutoffHour;
      AppClock.cutoffHour = 4;
      addTearDown(() => AppClock.cutoffHour = previous);
      final wall = DateTime(2026, 1, 3, 2);
      final logical = wall.subtract(const Duration(hours: 4));
      final habit = _habit(completions: _records({'02-01-2026': 1}));
      final goal = Goal(
        meta: _meta('night-goal', createdAt: wall),
        title: 'Keep showing up',
        source: GoalSource.habits,
        measurement: GoalMeasurement.number,
        unit: 'days',
        target: 10,
      );
      final link = GoalHabitLink.forHabit(
        meta: _meta('night-link', createdAt: wall),
        goalId: goal.id,
        habit: habit,
        role: GoalHabitRole.contributor,
      );
      expect(link.startDate, '02-01-2026');
      final encodedGoal = goal.toMap();
      final encodedLink = link.toMap();
      AppClock.cutoffHour = 0;
      final restored = Goal.fromMap(encodedGoal);
      expect(restored.meta.createdDay, '02-01-2026');
      expect(
        GoalProgress.compute(
          goal: restored,
          links: [GoalHabitLink.fromMap(encodedLink)],
          habits: {habit.id: habit},
          asOf: logical,
        ).value,
        1,
      );
      expect(restored.meta.revise(at: wall).createdDay, '02-01-2026');
    });

    test(
      'unreasonably long enumeration windows fail rather than loop unbounded',
      () {
        final habit = _habit(
          kind: HabitKind.negative,
          createdAt: DateTime(1800),
        );
        expect(
          () => _progress(
            habit,
            goal: _goal(startDate: '01-01-1800'),
            link: _link(habit, startDate: '01-01-1800'),
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('schedule-based consistency', () {
    test(
      'daily opportunities exclude weekends, vacations and unfinished today',
      () {
        final habit = _habit(
          restDays: [DateTime.saturday, DateTime.sunday],
          completions: _records({'01-01-2026': 1}),
        );
        expect(_consistency(habit, DateTime(2026, 1, 5, 12)).value, 50);
        final doneToday = habit.copyWith(
          completions: _records({'01-01-2026': 1, '05-01-2026': 1}),
        );
        expect(
          _consistency(doneToday, DateTime(2026, 1, 5, 12)).value,
          closeTo(200 / 3, 1e-8),
        );
        final paused = habit.copyWith(
          vacations: [
            VacationPeriod(
              start: DateTime(2026, 1, 2),
              end: DateTime(2026, 1, 2),
            ),
          ],
        );
        expect(_consistency(paused, DateTime(2026, 1, 5, 12)).value, 100);
      },
    );

    test('weekday schedules count only selected opportunities', () {
      final habit = _habit(
        createdAt: DateTime(2026, 1, 5),
        interval: HabitInterval.weekdays,
        scheduleWeekdays: [DateTime.monday, DateTime.wednesday],
        completions: _records({'05-01-2026': 1, '06-01-2026': 1}),
      );
      expect(_consistency(habit, DateTime(2026, 1, 12, 12)).value, 50);
      expect(
        _consistency(
          habit.copyWith(restDays: [DateTime.wednesday]),
          DateTime(2026, 1, 12, 12),
        ).value,
        100,
      );
    });

    test(
      'weekly targets measure periods, without prematurely failing this week',
      () {
        final habit = _habit(
          createdAt: DateTime(2026, 1, 5),
          interval: HabitInterval.weekly,
          targetFrequency: 2,
          completions: _records({
            '05-01-2026': 4,
            '06-01-2026': 1,
            '12-01-2026': 1,
            '19-01-2026': 1,
          }),
        );
        expect(_consistency(habit, DateTime(2026, 1, 21)).value, 50);
        final done = habit.copyWith(
          completions: {
            ...habit.completions,
            '20-01-2026': const Completion(date: '20-01-2026'),
          },
        );
        expect(
          _consistency(done, DateTime(2026, 1, 21)).value,
          closeTo(200 / 3, 1e-8),
        );
        final paused = habit.copyWith(
          vacations: [
            VacationPeriod(
              start: DateTime(2026, 1, 12),
              end: DateTime(2026, 1, 18),
            ),
          ],
        );
        expect(_consistency(paused, DateTime(2026, 1, 21)).value, 100);
      },
    );

    test('weekly tap counts cannot stand in for distinct completed days', () {
      final habit = _habit(
        createdAt: DateTime(2026, 1, 5),
        interval: HabitInterval.weekly,
        targetFrequency: 2,
        completions: _records({'05-01-2026': 100}),
      );
      expect(_consistency(habit, DateTime(2026, 1, 12)).value, 0);
    });

    test(
      'clipped or unavailable periods are neutral, not invented lower targets',
      () {
        final habit = _habit(
          createdAt: DateTime(2026, 1, 8),
          interval: HabitInterval.weekly,
          targetFrequency: 2,
          completions: _records({'08-01-2026': 1}),
        );
        expect(_consistency(habit, DateTime(2026, 1, 12)).value, 0);
        final completed = habit.copyWith(
          completions: {
            ...habit.completions,
            '09-01-2026': const Completion(date: '09-01-2026'),
          },
        );
        expect(_consistency(completed, DateTime(2026, 1, 12)).value, 100);
        final unavailable = _habit(
          createdAt: DateTime(2026, 1, 5),
          interval: HabitInterval.weekly,
          targetFrequency: 2,
          vacations: [
            VacationPeriod(
              start: DateTime(2026, 1, 6),
              end: DateTime(2026, 1, 11),
            ),
          ],
          completions: _records({'05-01-2026': 1}),
        );
        expect(_consistency(unavailable, DateTime(2026, 1, 12)).value, 0);
      },
    );

    test(
      'monthly periods use calendar boundaries and leave this month open',
      () {
        final habit = _habit(
          interval: HabitInterval.monthly,
          targetFrequency: 2,
          completions: _records({
            '01-01-2026': 1,
            '31-01-2026': 1,
            '01-02-2026': 1,
            '01-03-2026': 1,
          }),
        );
        expect(_consistency(habit, DateTime(2026, 3, 10)).value, 50);
        final done = habit.copyWith(
          completions: {
            ...habit.completions,
            '02-03-2026': const Completion(date: '02-03-2026'),
          },
        );
        expect(
          _consistency(done, DateTime(2026, 3, 10)).value,
          closeTo(200 / 3, 1e-8),
        );
        final paused = habit.copyWith(
          vacations: [
            VacationPeriod(
              start: DateTime(2026, 2, 1),
              end: DateTime(2026, 2, 28),
            ),
          ],
        );
        expect(_consistency(paused, DateTime(2026, 3, 10)).value, 100);
      },
    );

    test(
      'every-N opportunities use the creation anchor and early completion once',
      () {
        final habit = _habit(
          interval: HabitInterval.everyXDays,
          scheduleEvery: 3,
          completions: _records({
            '01-01-2026': 1,
            '03-01-2026': 1,
            '08-01-2026': 1,
          }),
        );
        expect(_consistency(habit, DateTime(2026, 1, 7, 12)).value, 100);
        expect(
          _consistency(habit, DateTime(2026, 1, 8, 12)).value,
          closeTo(200 / 3, 1e-8),
        );
        expect(_consistency(habit, DateTime(2026, 1, 10, 12)).value, 75);
        final paused = habit.copyWith(
          vacations: [
            VacationPeriod(
              start: DateTime(2026, 1, 7),
              end: DateTime(2026, 1, 7),
            ),
          ],
        );
        expect(_consistency(paused, DateTime(2026, 1, 8, 12)).value, 100);
      },
    );

    test(
      'every-N early completions outside the selected window do not count',
      () {
        final habit = _habit(
          interval: HabitInterval.everyXDays,
          scheduleEvery: 3,
          completions: _records({'03-01-2026': 1}),
        );
        expect(
          _progress(
            habit,
            goal: _goal(
              measurement: GoalMeasurement.percentage,
              unit: '',
              startDate: '04-01-2026',
            ),
            link: _link(habit, metric: HabitGoalMetric.consistency),
            asOf: DateTime(2026, 1, 5),
          ).value,
          0,
        );
      },
    );

    test(
      'compatible consistency sources pool opportunities, not percentages',
      () {
        final one = _habit(id: 'one', completions: _records({'01-01-2026': 1}));
        final two = _habit(id: 'two');
        final goal = _goal(measurement: GoalMeasurement.percentage, unit: '');
        expect(
          GoalProgress.compute(
            goal: goal,
            links: [
              _link(
                one,
                metric: HabitGoalMetric.consistency,
                endDate: '01-01-2026',
              ),
              _link(
                two,
                metric: HabitGoalMetric.consistency,
                endDate: '03-01-2026',
              ),
            ],
            habits: {one.id: one, two.id: two},
            asOf: DateTime(2026, 1, 4),
          ).value,
          25,
        );
        final weekly = two.copyWith(interval: HabitInterval.weekly);
        expect(
          () => GoalProgress.compute(
            goal: goal,
            links: [
              _link(one, metric: HabitGoalMetric.consistency),
              _link(weekly, metric: HabitGoalMetric.consistency),
            ],
            habits: {one.id: one, weekly.id: weekly},
            asOf: DateTime(2026, 1, 4),
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'negative and archived sources do not gain future clean opportunities',
      () {
        final habit = _habit(
          kind: HabitKind.negative,
          completions: _records({'01-01-2026': 1}),
        );
        expect(_consistency(habit, DateTime(2026, 1, 2, 23)).value, 0);
        expect(_consistency(habit, DateTime(2026, 1, 3)).value, 50);
        final archived = habit.copyWith(archivedAt: DateTime(2026, 1, 3));
        expect(_consistency(archived, DateTime(2026, 2, 1)).value, 50);
        final fresh = _habit(kind: HabitKind.negative);
        expect(
          _consistency(fresh, DateTime(2026, 1, 1, 23)).reachedTarget,
          isFalse,
        );
      },
    );
  });
}
