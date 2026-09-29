import 'dart:convert';

import 'package:streak/core/data/record.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/data/goal_progress.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_progress.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';

class WorkConflict implements Exception {
  const WorkConflict(this.record);
  final String record;

  @override
  String toString() =>
      'Work or goal data conflicts at $record. Restore with replace only '
      'after choosing which copy to keep.';
}

class WorkData {
  WorkData({
    this.revision = 0,
    Iterable<WorkArea> areas = const [],
    Iterable<WorkProject> projects = const [],
    Iterable<WorkTask> tasks = const [],
    Iterable<Goal> goals = const [],
    Iterable<GoalHabitLink> habitLinks = const [],
    Iterable<WorkEntry> entries = const [],
    Iterable<WorkPlanBlock> blocks = const [],
  }) : areas = List.unmodifiable(areas),
       projects = List.unmodifiable(projects),
       tasks = List.unmodifiable(tasks),
       goals = List.unmodifiable(goals),
       habitLinks = List.unmodifiable(habitLinks),
       entries = List.unmodifiable(entries),
       blocks = List.unmodifiable(blocks) {
    validate();
  }

  static const schemaVersion = 1;

  final int revision;
  final List<WorkArea> areas;
  final List<WorkProject> projects;
  final List<WorkTask> tasks;
  final List<Goal> goals;
  final List<GoalHabitLink> habitLinks;
  final List<WorkEntry> entries;
  final List<WorkPlanBlock> blocks;

  bool get isEmpty =>
      areas.isEmpty &&
      projects.isEmpty &&
      tasks.isEmpty &&
      goals.isEmpty &&
      habitLinks.isEmpty &&
      entries.isEmpty &&
      blocks.isEmpty;

  WorkData copyWith({
    int? revision,
    Iterable<WorkArea>? areas,
    Iterable<WorkProject>? projects,
    Iterable<WorkTask>? tasks,
    Iterable<Goal>? goals,
    Iterable<GoalHabitLink>? habitLinks,
    Iterable<WorkEntry>? entries,
    Iterable<WorkPlanBlock>? blocks,
  }) => WorkData(
    revision: revision ?? this.revision,
    areas: areas ?? this.areas,
    projects: projects ?? this.projects,
    tasks: tasks ?? this.tasks,
    goals: goals ?? this.goals,
    habitLinks: habitLinks ?? this.habitLinks,
    entries: entries ?? this.entries,
    blocks: blocks ?? this.blocks,
  );

  static Map<String, T> _index<T extends StoredRecord>(Iterable<T> records) {
    final result = <String, T>{};
    for (final record in records) {
      if (result.containsKey(record.id)) {
        throw ArgumentError('Duplicate ${record.runtimeType} ID ${record.id}');
      }
      result[record.id] = record;
    }
    return result;
  }

  void validate() {
    if (revision < 0) throw ArgumentError('Invalid Work data revision');
    final areaMap = _index(areas);
    final projectMap = _index(projects);
    final taskMap = _index(tasks);
    final goalMap = _index(goals);
    _index(habitLinks);
    _index(entries);
    _index(blocks);

    void reference(Map<String, StoredRecord> records, String? id) {
      if (id != null && !records.containsKey(id)) {
        throw ArgumentError('Missing Work or goal reference: $id');
      }
    }

    String? areaOf(WorkTask task) =>
        projectMap[task.projectId]?.areaId ?? task.areaId;

    for (final project in projects) {
      reference(areaMap, project.areaId);
      if (areaMap[project.areaId]?.isDeleted == true && !project.isDeleted) {
        throw ArgumentError('Delete a work area and its projects together');
      }
    }
    final children = <String, List<WorkTask>>{};
    final todoSources = <String>{};
    for (final task in tasks) {
      if (task.sourceTodoId != null && !todoSources.add(task.sourceTodoId!)) {
        throw ArgumentError('A to-do can be moved to Work only once');
      }
      reference(areaMap, task.areaId);
      reference(projectMap, task.projectId);
      reference(taskMap, task.parentTaskId);
      final project = projectMap[task.projectId];
      if (!task.isDeleted &&
          (project?.isDeleted == true ||
              areaMap[areaOf(task)]?.isDeleted == true)) {
        throw ArgumentError('Delete work containers and their tasks together');
      }
      if (project != null &&
          task.areaId != null &&
          task.areaId != project.areaId) {
        throw ArgumentError('Task ${task.id} conflicts with its project area');
      }
      final parent = taskMap[task.parentTaskId];
      if (parent != null) {
        if (parent.parentTaskId != null) {
          throw ArgumentError('Only one subtask level is currently supported');
        }
        if (task.projectId != parent.projectId ||
            areaOf(task) != areaOf(parent)) {
          throw ArgumentError('Subtasks must inherit their parent context');
        }
        if (parent.isDeleted && !task.isDeleted) {
          throw ArgumentError('Delete the task and its subtasks together');
        }
        children.putIfAbsent(parent.id, () => []).add(task);
      }
    }
    for (final item in children.entries) {
      final parent = taskMap[item.key]!;
      if (parent.progressMode == WorkTaskProgress.manual) {
        throw ArgumentError('Parent task progress must come from subtasks');
      }
      if (!parent.isDeleted &&
          parent.status == WorkTaskStatus.done &&
          item.value.any(
            (task) =>
                !task.isDeleted &&
                task.status != WorkTaskStatus.done &&
                task.status != WorkTaskStatus.cancelled,
          )) {
        throw ArgumentError('Finish open subtasks before closing their parent');
      }
    }

    for (final goal in goals) {
      reference(areaMap, goal.areaId);
      reference(projectMap, goal.projectId);
      final project = projectMap[goal.projectId];
      if (project != null &&
          goal.areaId != null &&
          goal.areaId != project.areaId) {
        throw ArgumentError('Goal ${goal.id} conflicts with its project area');
      }
      for (final id in goal.taskIds) {
        reference(taskMap, id);
        final task = taskMap[id]!;
        if ((goal.projectId != null && goal.projectId != task.projectId) ||
            (goal.areaId != null && goal.areaId != areaOf(task))) {
          throw ArgumentError('Goal tasks must belong to its work context');
        }
        if (goal.source == GoalSource.work) {
          if (goal.projectIds.contains(task.projectId) ||
              goal.taskIds.contains(task.parentTaskId)) {
            throw ArgumentError('A goal cannot count a parent and its child');
          }
        }
      }
      for (final id in goal.projectIds) {
        reference(projectMap, id);
        if ((goal.projectId != null && goal.projectId != id) ||
            (goal.areaId != null && goal.areaId != projectMap[id]!.areaId)) {
          throw ArgumentError('Goal projects must belong to its work context');
        }
      }
    }
    final pairs = <(String, String)>{};
    for (final link in habitLinks) {
      reference(goalMap, link.goalId);
      if (!link.isDeleted && !pairs.add((link.goalId, link.habitId))) {
        throw ArgumentError('A habit can have only one link to each goal');
      }
    }
    for (final entry in entries) {
      reference(switch (entry.entityKind) {
        WorkEntityKind.area => areaMap,
        WorkEntityKind.project => projectMap,
        WorkEntityKind.task => taskMap,
        WorkEntityKind.goal => goalMap,
      }, entry.entityId);
    }
    for (final block in blocks) {
      reference(taskMap, block.taskId);
    }
  }

  List<GoalHabitLink> linksForHabit(String habitId) => List.unmodifiable(
    habitLinks.where((link) => link.habitId == habitId && !link.isDeleted),
  );

  List<GoalHabitLink> linksForGoal(String goalId) => List.unmodifiable(
    habitLinks.where((link) => link.goalId == goalId && !link.isDeleted),
  );

  WorkProgress projectProgress(String id) {
    if (!projects.any((project) => project.id == id)) {
      throw ArgumentError('Unknown project $id');
    }
    return WorkProgress.of(
      tasks,
      projectIds: [id],
      excludedProjectIds: _excludedProjects,
    );
  }

  GoalProgress goalProgress(
    String id, {
    required Map<String, Habit> habits,
    required DateTime asOf,
  }) {
    final goal = _index(goals)[id];
    if (goal == null) throw ArgumentError('Unknown goal $id');
    return GoalProgress.compute(
      goal: goal,
      links: habitLinks,
      habits: habits,
      asOf: asOf,
      workFraction: goal.source == GoalSource.work
          ? WorkProgress.of(
              tasks,
              taskIds: goal.taskIds,
              projectIds: goal.projectIds,
              excludedProjectIds: _excludedProjects,
            ).fraction
          : null,
    );
  }

  Set<String> get photoPaths => {
    for (final area in areas)
      if (area.coverPath.isNotEmpty) area.coverPath,
    for (final project in projects)
      if (project.coverPath.isNotEmpty) project.coverPath,
    for (final task in tasks) ...task.photos,
    for (final goal in goals) ...goal.photos,
    for (final entry in entries) ...entry.photos,
  }..remove('');

  Set<String> get _excludedProjects => {
    for (final project in projects)
      if (project.isDeleted || project.status == WorkProjectStatus.cancelled)
        project.id,
  };

  WorkData merge(WorkData incoming) {
    List<T> combine<T extends StoredRecord>(List<T> ours, List<T> theirs) {
      final merged = _index(ours);
      for (final record in theirs) {
        final existing = merged[record.id];
        if (existing != null &&
            json.encode(existing.toMap()) != json.encode(record.toMap())) {
          throw WorkConflict('${record.runtimeType}:${record.id}');
        }
        merged[record.id] = record;
      }
      return merged.values.toList();
    }

    try {
      return WorkData(
        revision: revision,
        areas: combine(areas, incoming.areas),
        projects: combine(projects, incoming.projects),
        tasks: combine(tasks, incoming.tasks),
        goals: combine(goals, incoming.goals),
        habitLinks: combine(habitLinks, incoming.habitLinks),
        entries: combine(entries, incoming.entries),
        blocks: combine(blocks, incoming.blocks),
      );
    } on ArgumentError catch (e) {
      throw WorkConflict('relationships: ${e.message}');
    }
  }

  Map<String, dynamic> toMap() => {
    'version': schemaVersion,
    'revision': revision,
    'areas': areas.map((record) => record.toMap()).toList(),
    'projects': projects.map((record) => record.toMap()).toList(),
    'tasks': tasks.map((record) => record.toMap()).toList(),
    'goals': goals.map((record) => record.toMap()).toList(),
    'habitLinks': habitLinks.map((record) => record.toMap()).toList(),
    'entries': entries.map((record) => record.toMap()).toList(),
    'blocks': blocks.map((record) => record.toMap()).toList(),
  };

  factory WorkData.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    if (read.integer('version') != schemaVersion) {
      throw const FormatException('Unsupported Work and Goals data version');
    }
    List<T> records<T>(String key, T Function(Map<String, dynamic>) build) => [
      for (final value in read.list(key)) build(RecordReader.object(value)),
    ];
    return WorkData(
      revision: read.integer('revision'),
      areas: records('areas', WorkArea.fromMap),
      projects: records('projects', WorkProject.fromMap),
      tasks: records('tasks', WorkTask.fromMap),
      goals: records('goals', Goal.fromMap),
      habitLinks: records('habitLinks', GoalHabitLink.fromMap),
      entries: records('entries', WorkEntry.fromMap),
      blocks: records('blocks', WorkPlanBlock.fromMap),
    );
  }
}
