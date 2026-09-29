import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_day_plan.dart';

class ReminderSchedule {
  const ReminderSchedule._();

  static const slotsPerReminder = 64;

  static int notificationId(String habitId, String reminderId, int slot) {
    final habit = habitId.hashCode.abs() % 10000;
    final reminder = reminderId.hashCode.abs() % 100;
    return (habit * 100 + reminder) * slotsPerReminder + slot;
  }

  static const maxHourlyPerDay = 8;

  static List<int> hourlySlots({
    required int hour,
    required int minute,
    required int everyHours,
  }) {
    if (everyHours < 1) return [hour * 60 + minute];
    final start = hour * 60 + minute;
    final step = everyHours * 60;
    final slots = <int>[];
    for (
      var at = start;
      at < 24 * 60 && slots.length < maxHourlyPerDay;
      at += step
    ) {
      slots.add(at);
    }
    return slots;
  }

  static int hourlyId(String habitId, String reminderId, int day, int slot) =>
      notificationId(habitId, reminderId, (day - 1) * maxHourlyPerDay + slot);

  static const todoIdBase = 1000000000;

  static int todoNotificationId(String todoId) =>
      todoIdBase + todoId.hashCode.abs() % 100000000;

  static DateTime? todoFireAt({
    required DateTime now,
    required bool done,
    DateTime? due,
    int? minutes,
  }) {
    if (done || due == null || minutes == null) return null;
    final at = DateTime(due.year, due.month, due.day).add(
      Duration(minutes: minutes),
    );
    return at.isAfter(now) ? at : null;
  }

  static DateTime nextWeekly({
    required DateTime now,
    required int weekday,
    required int hour,
    required int minute,
  }) {
    var when = DateTime(now.year, now.month, now.day, hour, minute);
    while (when.weekday != weekday) {
      when = when.add(const Duration(days: 1));
    }
    return when.isBefore(now) ? when.add(const Duration(days: 7)) : when;
  }

  static const workPayloadPrefix = 'work:';
  static const workIdBase = 1200000000;
  static const workSnoozeIdBase = 1700000000;
  static const maxWorkRemindersPerTask = 10;
  static const maxScheduledWorkReminders = 64;
  static const _workIdRange = 500000000;
  static const _workSnoozeIdRange = 400000000;

  static String workPayload(String taskId) => '$workPayloadPrefix$taskId';

  static int workNotificationId(String taskId, DateTime at) =>
      workIdBase +
      _stableHash('$taskId|${at.toUtc().toIso8601String()}') % _workIdRange;

  static int workSnoozeNotificationId(String taskId) =>
      workSnoozeIdBase + _stableHash('snooze|$taskId') % _workSnoozeIdRange;

  static List<WorkReminderSpec> workReminderSpecs(
    WorkData data, {
    required DateTime now,
    int maxNotifications = maxScheduledWorkReminders,
    Map<String, DateTime> snoozes = const {},
  }) {
    final specs = <WorkReminderSpec>[];
    final usedIds = <int>{};
    void addSpec(WorkReminderSpec spec) {
      var id = spec.id;
      while (!usedIds.add(id)) {
        id++;
        if (id >= workSnoozeIdBase + _workSnoozeIdRange) id = workIdBase;
      }
      specs.add(spec.copyWith(id: id));
    }

    for (final task in data.tasks) {
      if (!WorkPlanProjection.shouldScheduleTask(data, task)) continue;
      final reminders = {
        for (final instant in task.reminders)
          if (instant.toUtc().isAfter(now.toUtc())) instant.toUtc(),
      }.toList()..sort();
      for (final at in reminders.take(maxWorkRemindersPerTask)) {
        addSpec(
          WorkReminderSpec(
            id: workNotificationId(task.id, at),
            taskId: task.id,
            title: task.title,
            body: task.description.trim().isEmpty
                ? ''
                : task.description.trim(),
            at: at,
            payload: workPayload(task.id),
          ),
        );
      }
      final snoozeAt = snoozes[task.id]?.toUtc();
      if (snoozeAt != null && snoozeAt.isAfter(now.toUtc())) {
        addSpec(
          WorkReminderSpec(
            id: workSnoozeNotificationId(task.id),
            taskId: task.id,
            title: task.title,
            body: task.description.trim().isEmpty
                ? ''
                : task.description.trim(),
            at: snoozeAt,
            payload: workPayload(task.id),
          ),
        );
      }
    }
    specs.sort((a, b) {
      final at = a.at.compareTo(b.at);
      if (at != 0) return at;
      return a.id.compareTo(b.id);
    });
    return List.unmodifiable(specs.take(maxNotifications));
  }

  static bool isWorkNotificationId(int id) =>
      (id >= workIdBase && id < workIdBase + _workIdRange) ||
      (id >= workSnoozeIdBase && id < workSnoozeIdBase + _workSnoozeIdRange);

  static bool isWorkPayload(String? payload) =>
      payload?.startsWith(workPayloadPrefix) ?? false;

  static String workTaskIdFromPayload(String payload) =>
      payload.substring(workPayloadPrefix.length);

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

class WorkReminderSpec {
  const WorkReminderSpec({
    required this.id,
    required this.taskId,
    required this.title,
    required this.body,
    required this.at,
    required this.payload,
  });

  final int id;
  final String taskId;
  final String title;
  final String body;
  final DateTime at;
  final String payload;

  WorkReminderSpec copyWith({int? id, String? body}) => WorkReminderSpec(
    id: id ?? this.id,
    taskId: taskId,
    title: title,
    body: body ?? this.body,
    at: at,
    payload: payload,
  );
}

enum WorkReminderFailure {
  permissionDenied,
  platformUnsupported,
  schedulingFailed,
  capacityLimited,
}

class WorkReminderSchedulingException implements Exception {
  const WorkReminderSchedulingException(this.failure, [this.cause]);

  final WorkReminderFailure failure;
  final Object? cause;

  @override
  String toString() => 'Work reminder scheduling failed: $failure';
}
