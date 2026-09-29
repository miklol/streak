import 'package:flutter/foundation.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';

enum WorkPlanConflictKind { work, habit }

@immutable
class WorkPlanConflict {
  const WorkPlanConflict({
    required this.kind,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.blockId,
    this.taskId,
    this.habitId,
  });

  final WorkPlanConflictKind kind;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? blockId;
  final String? taskId;
  final String? habitId;
}

@immutable
class WorkDayPlanItem {
  const WorkDayPlanItem({
    required this.block,
    required this.task,
    required this.startsAt,
    required this.endsAt,
    required this.startMinute,
    required this.endMinute,
    this.project,
    this.area,
    this.parent,
  });

  final WorkPlanBlock block;
  final WorkTask task;
  final WorkProject? project;
  final WorkArea? area;
  final WorkTask? parent;
  final DateTime startsAt;
  final DateTime endsAt;
  final int startMinute;
  final int endMinute;

  String get title => task.title;

  String get contextLabel {
    final parts = [
      if (parent != null) parent!.title,
      if (project != null) project!.name,
      if (area != null) area!.name,
    ];
    return parts.join(' • ');
  }

  int get plannedMinutes => block.minutes;
}

class WorkPlanProjection {
  const WorkPlanProjection._();

  static WorkTask? taskById(WorkData data, String? id) {
    if (id == null) return null;
    for (final task in data.tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  static WorkProject? projectById(WorkData data, String? id) {
    if (id == null) return null;
    for (final project in data.projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  static WorkArea? areaById(WorkData data, String? id) {
    if (id == null) return null;
    for (final area in data.areas) {
      if (area.id == id) return area;
    }
    return null;
  }

  static String? areaIdForTask(WorkData data, WorkTask task) =>
      projectById(data, task.projectId)?.areaId ?? task.areaId;

  static bool isTaskEditable(WorkData data, WorkTask task) {
    if (!_isTaskVisible(data, task, includeCompletedHistory: false)) {
      return false;
    }
    return task.status != WorkTaskStatus.done;
  }

  static bool shouldScheduleTask(WorkData data, WorkTask task) =>
      _isTaskVisible(data, task, includeCompletedHistory: false) &&
      task.status != WorkTaskStatus.done;

  static bool shouldShowBlock(
    WorkData data,
    WorkPlanBlock block, {
    DateTime? now,
  }) {
    if (block.isDeleted || block.isArchived) return false;
    final task = taskById(data, block.taskId);
    if (task == null) return false;
    if (!_isTaskVisible(data, task, includeCompletedHistory: true)) {
      return false;
    }
    if (task.status == WorkTaskStatus.done) {
      final completedAt = task.completedAt;
      if (completedAt == null) return false;
      return !block.startsAt.isAfter(completedAt.toUtc());
    }
    return true;
  }

  static bool _isTaskVisible(
    WorkData data,
    WorkTask task, {
    required bool includeCompletedHistory,
  }) {
    if (task.isDeleted || task.isArchived) return false;
    if (task.status == WorkTaskStatus.cancelled) return false;
    if (!includeCompletedHistory && task.status == WorkTaskStatus.done) {
      return false;
    }
    final parent = taskById(data, task.parentTaskId);
    if (parent != null &&
        (parent.isDeleted ||
            parent.isArchived ||
            parent.status == WorkTaskStatus.done ||
            parent.status == WorkTaskStatus.cancelled)) {
      return false;
    }
    final project = projectById(data, task.projectId);
    if (project != null &&
        (project.isDeleted ||
            project.isArchived ||
            project.status == WorkProjectStatus.done ||
            project.status == WorkProjectStatus.cancelled)) {
      return false;
    }
    final area = areaById(data, project?.areaId ?? task.areaId);
    if (area != null && (area.isDeleted || area.isArchived)) return false;
    return true;
  }

  static List<WorkPlanBlock> blocksForTask(
    WorkData data,
    String taskId, {
    DateTime? now,
  }) {
    final blocks =
        data.blocks
            .where(
              (block) =>
                  block.taskId == taskId &&
                  shouldShowBlock(data, block, now: now),
            )
            .toList()
          ..sort(_compareBlocks);
    return List.unmodifiable(blocks);
  }

  static List<WorkPlanBlock> blocksForDay(
    WorkData data,
    DateTime day, {
    DateTime? now,
  }) {
    final start = day.atMidnight;
    final end = DateTime(start.year, start.month, start.day + 1);
    final blocks =
        data.blocks
            .where(
              (block) =>
                  shouldShowBlock(data, block, now: now) &&
                  block.startsAt.toLocal().isBefore(end) &&
                  block.endsAt.toLocal().isAfter(start),
            )
            .toList()
          ..sort(_compareBlocks);
    return List.unmodifiable(blocks);
  }

  static List<WorkDayPlanItem> itemsForDay(
    WorkData data,
    DateTime day, {
    DateTime? now,
  }) {
    final start = day.atMidnight;
    final end = DateTime(start.year, start.month, start.day + 1);
    final items = <WorkDayPlanItem>[];
    for (final block in blocksForDay(data, day, now: now)) {
      final task = taskById(data, block.taskId);
      if (task == null) continue;
      final localStart = block.startsAt.toLocal();
      final localEnd = block.endsAt.toLocal();
      final startMinute = _calendarMinuteInDay(localStart, start);
      final endMinute = _calendarMinuteInDay(localEnd, start, end: end);
      items.add(
        WorkDayPlanItem(
          block: block,
          task: task,
          parent: taskById(data, task.parentTaskId),
          project: projectById(data, task.projectId),
          area: areaById(data, areaIdForTask(data, task)),
          startsAt: localStart,
          endsAt: localEnd,
          startMinute: startMinute,
          endMinute: endMinute > startMinute ? endMinute : startMinute + 1,
        ),
      );
    }
    items.sort((a, b) {
      final startOrder = a.startMinute.compareTo(b.startMinute);
      if (startOrder != 0) return startOrder;
      final endOrder = a.endMinute.compareTo(b.endMinute);
      if (endOrder != 0) return endOrder;
      return a.title.compareTo(b.title);
    });
    return List.unmodifiable(items);
  }

  static List<WorkPlanConflict> conflictsForBlock({
    required WorkData data,
    required DateTime startsAt,
    required int minutes,
    String? excludingBlockId,
    Iterable<Habit> habits = const [],
    DateTime? now,
  }) {
    if (minutes <= 0 || minutes > 24 * 60) {
      throw ArgumentError(
        'Plan conflicts require a duration from 1 minute to 24 hours',
      );
    }
    final start = startsAt.toUtc();
    final end = start.add(Duration(minutes: minutes));
    final conflicts = <WorkPlanConflict>[];

    for (final block in data.blocks) {
      if (block.id == excludingBlockId) continue;
      if (!shouldShowBlock(data, block, now: now)) continue;
      if (!_overlaps(start, end, block.startsAt, block.endsAt)) continue;
      final task = taskById(data, block.taskId);
      conflicts.add(
        WorkPlanConflict(
          kind: WorkPlanConflictKind.work,
          title: task?.title ?? 'Planned work',
          startsAt: block.startsAt.toLocal(),
          endsAt: block.endsAt.toLocal(),
          blockId: block.id,
          taskId: block.taskId,
        ),
      );
    }

    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    var cursor = localStart.atMidnight;
    final lastDay = localEnd.atMidnight;
    while (!cursor.isAfter(lastDay)) {
      for (final habit in habits) {
        if (!_habitDueOn(habit, cursor) || !habit.isPlanned) continue;
        final habitStart = DateTime(
          cursor.year,
          cursor.month,
          cursor.day,
          habit.startMinute ~/ 60,
          habit.startMinute % 60,
        );
        final habitEnd = habit.endMinute >= Habit.dayMinutes
            ? DateTime(cursor.year, cursor.month, cursor.day + 1)
            : DateTime(
                cursor.year,
                cursor.month,
                cursor.day,
                habit.endMinute ~/ 60,
                habit.endMinute % 60,
              );
        if (!_overlaps(localStart, localEnd, habitStart, habitEnd)) continue;
        conflicts.add(
          WorkPlanConflict(
            kind: WorkPlanConflictKind.habit,
            title: habit.name,
            startsAt: habitStart,
            endsAt: habitEnd,
            habitId: habit.id,
          ),
        );
      }
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }

    conflicts.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return List.unmodifiable(conflicts);
  }

  static bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) => aStart.isBefore(bEnd) && aEnd.isAfter(bStart);

  static bool _habitDueOn(Habit habit, DateTime day) =>
      !habit.isArchived &&
      habit.kind != HabitKind.negative &&
      !day.atMidnight.isBefore(habit.startedAt) &&
      habit.isScheduledOn(day) &&
      !habit.isPausedOn(day);

  static int calendarMinuteOfDay(DateTime value, DateTime day) =>
      _calendarMinuteInDay(
        value,
        DateTime(day.year, day.month, day.day),
        end: DateTime(day.year, day.month, day.day + 1),
      );

  static int _calendarMinuteInDay(
    DateTime value,
    DateTime start, {
    DateTime? end,
  }) {
    final dayEnd = end ?? DateTime(start.year, start.month, start.day + 1);
    if (!value.isAfter(start)) return 0;
    if (!value.isBefore(dayEnd)) return Habit.dayMinutes;
    return (value.hour * 60 + value.minute).clamp(0, Habit.dayMinutes).toInt();
  }

  static int _compareBlocks(WorkPlanBlock a, WorkPlanBlock b) {
    final start = a.startsAt.compareTo(b.startsAt);
    if (start != 0) return start;
    final end = a.endsAt.compareTo(b.endsAt);
    return end != 0 ? end : a.id.compareTo(b.id);
  }
}
