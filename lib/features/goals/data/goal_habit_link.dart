import 'dart:convert';

import 'package:streak/core/data/record.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/habits/data/habit.dart';

enum GoalHabitRole { supporting, contributor }

enum HabitGoalMetric { completedDays, quantity, duration, consistency }

class GoalHabitLink extends StoredRecord {
  GoalHabitLink({
    required RecordMeta meta,
    required this.goalId,
    required this.habitId,
    this.role = GoalHabitRole.supporting,
    this.metric = HabitGoalMetric.completedDays,
    this.startDate,
    this.endDate,
    this.unit = '',
    this.sourceSignature,
  }) : super(meta) {
    requireText(goalId, 'goalId');
    requireText(habitId, 'habitId');
    requireOptionalId(sourceSignature, 'sourceSignature');
    requireDayRange(startDate, endDate);
    if (unit != unit.trim()) {
      throw ArgumentError('unit cannot have outer spaces');
    }
    if (role == GoalHabitRole.contributor) {
      if (startDate == null || sourceSignature == null) {
        throw ArgumentError(
          'Contributors need a start date and source signature',
        );
      }
      requireText(unit, 'unit');
      switch (metric) {
        case HabitGoalMetric.completedDays:
          if (unit != 'days') {
            throw ArgumentError('Completed-day contributions use days');
          }
        case HabitGoalMetric.duration:
          if (unit != 'minutes' && unit != 'hours') {
            throw ArgumentError('Duration contributions use minutes or hours');
          }
        case HabitGoalMetric.consistency:
          if (unit != '%') {
            throw ArgumentError('Consistency contributions use percent');
          }
        case HabitGoalMetric.quantity:
          break;
      }
    }
  }

  final String goalId;
  final String habitId;
  final GoalHabitRole role;
  final HabitGoalMetric metric;
  final String? startDate;
  final String? endDate;
  final String unit;
  final String? sourceSignature;

  /// Existing activity is opt-in: contributors default to the link's creation
  /// day. Earlier goal and link start dates explicitly select historical logs.
  factory GoalHabitLink.forHabit({
    required RecordMeta meta,
    required String goalId,
    required Habit habit,
    GoalHabitRole role = GoalHabitRole.supporting,
    HabitGoalMetric metric = HabitGoalMetric.completedDays,
    String? startDate,
    String? endDate,
    String? unit,
  }) {
    final contributing = role == GoalHabitRole.contributor;
    final sourceUnit = switch (metric) {
      HabitGoalMetric.completedDays => 'days',
      HabitGoalMetric.quantity => habit.unitLabel,
      HabitGoalMetric.duration => 'minutes',
      HabitGoalMetric.consistency => '%',
    };
    final link = GoalHabitLink(
      meta: meta,
      goalId: goalId,
      habitId: habit.id,
      role: role,
      metric: metric,
      startDate: startDate ?? (contributing ? meta.createdDay : null),
      endDate: endDate,
      unit: unit ?? (contributing ? sourceUnit : ''),
      sourceSignature: contributing
          ? signatureFor(habit, metric: metric)
          : null,
    );
    link.validateHabit(habit);
    return link;
  }

  /// Versioned, deterministic settings snapshot, not an activity snapshot.
  /// Pauses and target/step changes also require an explicit link refresh.
  static String signatureFor(Habit habit, {required HabitGoalMetric metric}) {
    requireText(habit.id, 'habit.id');
    requireDay(habit.createdAt.dayKey, 'habit.createdAt');
    if (!habit.perDayTarget.isFinite || habit.perDayTarget <= 0) {
      throw ArgumentError('Habit targets must be finite and positive');
    }
    if (habit.targetFrequency < 1 ||
        (habit.interval == HabitInterval.weekly && habit.targetFrequency > 7) ||
        (habit.interval == HabitInterval.monthly &&
            habit.targetFrequency > 31) ||
        (habit.interval == HabitInterval.everyXDays &&
            habit.scheduleEvery < 1)) {
      throw ArgumentError('Invalid habit frequency');
    }
    _validateWeekdays(habit.scheduleWeekdays);
    _validateWeekdays(habit.restDays);
    if (habit.interval == HabitInterval.weekdays &&
        habit.scheduleWeekdays.isEmpty) {
      throw ArgumentError('A weekday habit needs scheduled weekdays');
    }
    final steps = habit.substeps.map((step) => step.id).toList()..sort();
    for (final step in steps) {
      requireText(step, 'habit.substeps.id');
    }
    if (steps.toSet().length != steps.length) {
      throw ArgumentError('Habit step IDs must be unique');
    }
    if (habit.kind == HabitKind.negative && habit.hasSubsteps) {
      throw ArgumentError(
        'Negative checklists do not have a supported measure',
      );
    }
    if (metric == HabitGoalMetric.quantity &&
        (habit.kind != HabitKind.quantitative ||
            habit.isTimeAmount ||
            habit.hasSubsteps ||
            habit.unitLabel.trim().isEmpty ||
            habit.unitLabel != habit.unitLabel.trim())) {
      throw ArgumentError(
        'Quantity requires a non-time quantitative habit with a unit',
      );
    }
    if (metric == HabitGoalMetric.duration &&
        (!habit.isTimeAmount || habit.hasSubsteps)) {
      throw ArgumentError('Duration requires a time-quantity habit');
    }
    final vacations = <String>[];
    for (final vacation in habit.vacations) {
      requireDayRange(vacation.start.dayKey, vacation.end?.dayKey);
      vacations.add('${vacation.start.dayKey}:${vacation.end?.dayKey ?? ''}');
    }
    vacations.sort();
    return jsonEncode({
      'version': 1,
      'metric': metric.name,
      'kind': habit.kind.name,
      'quantKind': habit.quantKind.name,
      'unit': habit.unitLabel,
      'perDayTarget': habit.perDayTarget,
      'interval': habit.interval.name,
      'targetFrequency': habit.targetFrequency,
      'scheduleWeekdays': habit.scheduleWeekdays.toList()..sort(),
      'scheduleEvery': habit.scheduleEvery,
      'createdOn': habit.createdAt.dayKey,
      'restDays': habit.restDays.toList()..sort(),
      'vacations': vacations.toSet().toList(),
      'steps': steps,
    });
  }

  void validateHabit(Habit habit) {
    if (habit.id != habitId) {
      throw StateError('Habit source ID does not match the link');
    }
    if (role != GoalHabitRole.contributor) return;
    if (sourceSignature != signatureFor(habit, metric: metric)) {
      throw StateError(
        'Habit measurement settings changed; refresh the link explicitly',
      );
    }
    if (metric == HabitGoalMetric.quantity && unit != habit.unitLabel) {
      throw StateError('Habit quantity unit does not match the link');
    }
  }

  @override
  Map<String, dynamic> toMap() => {
    ...meta.toMap(),
    'goalId': goalId,
    'habitId': habitId,
    'role': role.name,
    'metric': metric.name,
    'startDate': startDate,
    'endDate': endDate,
    'unit': unit,
    'sourceSignature': sourceSignature,
  };

  factory GoalHabitLink.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return GoalHabitLink(
      meta: RecordMeta.fromMap(map),
      goalId: read.string('goalId'),
      habitId: read.string('habitId'),
      role: read.enumValue('role', GoalHabitRole.values),
      metric: read.enumValue('metric', HabitGoalMetric.values),
      startDate: read.optionalString('startDate'),
      endDate: read.optionalString('endDate'),
      unit: read.string('unit', fallback: ''),
      sourceSignature: read.optionalString('sourceSignature'),
    );
  }

  GoalHabitLink copyWith({
    RecordMeta? meta,
    String? goalId,
    String? habitId,
    GoalHabitRole? role,
    HabitGoalMetric? metric,
    String? startDate,
    String? endDate,
    bool clearStartDate = false,
    bool clearEndDate = false,
    String? unit,
    String? sourceSignature,
    bool clearSourceSignature = false,
  }) => GoalHabitLink(
    meta: meta ?? this.meta,
    goalId: goalId ?? this.goalId,
    habitId: habitId ?? this.habitId,
    role: role ?? this.role,
    metric: metric ?? this.metric,
    startDate: clearStartDate ? null : (startDate ?? this.startDate),
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
    unit: unit ?? this.unit,
    sourceSignature: clearSourceSignature
        ? null
        : (sourceSignature ?? this.sourceSignature),
  );
}

void _validateWeekdays(List<int> days) {
  if (days.any((day) => day < DateTime.monday || day > DateTime.sunday) ||
      days.toSet().length != days.length) {
    throw ArgumentError('Invalid or duplicate habit weekdays');
  }
}
