import 'package:flutter/foundation.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:uuid/uuid.dart';

enum WorkTaskSort { manual, dueDate, priority }

enum WorkFailure {
  missing,
  stale,
  invalidScope,
  invalidParent,
  linkedGoal,
  openSubtasks,
  closedParent,
  archivedParent,
  invalidProgress,
  invalidNote,
}

class WorkOperationException implements Exception {
  const WorkOperationException(this.code, {this.count = 0});
  final WorkFailure code;
  final int count;

  @override
  String toString() => 'Work operation failed: ${code.name}';
}

class WorkController extends ChangeNotifier {
  WorkController({DateTime Function()? now})
    : _now = now ?? AppClock.wallNow,
      _data = LocalStore.readWork();

  final DateTime Function() _now;
  WorkData _data;
  WorkData get data => _data;

  static RecordMeta newMeta() =>
      RecordMeta(id: const Uuid().v4(), createdAt: AppClock.wallNow().toUtc());

  RecordMeta _newMeta() =>
      RecordMeta(id: const Uuid().v4(), createdAt: _now().toUtc());

  RecordMeta _touch(RecordMeta meta, {bool? archived, bool? deleted}) {
    final now = _now().toUtc();
    // Imported records can come from a device whose clock is ahead of ours.
    return meta.revise(
      at: now.isBefore(meta.updatedAt) ? meta.updatedAt : now,
      archived: archived,
      deleted: deleted,
    );
  }

  void reload() {
    _data = LocalStore.readWork();
    notifyListeners();
  }

  static T? _find<T extends StoredRecord>(Iterable<T> records, String? id) {
    if (id == null) return null;
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }

  WorkArea? areaById(String id) => _find(_data.areas, id);
  WorkProject? projectById(String id) => _find(_data.projects, id);
  WorkTask? taskById(String id) => _find(_data.tasks, id);

  static String? _areaFor(WorkData state, WorkTask task) =>
      _find(state.projects, task.projectId)?.areaId ?? task.areaId;
  String? areaForTask(WorkTask task) => _areaFor(_data, task);

  static bool _projectArchived(WorkData state, WorkProject project) =>
      project.isArchived ||
      _find(state.areas, project.areaId)?.isArchived == true;

  static bool _taskArchived(WorkData state, WorkTask task) {
    final project = _find(state.projects, task.projectId);
    return task.isArchived ||
        _find(state.tasks, task.parentTaskId)?.isArchived == true ||
        _find(state.areas, _areaFor(state, task))?.isArchived == true ||
        (project != null && _projectArchived(state, project));
  }

  bool isTaskArchived(WorkTask task) => _taskArchived(_data, task);
  bool isProjectArchived(WorkProject project) =>
      _projectArchived(_data, project);

  static int _order(StoredRecord a, int aOrder, StoredRecord b, int bOrder) {
    final order = aOrder.compareTo(bOrder);
    if (order != 0) return order;
    final date = a.meta.createdAt.compareTo(b.meta.createdAt);
    return date != 0 ? date : a.id.compareTo(b.id);
  }

  List<WorkArea> areas({bool archived = false, String query = ''}) {
    final term = query.trim().toLowerCase();
    return _data.areas
        .where(
          (area) =>
              !area.isDeleted &&
              area.isArchived == archived &&
              '${area.name}\n${area.description}\n${area.role}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList()
      ..sort((a, b) => _order(a, a.order, b, b.order));
  }

  List<WorkProject> projects({
    String? areaId,
    bool archived = false,
    String query = '',
    WorkProjectStatus? status,
  }) {
    final term = query.trim().toLowerCase();
    return _data.projects
        .where(
          (project) =>
              !project.isDeleted &&
              _projectArchived(_data, project) == archived &&
              (areaId == null || project.areaId == areaId) &&
              (status == null || project.status == status) &&
              '${project.name}\n${project.description}\n${project.outcome}\n'
                      '${project.tags.join(' ')}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList()
      ..sort((a, b) => _order(a, a.order, b, b.order));
  }

  List<WorkTask> tasks({
    String? areaId,
    String? projectId,
    String? parentTaskId,
    bool rootsOnly = false,
    bool inboxOnly = false,
    bool archived = false,
    bool includeDone = true,
    String query = '',
    WorkTaskStatus? status,
    TodoPriority? priority,
    WorkTaskSort sort = WorkTaskSort.manual,
  }) {
    final term = query.trim().toLowerCase();
    final result = _data.tasks.where((task) {
      if (task.isDeleted || _taskArchived(_data, task) != archived) {
        return false;
      }
      if (areaId != null && _areaFor(_data, task) != areaId) return false;
      if (projectId != null && task.projectId != projectId) return false;
      if (parentTaskId != null && task.parentTaskId != parentTaskId) {
        return false;
      }
      if (rootsOnly && task.parentTaskId != null) return false;
      if (inboxOnly &&
          (task.projectId != null || _areaFor(_data, task) != null)) {
        return false;
      }
      if (status != null && task.status != status) return false;
      if (priority != null && task.priority != priority) return false;
      if (!includeDone &&
          status == null &&
          (task.status == WorkTaskStatus.done ||
              task.status == WorkTaskStatus.cancelled)) {
        return false;
      }
      final project = _find(_data.projects, task.projectId);
      if (!includeDone &&
          (project?.status == WorkProjectStatus.cancelled ||
              _find(_data.tasks, task.parentTaskId)?.status ==
                  WorkTaskStatus.cancelled)) {
        return false;
      }
      return term.isEmpty ||
          '${task.title}\n${task.description}\n${task.completionCriteria}\n'
                  '${task.tags.join(' ')}\n${project?.name ?? ''}\n'
                  '${_find(_data.areas, _areaFor(_data, task))?.name ?? ''}\n'
                  '${_find(_data.tasks, task.parentTaskId)?.title ?? ''}'
              .toLowerCase()
              .contains(term);
    }).toList();
    result.sort((a, b) {
      if (sort == WorkTaskSort.priority) {
        final priority = b.priority.index.compareTo(a.priority.index);
        if (priority != 0) return priority;
      }
      if (sort != WorkTaskSort.manual) {
        if (a.dueDate == null && b.dueDate != null) return 1;
        if (a.dueDate != null && b.dueDate == null) return -1;
        if (a.dueDate != null && b.dueDate != null) {
          final date = parseDayKey(
            a.dueDate!,
          ).epochDay.compareTo(parseDayKey(b.dueDate!).epochDay);
          if (date != 0) return date;
          final minute = (a.dueMinute ?? 1440).compareTo(b.dueMinute ?? 1440);
          if (minute != 0) return minute;
        }
      }
      return _order(a, a.order, b, b.order);
    });
    return result;
  }

  bool isOverdue(WorkTask task, DateTime now) {
    if (task.dueDate == null || _finished(task)) return false;
    final due = parseDayKey(task.dueDate!);
    return due.epochDay < now.epochDay ||
        (due.epochDay == now.epochDay &&
            task.dueMinute != null &&
            task.dueMinute! < now.hour * 60 + now.minute);
  }

  bool isForToday(WorkTask task, DateTime now) =>
      !_finished(task) &&
      ((task.dueDate != null &&
              parseDayKey(task.dueDate!).epochDay <= now.epochDay) ||
          (task.startDate != null &&
              parseDayKey(task.startDate!).epochDay <= now.epochDay) ||
          _data.blocks.any((block) => !block.isDeleted && !block.isArchived &&
              block.taskId == task.id &&
              block.startsAt.isBefore(now.atMidnight.addDays(1)) &&
              block.endsAt.isAfter(now.atMidnight)) ||
          task.status == WorkTaskStatus.inProgress);

  static bool _finished(WorkTask task) =>
      task.status == WorkTaskStatus.done ||
      task.status == WorkTaskStatus.cancelled;

  int openSubtaskCount(String taskId) => _data.tasks
      .where(
        (task) =>
            task.parentTaskId == taskId && !task.isDeleted && !_finished(task),
      )
      .length;

  List<WorkEntry> entriesFor(WorkEntityKind kind, String id) =>
      _data.entries
          .where(
            (entry) =>
                !entry.isDeleted &&
                entry.entityKind == kind &&
                entry.entityId == id,
          )
          .toList()
        ..sort((a, b) {
          final date = parseDayKey(
            b.date,
          ).epochDay.compareTo(parseDayKey(a.date).epochDay);
          return date != 0
              ? date
              : b.meta.createdAt.compareTo(a.meta.createdAt);
        });

  Future<void> _change(
    WorkData Function(WorkData) change, {
    int? revision,
  }) async {
    final updated = await LocalStore.updateWork(
      change,
      expectedRevision: revision,
    );
    if (updated.revision >= _data.revision) {
      _data = updated;
      notifyListeners();
    }
  }

  static List<T> _put<T extends StoredRecord>(List<T> records, T record) => [
    for (final existing in records)
      if (existing.id == record.id) record else existing,
    if (!records.any((existing) => existing.id == record.id)) record,
  ];

  RecordMeta _saveMeta(StoredRecord? old, RecordMeta draft, int? expected) {
    if (old == null) {
      if (expected != null) {
        throw const WorkOperationException(WorkFailure.missing);
      }
      return draft;
    }
    if (old.isDeleted) throw const WorkOperationException(WorkFailure.missing);
    if (expected != old.meta.revision) {
      throw const WorkOperationException(WorkFailure.stale);
    }
    return _touch(old.meta);
  }

  WorkEntry _event(
    WorkEntityKind kind,
    String id,
    WorkEntryKind type, {
    String? fromStatus,
    String? status,
    double? fromValue,
    double? value,
  }) => WorkEntry(
    meta: _newMeta(),
    entityKind: kind,
    entityId: id,
    kind: type,
    previousStatus: fromStatus,
    status: status,
    previousValue: fromValue,
    value: value,
  );

  void _target(
    WorkData state,
    String? areaId,
    String? projectId, {
    bool adding = false,
  }) {
    WorkProject? project;
    if (projectId != null) {
      project = _find(state.projects, projectId);
      if (project == null || project.isDeleted) {
        throw const WorkOperationException(WorkFailure.invalidScope);
      }
      if (areaId != null && areaId != project.areaId) {
        throw const WorkOperationException(WorkFailure.invalidScope);
      }
      if (_projectArchived(state, project)) {
        throw const WorkOperationException(WorkFailure.archivedParent);
      }
      if (project.status == WorkProjectStatus.cancelled ||
          (adding && project.status == WorkProjectStatus.done)) {
        throw const WorkOperationException(WorkFailure.closedParent);
      }
    }
    final effectiveArea = project?.areaId ?? areaId;
    if (effectiveArea != null) {
      final area = _find(state.areas, effectiveArea);
      if (area == null || area.isDeleted) {
        throw const WorkOperationException(WorkFailure.invalidScope);
      }
      if (area.isArchived) {
        throw const WorkOperationException(WorkFailure.archivedParent);
      }
    }
  }

  Future<WorkArea> saveArea(WorkArea draft, {int? expectedRevision}) async {
    late WorkArea saved;
    await _change((state) {
      final old = _find(state.areas, draft.id);
      saved = draft.copyWith(
        meta: _saveMeta(old, draft.meta, expectedRevision),
        name: draft.name.trim(),
        description: draft.description.trim(),
        role: draft.role.trim(),
        order: old?.order ?? _nextOrder(state.areas.map((area) => area.order)),
      );
      return state.copyWith(areas: _put(state.areas, saved));
    });
    return saved;
  }

  Future<WorkProject> saveProject(
    WorkProject draft, {
    int? expectedRevision,
    bool completeTasks = false,
  }) async {
    late WorkProject saved;
    await _change((state) {
      final old = _find(state.projects, draft.id);
      final meta = _saveMeta(old, draft.meta, expectedRevision);
      _target(state, draft.areaId, null);
      var tasks = state.tasks;
      if (old != null && old.areaId != draft.areaId) {
        if (state.goals.any(
          (goal) =>
              goal.areaId != null &&
              (goal.projectId == old.id ||
                  goal.projectIds.contains(old.id) ||
                  goal.taskIds.any(
                    (id) => _find(tasks, id)?.projectId == old.id,
                  )),
        )) {
          throw const WorkOperationException(WorkFailure.linkedGoal);
        }
        tasks = [
          for (final task in tasks)
            if (task.projectId == draft.id)
              task.copyWith(
                meta: _touch(task.meta),
                areaId: draft.areaId,
                clearArea: draft.areaId == null,
              )
            else
              task,
        ];
      }
      final open = tasks
          .where(
            (task) =>
                task.projectId == draft.id &&
                !task.isDeleted &&
                !_finished(task) &&
                _find(state.tasks, task.parentTaskId)?.status !=
                    WorkTaskStatus.cancelled,
          )
          .toList();
      var entries = state.entries;
      if (draft.status == WorkProjectStatus.done && open.isNotEmpty) {
        if (!completeTasks) {
          throw WorkOperationException(
            WorkFailure.openSubtasks,
            count: open.length,
          );
        }
        tasks = [
          for (final task in tasks)
            if (open.any((item) => item.id == task.id))
              _withStatus(task, WorkTaskStatus.done)
            else
              task,
        ];
        entries = [
          ...entries,
          for (final task in open)
            _event(
              WorkEntityKind.task,
              task.id,
              WorkEntryKind.statusChange,
              fromStatus: task.status.name,
              status: WorkTaskStatus.done.name,
            ),
        ];
      }
      saved = draft.copyWith(
        meta: meta,
        name: draft.name.trim(),
        description: draft.description.trim(),
        outcome: draft.outcome.trim(),
        order:
            old?.order ?? _nextOrder(state.projects.map((item) => item.order)),
      );
      if (old != null && old.status != saved.status) {
        entries = [
          ...entries,
          _event(
            WorkEntityKind.project,
            saved.id,
            WorkEntryKind.statusChange,
            fromStatus: old.status.name,
            status: saved.status.name,
          ),
        ];
      }
      return state.copyWith(
        projects: _put(state.projects, saved),
        tasks: tasks,
        entries: entries,
      );
    });
    return saved;
  }

  WorkTask _withStatus(WorkTask task, WorkTaskStatus status) => task.copyWith(
    meta: _touch(task.meta),
    status: status,
    progress:
        status == WorkTaskStatus.done &&
            task.progressMode == WorkTaskProgress.manual
        ? 100
        : task.progress,
    completedAt: status == WorkTaskStatus.done ? _now().toUtc() : null,
    clearCompletedAt: status != WorkTaskStatus.done,
  );

  WorkData _saveTask(WorkData state, WorkTask draft, {int? expectedRevision}) {
    final old = _find(state.tasks, draft.id);
    final meta = _saveMeta(old, draft.meta, expectedRevision);
    final scopeChanged =
        old == null ||
        old.projectId != draft.projectId ||
        _areaFor(state, old) != _areaFor(state, draft) ||
        old.parentTaskId != draft.parentTaskId;
    if ((old == null && draft.sourceTodoId != null) ||
        (old != null && old.sourceTodoId != draft.sourceTodoId)) {
      throw const WorkOperationException(WorkFailure.invalidScope);
    }
    _target(state, draft.areaId, draft.projectId, adding: scopeChanged);
    if (old != null && _taskArchived(state, old)) {
      throw const WorkOperationException(WorkFailure.archivedParent);
    }
    final children = state.tasks
        .where((task) => task.parentTaskId == draft.id)
        .toList();
    if (children.isNotEmpty && draft.progressMode == WorkTaskProgress.manual) {
      throw const WorkOperationException(WorkFailure.invalidProgress);
    }
    final parent = _find(state.tasks, draft.parentTaskId);
    if (draft.parentTaskId != null) {
      if (parent == null ||
          parent.isDeleted ||
          parent.parentTaskId != null ||
          parent.id == draft.id ||
          children.isNotEmpty) {
        throw const WorkOperationException(WorkFailure.invalidParent);
      }
      if (_taskArchived(state, parent)) {
        throw const WorkOperationException(WorkFailure.archivedParent);
      }
      if (parent.status == WorkTaskStatus.cancelled ||
          (scopeChanged && parent.status == WorkTaskStatus.done)) {
        throw const WorkOperationException(WorkFailure.closedParent);
      }
      if (parent.progressMode == WorkTaskProgress.manual) {
        throw const WorkOperationException(WorkFailure.invalidProgress);
      }
      if (draft.projectId != parent.projectId ||
          _areaFor(state, draft) != _areaFor(state, parent)) {
        throw const WorkOperationException(WorkFailure.invalidScope);
      }
    }
    if (draft.status == WorkTaskStatus.done &&
        children.any((task) => !task.isDeleted && !_finished(task))) {
      throw WorkOperationException(
        WorkFailure.openSubtasks,
        count: children
            .where((task) => !task.isDeleted && !_finished(task))
            .length,
      );
    }
    final movedIds = {draft.id, ...children.map((task) => task.id)};
    if (old != null &&
        scopeChanged &&
        state.goals.any(
          (goal) =>
              goal.taskIds.any(movedIds.contains) &&
              ((goal.areaId != null && goal.areaId != _areaFor(state, draft)) ||
                  (goal.projectId != null &&
                      goal.projectId != draft.projectId) ||
                  (goal.source == GoalSource.work &&
                      (goal.projectIds.contains(draft.projectId) ||
                          goal.taskIds.contains(draft.parentTaskId)))),
        )) {
      throw const WorkOperationException(WorkFailure.linkedGoal);
    }
    final saved = draft.copyWith(
      meta: meta,
      title: draft.title.trim(),
      description: draft.description.trim(),
      completionCriteria: draft.completionCriteria.trim(),
      order: old == null || scopeChanged
          ? _nextOrder(
              state.tasks
                  .where(
                    (task) =>
                        task.projectId == draft.projectId &&
                        task.parentTaskId == draft.parentTaskId &&
                        _areaFor(state, task) == _areaFor(state, draft),
                  )
                  .map((task) => task.order),
            )
          : old.order,
      completedAt: draft.status == WorkTaskStatus.done
          ? (draft.completedAt ?? _now().toUtc())
          : null,
      clearCompletedAt: draft.status != WorkTaskStatus.done,
    );
    var tasks = _put(state.tasks, saved);
    if (scopeChanged) {
      tasks = [
        for (final task in tasks)
          if (task.parentTaskId == saved.id)
            task.copyWith(
              meta: _touch(task.meta),
              areaId: saved.areaId,
              clearArea: saved.areaId == null,
              projectId: saved.projectId,
              clearProject: saved.projectId == null,
            )
          else
            task,
      ];
    }
    final entries = [...state.entries];
    if (old != null && old.status != saved.status) {
      entries.add(
        _event(
          WorkEntityKind.task,
          saved.id,
          WorkEntryKind.statusChange,
          fromStatus: old.status.name,
          status: saved.status.name,
        ),
      );
    }
    if (old != null && old.progress != saved.progress) {
      entries.add(
        _event(
          WorkEntityKind.task,
          saved.id,
          WorkEntryKind.progress,
          fromValue: old.progress,
          value: saved.progress,
        ),
      );
    }
    if (old != null && scopeChanged) {
      entries.add(
        _event(WorkEntityKind.task, saved.id, WorkEntryKind.scopeChange),
      );
    }
    if (parent != null &&
        parent.status == WorkTaskStatus.done &&
        !_finished(saved)) {
      tasks = _put(tasks, _withStatus(parent, WorkTaskStatus.inProgress));
      entries.add(
        _event(
          WorkEntityKind.task,
          parent.id,
          WorkEntryKind.statusChange,
          fromStatus: parent.status.name,
          status: WorkTaskStatus.inProgress.name,
        ),
      );
    }
    var projects = state.projects;
    final project = _find(projects, saved.projectId);
    if (project?.status == WorkProjectStatus.done && !_finished(saved)) {
      projects = _put(
        projects,
        project!.copyWith(
          meta: _touch(project.meta),
          status: WorkProjectStatus.active,
        ),
      );
      entries.add(
        _event(
          WorkEntityKind.project,
          project.id,
          WorkEntryKind.statusChange,
          fromStatus: WorkProjectStatus.done.name,
          status: WorkProjectStatus.active.name,
        ),
      );
    }
    return state.copyWith(tasks: tasks, projects: projects, entries: entries);
  }

  Future<WorkTask> saveTask(WorkTask draft, {int? expectedRevision}) async {
    await _change(
      (state) => _saveTask(state, draft, expectedRevision: expectedRevision),
    );
    return taskById(draft.id)!;
  }

  Future<void> setTaskStatus(
    String id,
    WorkTaskStatus status, {
    bool completeSubtasks = false,
  }) async {
    await _change((state) {
      final task = _find(state.tasks, id);
      if (task == null || task.isDeleted) {
        throw const WorkOperationException(WorkFailure.missing);
      }
      var prepared = state;
      if (status == WorkTaskStatus.done) {
        final open = state.tasks
            .where(
              (child) =>
                  child.parentTaskId == id &&
                  !child.isDeleted &&
                  !_finished(child),
            )
            .toList();
        if (open.isNotEmpty && !completeSubtasks) {
          throw WorkOperationException(
            WorkFailure.openSubtasks,
            count: open.length,
          );
        }
        prepared = state.copyWith(
          tasks: [
            for (final item in state.tasks)
              if (open.any((child) => child.id == item.id))
                _withStatus(item, status)
              else
                item,
          ],
          entries: [
            ...state.entries,
            for (final child in open)
              _event(
                WorkEntityKind.task,
                child.id,
                WorkEntryKind.statusChange,
                fromStatus: child.status.name,
                status: status.name,
              ),
          ],
        );
      }
      final draft = task.copyWith(
        status: status,
        progress:
            status == WorkTaskStatus.done &&
                task.progressMode == WorkTaskProgress.manual
            ? 100
            : task.progress,
        completedAt: status == WorkTaskStatus.done ? _now().toUtc() : null,
        clearCompletedAt: status != WorkTaskStatus.done,
      );
      return _saveTask(prepared, draft, expectedRevision: task.meta.revision);
    });
  }

  Future<void> setArchived(
    WorkEntityKind kind,
    String id,
    bool archived,
  ) async {
    await _change((state) {
      switch (kind) {
        case WorkEntityKind.area:
          final item = _find(state.areas, id);
          if (item == null || item.isDeleted) {
            throw const WorkOperationException(WorkFailure.missing);
          }
          return state.copyWith(
            areas: _put(
              state.areas,
              item.copyWith(meta: _touch(item.meta, archived: archived)),
            ),
          );
        case WorkEntityKind.project:
          final item = _find(state.projects, id);
          if (item == null || item.isDeleted) {
            throw const WorkOperationException(WorkFailure.missing);
          }
          if (!archived) _target(state, item.areaId, null);
          return state.copyWith(
            projects: _put(
              state.projects,
              item.copyWith(meta: _touch(item.meta, archived: archived)),
            ),
          );
        case WorkEntityKind.task:
          final item = _find(state.tasks, id);
          if (item == null || item.isDeleted) {
            throw const WorkOperationException(WorkFailure.missing);
          }
          if (!archived) {
            _target(state, item.areaId, item.projectId);
            if (_find(state.tasks, item.parentTaskId)?.isArchived == true) {
              throw const WorkOperationException(WorkFailure.archivedParent);
            }
          }
          return state.copyWith(
            tasks: _put(
              state.tasks,
              item.copyWith(meta: _touch(item.meta, archived: archived)),
            ),
          );
        case WorkEntityKind.goal:
          throw const WorkOperationException(WorkFailure.invalidScope);
      }
    });
  }

  Future<void> moveTask(
    String id, {
    String? areaId,
    String? projectId,
    String? parentTaskId,
  }) async {
    await _change((state) {
      final task = _find(state.tasks, id);
      if (task == null) throw const WorkOperationException(WorkFailure.missing);
      final parent = _find(state.tasks, parentTaskId);
      final nextProject = parent?.projectId ?? projectId;
      final nextArea = parent != null
          ? _areaFor(state, parent)
          : (_find(state.projects, nextProject)?.areaId ?? areaId);
      return _saveTask(
        state,
        task.copyWith(
          areaId: nextArea,
          clearArea: nextArea == null,
          projectId: nextProject,
          clearProject: nextProject == null,
          parentTaskId: parentTaskId,
          clearParent: parentTaskId == null,
        ),
        expectedRevision: task.meta.revision,
      );
    });
  }

  Future<WorkTask> duplicateTask(String id, {required String title}) async {
    late String newId;
    await _change((state) {
      final source = _find(state.tasks, id);
      if (source == null || source.isDeleted) {
        throw const WorkOperationException(WorkFailure.missing);
      }
      _target(state, source.areaId, source.projectId, adding: true);
      final meta = _newMeta();
      newId = meta.id;
      final copy = source.copyWith(
        meta: meta,
        title: title,
        status: WorkTaskStatus.notStarted,
        progress: 0,
        clearCompletedAt: true,
        clearSourceTodo: true,
        order: _nextOrder(state.tasks.map((task) => task.order)),
      );
      var result = _saveTask(state, copy);
      final children =
          state.tasks
              .where(
                (task) => task.parentTaskId == id && !task.isDeleted,
              )
              .toList()
            ..sort((a, b) => _order(a, a.order, b, b.order));
      for (final child in children) {
        result = _saveTask(
          result,
          child.copyWith(
            meta: _newMeta(),
            parentTaskId: newId,
            status: WorkTaskStatus.notStarted,
            progress: 0,
            clearCompletedAt: true,
            clearSourceTodo: true,
          ),
        );
      }
      return result;
    });
    return taskById(newId)!;
  }

  static int _nextOrder(Iterable<int> values) =>
      values.fold<int>(-1, (a, b) => a > b ? a : b) + 1;

  static bool _siblings(WorkData state, WorkTask a, WorkTask b) =>
      a.parentTaskId == b.parentTaskId &&
      a.projectId == b.projectId &&
      _areaFor(state, a) == _areaFor(state, b);

  WorkData _reorder(WorkData state, List<String> ids) {
    if (ids.toSet().length != ids.length || ids.isEmpty) {
      throw const WorkOperationException(WorkFailure.invalidScope);
    }
    final selected = ids.map((id) => _find(state.tasks, id)).toList();
    if (selected.any((task) => task == null || task.isDeleted)) {
      throw const WorkOperationException(WorkFailure.missing);
    }
    final first = selected.first!;
    if (selected.any((task) => !_siblings(state, first, task!))) {
      throw const WorkOperationException(WorkFailure.invalidScope);
    }
    final siblings =
        state.tasks
            .where((task) => !task.isDeleted && _siblings(state, first, task))
            .toList()
          ..sort((a, b) => _order(a, a.order, b, b.order));
    var cursor = 0;
    final order = [
      for (final task in siblings)
        if (ids.contains(task.id)) selected[cursor++]! else task,
    ];
    final replacements = <String, WorkTask>{};
    for (var index = 0; index < order.length; index++) {
      final task = order[index];
      replacements[task.id] = task.order == index
          ? task
          : task.copyWith(meta: _touch(task.meta), order: index);
    }
    return state.copyWith(
      tasks: [
        for (final task in state.tasks) replacements[task.id] ?? task,
      ],
    );
  }

  Future<void> reorderTasks(
    List<String> ids, {
    required int expectedRevision,
  }) => _change((state) => _reorder(state, ids), revision: expectedRevision);

  Future<void> moveTaskBy(String id, int offset) async {
    if (offset != -1 && offset != 1) {
      throw const WorkOperationException(WorkFailure.invalidScope);
    }
    await _change((state) {
      final task = _find(state.tasks, id);
      if (task == null || task.isDeleted) {
        throw const WorkOperationException(WorkFailure.missing);
      }
      final siblings =
          state.tasks
              .where(
                (item) =>
                    !item.isDeleted &&
                    !_taskArchived(state, item) &&
                    _siblings(state, task, item),
              )
              .toList()
            ..sort((a, b) => _order(a, a.order, b, b.order));
      final index = siblings.indexWhere((item) => item.id == id);
      final target = index + offset;
      if (index < 0 || target < 0 || target >= siblings.length) {
        throw const WorkOperationException(WorkFailure.invalidScope);
      }
      siblings[index] = siblings[target];
      siblings[target] = task;
      return _reorder(state, siblings.map((item) => item.id).toList());
    });
  }

  Future<WorkEntry> saveNote({
    required WorkEntityKind kind,
    required String entityId,
    required String text,
    List<String> photos = const [],
    String? date,
    WorkEntry? existing,
  }) async {
    if (text.trim().isEmpty && photos.isEmpty) {
      throw const WorkOperationException(WorkFailure.invalidNote);
    }
    late WorkEntry saved;
    await _change((state) {
      final owner = switch (kind) {
        WorkEntityKind.area => _find(state.areas, entityId),
        WorkEntityKind.project => _find(state.projects, entityId),
        WorkEntityKind.task => _find(state.tasks, entityId),
        WorkEntityKind.goal => null,
      };
      if (owner == null || owner.isDeleted) {
        throw const WorkOperationException(WorkFailure.missing);
      }
      final old = existing == null ? null : _find(state.entries, existing.id);
      if (existing != null &&
          (old == null ||
              old.isDeleted ||
              old.meta.revision != existing.meta.revision)) {
        throw const WorkOperationException(WorkFailure.stale);
      }
      if (old != null &&
          (old.kind != WorkEntryKind.note ||
              old.entityKind != kind ||
              old.entityId != entityId)) {
        throw const WorkOperationException(WorkFailure.invalidNote);
      }
      saved = WorkEntry(
        meta: old == null ? _newMeta() : _touch(old.meta),
        entityKind: kind,
        entityId: entityId,
        text: text.trim(),
        date: date ?? old?.date,
        photos: photos,
      );
      return state.copyWith(entries: _put(state.entries, saved));
    });
    return saved;
  }

  Future<void> removeNote(String id) => _change((state) {
    final entry = _find(state.entries, id);
    if (entry == null || entry.isDeleted) {
      throw const WorkOperationException(WorkFailure.missing);
    }
    if (entry.kind != WorkEntryKind.note) {
      throw const WorkOperationException(WorkFailure.invalidNote);
    }
    return state.copyWith(
      entries: _put(
        state.entries,
        entry.copyWith(meta: _touch(entry.meta, deleted: true)),
      ),
    );
  });
}
