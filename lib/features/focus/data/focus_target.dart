import 'package:flutter/foundation.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';

enum FocusTargetKind { free, habit, workTask }

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

@immutable
class FocusTarget {
  FocusTarget({
    required this.kind,
    required this.id,
    this.title = '',
    this.parentTaskId,
    this.projectId,
    this.areaId,
    this.parentTitle = '',
    this.projectTitle = '',
    this.areaTitle = '',
  }) {
    switch (kind) {
      case FocusTargetKind.free:
        if (id.isNotEmpty) throw ArgumentError('Free focus has no target id');
      case FocusTargetKind.habit:
      case FocusTargetKind.workTask:
        requireText(id, 'focus target id');
    }
    if (kind == FocusTargetKind.workTask && title.trim().isEmpty) {
      throw ArgumentError('Work focus target needs a title snapshot');
    }
    if (kind != FocusTargetKind.workTask &&
        (parentTaskId != null ||
            projectId != null ||
            areaId != null ||
            parentTitle.isNotEmpty ||
            projectTitle.isNotEmpty ||
            areaTitle.isNotEmpty)) {
      throw ArgumentError('Only Work focus targets can include Work context');
    }
  }

  factory FocusTarget.free({String title = ''}) =>
      FocusTarget(kind: FocusTargetKind.free, id: '', title: title);

  factory FocusTarget.habit(String id, {String title = ''}) =>
      FocusTarget(kind: FocusTargetKind.habit, id: id, title: title);

  factory FocusTarget.fromWork(WorkData data, String taskId) {
    WorkTask? task;
    for (final item in data.tasks) {
      if (item.id == taskId) {
        task = item;
        break;
      }
    }
    if (task == null || task.isDeleted) {
      throw ArgumentError('Unknown Work focus target $taskId');
    }
    final parent = _firstWhereOrNull(
      data.tasks,
      (item) => item.id == task!.parentTaskId && !item.isDeleted,
    );
    final project = _firstWhereOrNull(
      data.projects,
      (item) => item.id == task!.projectId && !item.isDeleted,
    );
    final areaId = project?.areaId ?? task.areaId;
    final area = _firstWhereOrNull(
      data.areas,
      (item) => item.id == areaId && !item.isDeleted,
    );
    return FocusTarget(
      kind: FocusTargetKind.workTask,
      id: task.id,
      title: task.title,
      parentTaskId: task.parentTaskId,
      projectId: task.projectId,
      areaId: areaId,
      parentTitle: parent?.title ?? '',
      projectTitle: project?.name ?? '',
      areaTitle: area?.name ?? '',
    );
  }

  factory FocusTarget.fromSessionMap(Map<String, dynamic> map) {
    final raw = map['target'];
    if (raw is Map) return FocusTarget.fromMap(RecordReader.object(raw));
    final habitId = (map['habitId'] ?? '') as String;
    return habitId.isEmpty ? FocusTarget.free() : FocusTarget.habit(habitId);
  }

  factory FocusTarget.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return FocusTarget(
      kind: read.enumValue('kind', FocusTargetKind.values),
      id: read.string('id', fallback: ''),
      title: read.string('title', fallback: ''),
      parentTaskId: read.optionalString('parentTaskId'),
      projectId: read.optionalString('projectId'),
      areaId: read.optionalString('areaId'),
      parentTitle: read.string('parentTitle', fallback: ''),
      projectTitle: read.string('projectTitle', fallback: ''),
      areaTitle: read.string('areaTitle', fallback: ''),
    );
  }

  final FocusTargetKind kind;
  final String id;
  final String title;
  final String? parentTaskId;
  final String? projectId;
  final String? areaId;
  final String parentTitle;
  final String projectTitle;
  final String areaTitle;

  Map<String, dynamic> toMap() => {
    'kind': kind.name,
    'id': id,
    'title': title,
    'parentTaskId': parentTaskId,
    'projectId': projectId,
    'areaId': areaId,
    'parentTitle': parentTitle,
    'projectTitle': projectTitle,
    'areaTitle': areaTitle,
  };
}
