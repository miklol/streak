import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';

class WorkInsights {
  WorkInsights._({
    required this.seconds,
    required this.manualSeconds,
    required this.completedTasks,
    required this.openTasks,
    required this.overdueTasks,
    required this.blockedTasks,
    required Map<String, int> projectSeconds,
    required Map<String, String> projectTitles,
    required Map<String, int> dailySeconds,
  }) : projectSeconds = Map.unmodifiable(projectSeconds),
       projectTitles = Map.unmodifiable(projectTitles),
       dailySeconds = Map.unmodifiable(dailySeconds);

  final int seconds;
  final int manualSeconds;
  final int completedTasks;
  final int openTasks;
  final int overdueTasks;
  final int blockedTasks;
  final Map<String, int> projectSeconds;
  final Map<String, String> projectTitles;
  final Map<String, int> dailySeconds;

  factory WorkInsights.compute({
    required WorkData data,
    required List<FocusSession> sessions,
    required DateTime from,
    required DateTime until,
    required DateTime now,
    String? areaId,
  }) {
    if (!until.isAfter(from) || until.epochDay - from.epochDay > 366) {
      throw ArgumentError('Choose an insights window of at most one year');
    }
    final projects = {for (final project in data.projects) project.id: project};
    final areas = {for (final area in data.areas) area.id: area};
    final tasks = {for (final task in data.tasks) task.id: task};
    final parents = {
      for (final task in data.tasks)
        if (task.parentTaskId != null) task.parentTaskId!,
    };
    String? taskArea(WorkTask task) =>
        projects[task.projectId]?.areaId ?? task.areaId;
    bool inScope(WorkTask task) => areaId == null || taskArea(task) == areaId;
    bool live(WorkTask task) {
      final project = projects[task.projectId];
      final area = areas[taskArea(task)];
      final parent = tasks[task.parentTaskId];
      return inScope(task) &&
          !task.isDeleted &&
          !task.isArchived &&
          task.status != WorkTaskStatus.cancelled &&
          task.status != WorkTaskStatus.done &&
          !(parent?.isArchived ?? false) &&
          !(parent?.isDeleted ?? false) &&
          parent?.status != WorkTaskStatus.cancelled &&
          parent?.status != WorkTaskStatus.done &&
          !(project?.isArchived ?? false) &&
          !(project?.isDeleted ?? false) &&
          project?.status != WorkProjectStatus.cancelled &&
          project?.status != WorkProjectStatus.done &&
          !(area?.isArchived ?? false) &&
          !(area?.isDeleted ?? false);
    }

    final open = data.tasks
        .where((task) => live(task) && !parents.contains(task.id))
        .toList();
    bool inPeriod(DateTime date) =>
        !date.isBefore(from) && date.isBefore(until);
    final completed = <String>{
      for (final task in data.tasks)
        if (inScope(task) &&
            !parents.contains(task.id) &&
            task.completedAt != null &&
            inPeriod(task.completedAt!))
          task.id,
      for (final entry in data.entries)
        if (!entry.isDeleted &&
            entry.entityKind == WorkEntityKind.task &&
            entry.kind == WorkEntryKind.statusChange &&
            entry.status == WorkTaskStatus.done.name &&
            tasks[entry.entityId] != null &&
            inScope(tasks[entry.entityId]!) &&
            !parents.contains(entry.entityId) &&
            inPeriod(entry.meta.createdAt))
          entry.entityId,
    };
    var seconds = 0;
    var manual = 0;
    final totals = <String, int>{};
    final titles = <String, String>{};
    final days = <String, int>{
      for (
        var date = from.atMidnight;
        date.isBefore(until);
        date = date.addDays(1)
      )
        date.dayKey: 0,
    };
    final seen = <String>{};
    for (final session in sessions) {
      if (!session.isWork ||
          session.isDeleted ||
          (areaId != null && session.target.areaId != areaId)) {
        continue;
      }
      if (!seen.add(session.id)) {
        throw StateError('Duplicate time record ${session.id}');
      }
      final counted = session.secondsInPeriod(from, until);
      if (counted <= 0) continue;
      seconds += counted;
      if (session.source == FocusEntrySource.manual) manual += counted;
      final id = session.target.projectId ?? '';
      totals[id] = (totals[id] ?? 0) + counted;
      titles[id] = session.target.projectTitle;
      for (final key in days.keys.toList()) {
        final day = parseDayKey(key);
        final start = day.isAfter(from) ? day : from;
        final next = day.addDays(1);
        final end = next.isBefore(until) ? next : until;
        days[key] = days[key]! + session.secondsInPeriod(start, end);
      }
    }
    return WorkInsights._(
      seconds: seconds,
      manualSeconds: manual,
      completedTasks: completed.length,
      openTasks: open.length,
      overdueTasks: open.where((task) {
        if (task.dueDate == null) return false;
        final due = parseDayKey(task.dueDate!);
        return due.epochDay < now.epochDay ||
            (due.epochDay == now.epochDay &&
                task.dueMinute != null &&
                task.dueMinute! < now.hour * 60 + now.minute);
      }).length,
      blockedTasks: open
          .where((task) => task.status == WorkTaskStatus.blocked)
          .length,
      projectSeconds: totals,
      projectTitles: titles,
      dailySeconds: days,
    );
  }
}
