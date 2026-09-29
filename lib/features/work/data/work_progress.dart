import 'package:streak/features/work/data/work_task.dart';

class WorkProgress {
  const WorkProgress({
    required this.total,
    required this.completed,
    required this.fraction,
  });

  final int total;
  final int completed;
  final double? fraction;

  static WorkProgress of(
    Iterable<WorkTask> tasks, {
    Iterable<String>? taskIds,
    Iterable<String>? projectIds,
    Set<String> excludedProjectIds = const {},
  }) {
    final all = <String, WorkTask>{};
    for (final task in tasks) {
      if (all.containsKey(task.id)) {
        throw ArgumentError('Duplicate task ${task.id}');
      }
      all[task.id] = task;
    }
    final children = <String, List<WorkTask>>{};
    for (final task in all.values) {
      final parentId = task.parentTaskId;
      if (parentId == null) continue;
      final parent = all[parentId];
      if (parent == null || parent.parentTaskId != null) {
        throw ArgumentError('Invalid parent for ${task.id}');
      }
      children.putIfAbsent(parentId, () => []).add(task);
    }

    bool included(WorkTask task) =>
        !task.isDeleted &&
        task.status != WorkTaskStatus.cancelled &&
        !excludedProjectIds.contains(task.projectId);

    final leaves = <String, WorkTask>{};
    void add(WorkTask task) {
      if (!included(task)) return;
      final parent = all[task.parentTaskId];
      if (parent != null && !included(parent)) return;
      final descendants = children[task.id];
      if (descendants == null || descendants.isEmpty) {
        leaves[task.id] = task;
      } else {
        for (final child in descendants) {
          if (included(child)) leaves[child.id] = child;
        }
      }
    }

    if (taskIds == null && projectIds == null) {
      for (final task in all.values) {
        add(task);
      }
    } else {
      for (final id in taskIds ?? const <String>[]) {
        final task = all[id];
        if (task == null) throw ArgumentError('Unknown task $id');
        add(task);
      }
      final projects = (projectIds ?? const <String>[]).toSet();
      for (final task in all.values) {
        if (projects.contains(task.projectId)) add(task);
      }
    }
    return WorkProgress(
      total: leaves.length,
      completed: leaves.values
          .where((task) => task.status == WorkTaskStatus.done)
          .length,
      fraction: leaves.isEmpty
          ? null
          : leaves.values.fold<double>(
                  0,
                  (sum, task) => sum + task.ownFraction,
                ) /
                leaves.length,
    );
  }
}
