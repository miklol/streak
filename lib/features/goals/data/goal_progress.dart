import 'package:streak/core/data/record.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/habits/data/completion.dart';
import 'package:streak/features/habits/data/habit.dart';

class GoalProgress {
  const GoalProgress._({required this.value, required this.fraction});

  final double value;
  final double fraction;

  bool get reachedTarget => fraction == 1;

  static const maxWindowDays = 36600;

  /// [asOf] is a logical timestamp, normally AppClock.now(), not wallNow().
  /// Date components are used without applying the day cutoff a second time.
  ///
  /// Absent goal/link starts default to their creation days; the habit's own
  /// creation is always a floor. Earlier explicit starts opt into old activity.
  /// Quantities and completed habit-days retain actual off-schedule logs.
  /// Durations use only canonical time-habit minutes, never focus-session totals.
  ///
  /// Consistency pools successful opportunities, not averages of percentages.
  /// Daily/weekday, weekly, monthly and equal every-N cadences can each pool
  /// together, but unlike cadences cannot. Partial periods can succeed early;
  /// only fully observed, closed periods with enough available days can fail.
  /// Decreasing outcomes are manual: accumulated activity is not a stock-level
  /// measurement and cannot safely infer a decrease.
  static GoalProgress compute({
    required Goal goal,
    List<GoalHabitLink> links = const [],
    Map<String, Habit> habits = const {},
    required DateTime asOf,
    double? workFraction,
  }) {
    requireDay(asOf.dayKey, 'asOf');
    final relevant = links
        .where((link) => link.goalId == goal.id && !link.isDeleted)
        .toList();
    final seenHabits = <String>{};
    for (final link in relevant) {
      if (!seenHabits.add(link.habitId)) {
        throw StateError('Duplicate goal/habit relationship');
      }
    }
    switch (goal.source) {
      case GoalSource.manual:
        return _result(goal, goal.current);
      case GoalSource.work:
        if (workFraction == null ||
            !workFraction.isFinite ||
            workFraction < 0 ||
            workFraction > 1) {
          throw ArgumentError(
            'Work goals require a finite delivery fraction from 0 to 1',
          );
        }
        return _result(goal, workFraction * 100);
      case GoalSource.habits:
        final contributing = relevant
            .where((link) => link.role == GoalHabitRole.contributor)
            .toList();
        if (contributing.isEmpty) {
          throw StateError(
            'Habit-measured goals require a contributing source',
          );
        }
        final metric = contributing.first.metric;
        var value = 0.0;
        var opportunities = 0;
        var successes = 0;
        String? cadence;
        for (final link in contributing) {
          if (link.metric != metric) {
            throw ArgumentError('Different habit metrics cannot be combined');
          }
          final habit = habits[link.habitId];
          if (habit == null) {
            throw StateError('Missing contributing habit: ${link.habitId}');
          }
          link.validateHabit(habit);
          _validateMeasurement(goal, link);
          final source = _HabitSource(habit);
          final window = _Window.forSource(
            goal,
            link,
            habit,
            asOf,
            stopAtArchive:
                metric == HabitGoalMetric.consistency ||
                habit.kind == HabitKind.negative,
          );
          if (metric == HabitGoalMetric.consistency) {
            final nextCadence = _cadence(habit);
            if (cadence != null && cadence != nextCadence) {
              throw ArgumentError(
                'Consistency sources need compatible scheduling cadences',
              );
            }
            cadence = nextCadence;
            final consistency = source.consistency(window);
            opportunities += consistency.opportunities;
            successes += consistency.successes;
          } else {
            value += source.accumulated(link, window);
            if (!value.isFinite) {
              throw StateError(
                'Habit contributions exceed the finite numeric range',
              );
            }
          }
        }
        if (metric == HabitGoalMetric.consistency) {
          value = opportunities == 0 ? 0 : successes * 100 / opportunities;
        } else if (metric == HabitGoalMetric.duration && goal.unit == 'hours') {
          value /= 60;
        }
        return _result(goal, value);
    }
  }

  static GoalProgress _result(Goal goal, double value) {
    if (!value.isFinite) throw StateError('Goal progress must be finite');
    final increasing = goal.target > goal.baseline;
    final reached = increasing ? value >= goal.target : value <= goal.target;
    final before = increasing ? value <= goal.baseline : value >= goal.baseline;
    return GoalProgress._(
      value: value,
      fraction: reached
          ? 1
          : before
          ? 0
          : ((value - goal.baseline) / (goal.target - goal.baseline)).clamp(
              0.0,
              1.0,
            ),
    );
  }
}

void _validateMeasurement(Goal goal, GoalHabitLink link) {
  if (link.metric == HabitGoalMetric.consistency) {
    if (goal.measurement != GoalMeasurement.percentage ||
        goal.baseline != 0 ||
        goal.target <= 0) {
      throw ArgumentError(
        'Consistency needs an increasing percentage goal from zero',
      );
    }
    return;
  }
  if (goal.baseline < 0 || goal.target <= goal.baseline) {
    throw ArgumentError(
      'Accumulated activity needs an increasing, nonnegative goal',
    );
  }
  if (goal.measurement == GoalMeasurement.currency &&
      link.metric == HabitGoalMetric.quantity &&
      goal.currency == link.unit) {
    return;
  }
  if (goal.measurement != GoalMeasurement.number || goal.unit != link.unit) {
    throw ArgumentError('Goal measurement and contributor unit do not match');
  }
}

String _cadence(Habit habit) => switch (habit.interval) {
  HabitInterval.daily || HabitInterval.weekdays => 'day',
  HabitInterval.weekly => 'week',
  HabitInterval.monthly => 'month',
  HabitInterval.everyXDays =>
    habit.scheduleEvery == 1 ? 'day' : 'every-${habit.scheduleEvery}-days',
};

class _Window {
  const _Window(this.start, this.end, this.maturity);

  final DateTime start;
  final DateTime end;
  final DateTime maturity;

  bool get isEmpty => start.epochDay > end.epochDay;

  bool contains(int day) => day >= start.epochDay && day <= end.epochDay;

  factory _Window.forSource(
    Goal goal,
    GoalHabitLink link,
    Habit habit,
    DateTime asOf, {
    required bool stopAtArchive,
  }) {
    var start = goal.startDate == null
        ? parseDayKey(goal.meta.createdDay)
        : parseDayKey(goal.startDate!);
    start = _later(
      start,
      link.startDate == null
          ? parseDayKey(link.meta.createdDay)
          : parseDayKey(link.startDate!),
    );
    start = _later(start, habit.createdAt.atMidnight);
    var maturity = asOf.atMidnight;
    if (stopAtArchive && habit.archivedAt != null) {
      maturity = _earlier(maturity, habit.archivedAt!.toLocal().atMidnight);
    }
    var end = maturity;
    if (goal.endDate != null) end = _earlier(end, parseDayKey(goal.endDate!));
    if (link.endDate != null) end = _earlier(end, parseDayKey(link.endDate!));
    if (end.epochDay - start.epochDay + 1 > GoalProgress.maxWindowDays) {
      throw ArgumentError(
        'Habit goal windows cannot exceed ${GoalProgress.maxWindowDays} days',
      );
    }
    return _Window(start, end, maturity);
  }
}

DateTime _later(DateTime a, DateTime b) => a.epochDay >= b.epochDay ? a : b;

DateTime _earlier(DateTime a, DateTime b) => a.epochDay <= b.epochDay ? a : b;

class _Consistency {
  const _Consistency(this.successes, this.opportunities);

  final int successes;
  final int opportunities;
}

class _HabitSource {
  _HabitSource(this.habit) {
    for (final entry in habit.completions.entries) {
      requireDay(entry.key, 'completion key');
      if (entry.key != entry.value.date) {
        throw StateError('Completion key and date must identify the same day');
      }
      if (!entry.value.count.isFinite || entry.value.count < 0) {
        throw StateError('Completion amounts must be finite and nonnegative');
      }
      entries[parseDayKey(entry.key).epochDay] = entry.value;
    }
  }

  final Habit habit;
  final Map<int, Completion> entries = {};

  bool _paused(DateTime day) =>
      habit.restDays.contains(day.weekday) ||
      habit.vacations.any(
        (vacation) =>
            day.epochDay >= vacation.start.epochDay &&
            (vacation.end == null || day.epochDay <= vacation.end!.epochDay),
      );

  bool _scheduled(DateTime day) => habit.isScheduledOn(day) && !_paused(day);

  bool _completed(DateTime day, _Window window) {
    final entry = entries[day.epochDay];
    if (habit.kind == HabitKind.negative) {
      return day.epochDay < window.maturity.epochDay &&
          _scheduled(day) &&
          entry == null;
    }
    if (entry == null) return false;
    if (habit.hasSubsteps) {
      return habit.substeps.every((step) => entry.steps.contains(step.id));
    }
    return entry.count >= habit.perDayTarget;
  }

  double accumulated(GoalHabitLink link, _Window window) {
    if (window.isEmpty) return 0;
    var value = 0.0;
    if (link.metric == HabitGoalMetric.completedDays &&
        habit.kind == HabitKind.negative) {
      for (
        var day = window.start;
        day.epochDay <= window.end.epochDay;
        day = day.addDays(1)
      ) {
        if (_completed(day, window)) value++;
      }
      return value;
    }
    for (final entry in habit.completions.entries) {
      final day = parseDayKey(entry.key);
      if (!window.contains(day.epochDay)) continue;
      if (link.metric == HabitGoalMetric.completedDays) {
        if (_completed(day, window)) value++;
      } else {
        value += entry.value.count;
      }
    }
    return value;
  }

  _Consistency consistency(_Window window) {
    if (window.isEmpty) return const _Consistency(0, 0);
    if (habit.interval == HabitInterval.weekly ||
        habit.interval == HabitInterval.monthly) {
      return _periodConsistency(window);
    }
    var successes = 0;
    var opportunities = 0;
    int? lastCompleted;
    for (
      var day = window.start;
      day.epochDay <= window.end.epochDay;
      day = day.addDays(1)
    ) {
      if (_completed(day, window)) lastCompleted = day.epochDay;
      if (!_scheduled(day)) continue;
      final done =
          habit.interval == HabitInterval.everyXDays &&
              habit.kind != HabitKind.negative
          ? lastCompleted != null &&
                lastCompleted > day.epochDay - habit.scheduleEvery
          : _completed(day, window);
      if (done || day.epochDay < window.maturity.epochDay) {
        opportunities++;
        if (done) successes++;
      }
    }
    return _Consistency(successes, opportunities);
  }

  _Consistency _periodConsistency(_Window window) {
    final weekly = habit.interval == HabitInterval.weekly;
    var periodStart = weekly
        ? window.start.startOfWeek(DateTime.monday)
        : DateTime(window.start.year, window.start.month);
    var successes = 0;
    var opportunities = 0;
    while (periodStart.epochDay <= window.end.epochDay) {
      final nextPeriod = weekly
          ? periodStart.addDays(7)
          : DateTime(periodStart.year, periodStart.month + 1);
      final periodEnd = nextPeriod.addDays(-1);
      final start = _later(periodStart, window.start);
      final end = _earlier(periodEnd, window.end);
      var completed = 0;
      var available = 0;
      for (
        var day = start;
        day.epochDay <= end.epochDay;
        day = day.addDays(1)
      ) {
        if (!_scheduled(day)) continue;
        available++;
        if (_completed(day, window)) completed++;
      }
      final done = completed >= habit.targetFrequency;
      // Do not invent a reduced weekly/monthly target when the counting window
      // or time off makes that target impossible. Such periods are neutral.
      final closed =
          periodStart.epochDay >= window.start.epochDay &&
          periodEnd.epochDay <= window.end.epochDay &&
          periodEnd.epochDay < window.maturity.epochDay &&
          available >= habit.targetFrequency;
      if (done || closed) {
        opportunities++;
        if (done) successes++;
      }
      periodStart = nextPeriod;
    }
    return _Consistency(successes, opportunities);
  }
}
