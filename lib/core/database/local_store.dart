import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/utils/app_dirs.dart';
import 'package:streak/features/habits/data/category.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/habits/data/habit_note.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/work/data/todo_move_exception.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';

class LocalStore {
  const LocalStore._();

  static const _habitsBox = 'habits';
  static const _settingsBox = 'settings';
  static const _categoriesBox = 'categories';
  static const _notesBox = 'notes';
  static const _focusBox = 'focus';
  static const _todosBox = 'todos';
  static const _workBox = 'work';

  static late Box _habits;
  static late Box _settings;
  static late Box _categories;
  static late Box _notes;
  static late Box _focus;
  static late Box _todos;
  static late Box _work;
  static Future<void> _workGate = Future.value();
  static Future<void> _focusGate = Future.value();
  static int _focusWrites = 0;
  static int _workWrites = 0;

  static int _writing = 0;

  static bool get isWriting => _writing > 0;

  static Future<T> guardWrites<T>(Future<T> Function() action) async {
    _writing++;
    try {
      return await action();
    } finally {
      _writing--;
    }
  }

  static Future<void> init() async {
    if (_workWrites > 0) await _workGate;
    if (_focusWrites > 0) await _focusGate;
    await Hive.initFlutter(isMobile ? null : appDataFolder);
    _habits = await Hive.openBox(_habitsBox);
    _settings = await Hive.openBox(_settingsBox);
    _categories = await Hive.openBox(_categoriesBox);
    _notes = await Hive.openBox(_notesBox);
    _focus = await Hive.openBox(_focusBox);
    _todos = await Hive.openBox(_todosBox);
    _work = await Hive.openBox(_workBox);
    _workGate = Future.value();
    _focusGate = Future.value();
    _focusWrites = 0;
    _workWrites = 0;
    await _recoverWork();
    await _recoverFocusTransition();
  }

  static Future<T> _withWorkGate<T>(Future<T> Function() action) async {
    _workWrites++;
    final previous = _workGate;
    final release = Completer<void>();
    _workGate = release.future;
    await previous;
    try {
      return await action();
    } finally {
      _workWrites--;
      release.complete();
    }
  }

  static Future<T> _guardedMutation<T>(Future<T> Function() action) =>
      _withWorkGate(
        () => guardWrites(() async {
          await _recoverWork();
          return await action();
        }),
      );

  static const _focusPendingKey = '__pending_focus_transition';

  static Future<T> _withFocusGate<T>(Future<T> Function() action) async {
    _focusWrites++;
    final previous = _focusGate;
    final release = Completer<void>();
    _focusGate = release.future;
    await previous;
    try {
      return await action();
    } finally {
      _focusWrites--;
      release.complete();
    }
  }

  static Future<void> _applyFocusTransition(
    FocusSession? session,
    Map<String, dynamic> active,
  ) async {
    if (session != null) {
      final existing = _focus.get(session.id);
      if (existing != null &&
          !_sameEncoded(
            Map<String, dynamic>.from(existing as Map),
            session.toMap(),
          )) {
        throw StateError('Focus session ${session.id} changed');
      }
      await _focus.put(session.id, session.toMap());
      await _focus.flush();
    }
    await _settings.put('focusActive', active);
    await _settings.flush();
  }

  static Future<void> _recoverFocusTransition() async {
    final raw = _focus.get(_focusPendingKey);
    if (raw == null) return;
    final pending = RecordReader.object(raw);
    final active = RecordReader.object(pending['active']);
    final session = pending['session'] == null
        ? null
        : FocusSession.fromMap(RecordReader.object(pending['session']));
    await _applyFocusTransition(session, active);
    await _focus.delete(_focusPendingKey);
    await _focus.flush();
  }

  static Future<void> writeFocusActive(Map<String, dynamic> active) {
    // Start the settings write immediately so callers that still use the
    // historic synchronous start/pause API have recoverable state even if
    // the process is suspended before they await FocusController.ready.
    final eager = _focusWrites == 0 && !_focus.containsKey(_focusPendingKey)
        ? _settings.put('focusActive', active) : Future<void>.value();
    return _withFocusGate(() async {
      await eager;
      await _recoverFocusTransition();
      await _settings.put('focusActive', active);
      await _settings.flush();
    });
  }

  static Future<void> recoverFocusTransition() =>
      _withFocusGate(_recoverFocusTransition);

  static Future<T> updateFocusSessions<T>(
    T Function(List<FocusSession> current) change,
  ) => _withFocusGate(() async {
    await _recoverFocusTransition();
    return change(readFocusSessions(includeDeleted: true));
  });

  static Future<void> commitFocusTransition({
    FocusSession? session,
    required Map<String, dynamic> active,
  }) => _withFocusGate(() async {
    await _recoverFocusTransition();
    await _focus.put(_focusPendingKey, {
      'session': session?.toMap(),
      'active': active,
    });
    await _focus.flush();
    await _applyFocusTransition(session, active);
    await _focus.delete(_focusPendingKey);
    await _focus.flush();
  });

  static WorkData readWork() {
    final raw = _work.get('state');
    return raw == null
        ? WorkData()
        : WorkData.fromMap(RecordReader.object(raw));
  }

  static Todo? _readTodoById(String id) {
    final raw = _todos.get(id);
    return raw == null ? null : Todo.fromMap(RecordReader.object(raw));
  }

  static WorkArea? _findArea(WorkData state, String? id) {
    if (id == null) return null;
    for (final area in state.areas) {
      if (area.id == id) return area;
    }
    return null;
  }

  static WorkProject? _findProject(WorkData state, String? id) {
    if (id == null) return null;
    for (final project in state.projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  static WorkTask? _findTaskBySource(WorkData state, String sourceTodoId) {
    for (final task in state.tasks) {
      if (task.sourceTodoId == sourceTodoId) return task;
    }
    return null;
  }

  static String? _areaOfTask(WorkData state, WorkTask task) =>
      _findProject(state, task.projectId)?.areaId ?? task.areaId;

  static bool _sameEncoded(Object a, Object b) =>
      json.encode(a) == json.encode(b);

  static bool _sameTodo(Todo a, Todo b) => _sameEncoded(a.toMap(), b.toMap());

  static bool _sameWork(WorkData a, WorkData b) =>
      _sameEncoded(a.toMap(), b.toMap());

  static DateTime? _todoCompletedAt(Todo todo) =>
      todo.done ? todo.doneAt?.toUtc() : null;

  static bool _todoMatchesTask(Todo todo, WorkTask task) {
    final completedAt = _todoCompletedAt(todo);
    return task.sourceTodoId == todo.id &&
        task.title == todo.title &&
        task.description == todo.body &&
        task.status ==
            (todo.done ? WorkTaskStatus.done : WorkTaskStatus.notStarted) &&
        task.priority == todo.priority &&
        task.dueDate == (todo.date.isEmpty ? null : todo.date) &&
        task.dueMinute == todo.minutes &&
        listEquals(task.photos, todo.photos) &&
        task.meta.createdAt.isAtSameMomentAs(todo.createdAt.toUtc()) &&
        ((task.completedAt == null && completedAt == null) ||
            (task.completedAt != null &&
                completedAt != null &&
                task.completedAt!.isAtSameMomentAs(completedAt)));
  }

  static WorkTask _validatedPendingTodoMoveTask(_PendingTodoMove pending) {
    WorkTask? target;
    for (final task in pending.work.tasks) {
      if (task.id == pending.targetTaskId) {
        target = task;
        break;
      }
    }
    if (target == null ||
        target.parentTaskId != null ||
        target.sourceTodoId != pending.source.id ||
        target.projectId != pending.projectId ||
        _areaOfTask(pending.work, target) != pending.areaId ||
        !_todoMatchesTask(pending.source, target)) {
      throw const FormatException('Invalid pending to-do move transaction');
    }
    return target;
  }

  static Future<void> _publishWorkState(WorkData next) async {
    await _work.put('state', next.toMap());
    await _work.flush();
  }

  static Future<void> _clearPendingWork() async {
    await _work.delete('pending');
    await _work.flush();
  }

  static int _nextTaskOrder(
    WorkData state,
    String? areaId,
    String? projectId,
  ) =>
      state.tasks
          .where(
            (task) =>
                task.parentTaskId == null &&
                task.projectId == projectId &&
                _areaOfTask(state, task) == areaId,
          )
          .map((task) => task.order)
          .fold<int>(-1, (a, b) => a > b ? a : b) +
      1;

  static _TodoMoveTarget _resolveTodoMoveTarget(
    WorkData state, {
    String? areaId,
    String? projectId,
  }) {
    WorkProject? project;
    if (projectId != null) {
      project = _findProject(state, projectId);
      if (project == null ||
          project.isDeleted ||
          project.isArchived ||
          project.status == WorkProjectStatus.done ||
          project.status == WorkProjectStatus.cancelled) {
        throw const TodoMoveException(TodoMoveFailure.invalidDestination);
      }
      if (areaId != null && areaId != project.areaId) {
        throw const TodoMoveException(TodoMoveFailure.invalidDestination);
      }
    }
    final effectiveArea = project?.areaId ?? areaId;
    if (effectiveArea != null) {
      final area = _findArea(state, effectiveArea);
      if (area == null || area.isDeleted || area.isArchived) {
        throw const TodoMoveException(TodoMoveFailure.invalidDestination);
      }
    }
    return _TodoMoveTarget(areaId: effectiveArea, projectId: project?.id);
  }

  static String _allocateTodoMoveTaskId(WorkData state, String sourceTodoId) {
    final used = {for (final task in state.tasks) task.id};
    if (!used.contains(sourceTodoId)) return sourceTodoId;
    final base = 'todo:$sourceTodoId';
    if (!used.contains(base)) return base;
    for (var index = 1; index <= 1024; index++) {
      final candidate = '$base:$index';
      if (!used.contains(candidate)) return candidate;
    }
    throw const TodoMoveException(TodoMoveFailure.idConflict);
  }

  static WorkTask _buildMovedTask(
    WorkData state,
    Todo source,
    _TodoMoveTarget target,
  ) {
    final createdAt = source.createdAt.toUtc();
    final completedAt = _todoCompletedAt(source);
    final updatedAt = completedAt != null && completedAt.isAfter(createdAt)
        ? completedAt
        : createdAt;
    final createdDay = source.createdAt
        .toLocal()
        .subtract(Duration(hours: AppClock.cutoffHour))
        .dayKey;
    final id = _allocateTodoMoveTaskId(state, source.id);
    return WorkTask(
      meta: RecordMeta(
        id: id,
        createdAt: createdAt,
        createdDay: createdDay,
        updatedAt: updatedAt,
      ),
      title: source.title,
      order: _nextTaskOrder(state, target.areaId, target.projectId),
      sourceTodoId: source.id,
      areaId: target.areaId,
      projectId: target.projectId,
      status: source.done ? WorkTaskStatus.done : WorkTaskStatus.notStarted,
      description: source.body,
      priority: source.priority,
      dueDate: source.date.isEmpty ? null : source.date,
      dueMinute: source.minutes,
      completedAt: completedAt,
      photos: source.photos,
    );
  }

  static Future<void> _recoverWork() async {
    final raw = _work.get('pending');
    if (raw == null) return;
    final data = RecordReader.object(raw);
    if (data['kind'] == _PendingTodoMove.kind) {
      await _recoverTodoMove(_PendingTodoMove.fromMap(data));
      return;
    }
    final pending = WorkData.fromMap(data);
    final current = readWork();
    if (pending.revision != current.revision + 1 &&
        !(pending.revision == current.revision &&
            _sameWork(pending, current))) {
      throw const FormatException('Invalid pending Work transaction');
    }
    await _publishWorkState(pending);
    await _clearPendingWork();
  }

  static Future<void> _recoverTodoMove(_PendingTodoMove pending) async {
    _validatedPendingTodoMoveTask(pending);
    final current = readWork();
    final published = _sameWork(current, pending.work);
    if (!published && pending.work.revision != current.revision + 1) {
      throw const FormatException('Invalid pending Work transaction');
    }
    final source = _readTodoById(pending.source.id);
    if (!published) {
      if (source != null && !_sameTodo(source, pending.source)) {
        debugPrint(
          'Abandoned interrupted to-do move ${pending.source.id}: '
          'source changed before Work state published.',
        );
        await _clearPendingWork();
        return;
      }
      await _publishWorkState(pending.work);
    }
    final latest = _readTodoById(pending.source.id);
    if (latest == null) {
      await _clearPendingWork();
      return;
    }
    if (!_sameTodo(latest, pending.source)) {
      debugPrint(
        'Preserved changed to-do ${pending.source.id} while keeping moved '
        'Work task ${pending.targetTaskId}.',
      );
      await _clearPendingWork();
      return;
    }
    await _todos.delete(pending.source.id);
    await _todos.flush();
    await _clearPendingWork();
  }

  static Future<WorkData> updateWork(
    WorkData Function(WorkData current) change, {
    int? expectedRevision,
  }) async {
    return _withWorkGate(() async {
      return await guardWrites(() async {
        await _recoverWork();
        final current = readWork();
        if (expectedRevision != null && expectedRevision != current.revision) {
          throw StateError('Work data changed; reload before saving');
        }
        final proposed = change(current).copyWith(revision: current.revision);
        if (json.encode(proposed.toMap()) == json.encode(current.toMap())) {
          return current;
        }
        final next = proposed.copyWith(revision: current.revision + 1);
        // Journal the whole relationship graph before publishing its new state.
        await _work.put('pending', next.toMap());
        await _work.flush();
        await _recoverWork();
        return next;
      });
    });
  }

  static Future<WorkData> writeWork(
    WorkData data, {
    required int expectedRevision,
  }) => updateWork((_) => data, expectedRevision: expectedRevision);

  static List<Todo> readTodos() {
    final result = <Todo>[];
    for (final raw in _todos.values) {
      try {
        result.add(Todo.fromMap(Map<String, dynamic>.from(raw as Map)));
      } catch (e) {
        debugPrint('Skipped an unreadable to-do: $e');
      }
    }
    return result;
  }

  static Future<void> writeTodo(
    Todo todo, {
    bool requireExisting = false,
  }) => _guardedMutation(() async {
    if (requireExisting && !_todos.containsKey(todo.id)) {
      if (_findTaskBySource(readWork(), todo.id) != null) {
        throw const TodoMoveException(TodoMoveFailure.alreadyMoved);
      }
      throw const TodoMoveException(TodoMoveFailure.missingSource);
    }
    await _todos.put(todo.id, todo.toMap());
    await _todos.flush();
  });

  static Future<void> removeTodo(String id) => _guardedMutation(() async {
    await _todos.delete(id);
    await _todos.flush();
  });

  static Future<void> removeTodos(Iterable<String> ids) => _guardedMutation(
    () async {
      for (final id in ids) {
        await _todos.delete(id);
      }
      await _todos.flush();
    },
  );

  static Future<WorkTask> moveTodoToWork(
    String id, {
    String? areaId,
    String? projectId,
  }) => _withWorkGate(() async {
    return await guardWrites(() async {
      await _recoverWork();
      final current = readWork();
      final existing = _findTaskBySource(current, id);
      final source = _readTodoById(id);
      if (source == null) {
        if (existing != null && !existing.isDeleted) return existing;
        if (existing != null) {
          throw const TodoMoveException(TodoMoveFailure.alreadyMoved);
        }
        throw const TodoMoveException(TodoMoveFailure.missingSource);
      }
      if (existing != null) {
        throw TodoMoveException(
          _todoMatchesTask(source, existing)
              ? TodoMoveFailure.alreadyMoved
              : TodoMoveFailure.changedSource,
        );
      }
      final target = _resolveTodoMoveTarget(
        current,
        areaId: areaId,
        projectId: projectId,
      );
      final task = _buildMovedTask(current, source, target);
      final next = current
          .copyWith(tasks: [...current.tasks, task], revision: current.revision)
          .copyWith(revision: current.revision + 1);
      final pending = _PendingTodoMove(
        source: source,
        targetTaskId: task.id,
        areaId: target.areaId,
        projectId: target.projectId,
        work: next,
      );
      await _work.put('pending', pending.toMap());
      await _work.flush();
      await _publishWorkState(next);
      final latest = _readTodoById(id);
      if (latest != null && !_sameTodo(latest, source)) {
        debugPrint(
          'Preserved changed to-do $id while keeping moved Work task '
          '${task.id}.',
        );
        await _clearPendingWork();
        throw const TodoMoveException(TodoMoveFailure.changedSource);
      }
      if (latest != null) {
        await _todos.delete(id);
        await _todos.flush();
      }
      await _clearPendingWork();
      return task;
    });
  });

  static List<FocusSession> readFocusSessions({bool includeDeleted = false}) {
    final result = <FocusSession>[];
    for (final key in _focus.keys) {
      if (key == _focusPendingKey) continue;
      final raw = _focus.get(key);
      try {
        final map = RecordReader.object(raw);
        final session = FocusSession.fromMap(map);
        if (includeDeleted || !session.isDeleted) result.add(session);
      } catch (e) {
        if (_isStrictFocusRecord(raw)) rethrow;
        debugPrint('Skipped an unreadable legacy focus session: $e');
      }
    }
    return result;
  }

  static bool _isStrictFocusRecord(Object? raw) {
    if (raw is! Map) return false;
    final map = Map<String, dynamic>.from(raw);
    final version = map['version'];
    if (version is int && version >= focusSessionSchemaVersion) return true;
    final target = map['target'];
    if (target is Map && target['kind'] == FocusTargetKind.workTask.name) {
      return true;
    }
    return false;
  }

  static Future<void> writeFocusSession(FocusSession session) =>
      _withFocusGate(() async {
        await _recoverFocusTransition();
        await _writeFocusSessionUnlocked(session);
      });

  static Future<FocusSession> writeFocusSessionChecked(
    FocusSession Function(List<FocusSession> current) build,
  ) => _withFocusGate(() async {
    await _recoverFocusTransition();
    final session = build(readFocusSessions(includeDeleted: true));
    await _writeFocusSessionUnlocked(session);
    return session;
  });

  static Future<void> _writeFocusSessionUnlocked(FocusSession session) async {
    final raw = _focus.get(session.id);
    if (raw != null) {
      final existing = FocusSession.fromMap(RecordReader.object(raw));
      if (existing.isWork && existing.isDeleted && !session.isDeleted) {
        throw StateError('Focus session ${session.id} was deleted');
      }
      if (existing.isWork &&
          existing.isDeleted &&
          session.isDeleted &&
          existing.revision > session.revision) {
        return;
      }
    }
    await _focus.put(session.id, session.toMap());
    await _focus.flush();
  }

  static Future<void> removeFocusSessions(Iterable<String> ids) async {
    await _withFocusGate(() async {
      await _recoverFocusTransition();
      for (final id in ids) {
        final raw = _focus.get(id);
        if (raw == null) continue;
        FocusSession? session;
        try {
          session = FocusSession.fromMap(RecordReader.object(raw));
        } catch (_) {
          await _focus.delete(id);
          continue;
        }
        if (session.isWork) {
          if (!session.isDeleted) {
            await _focus.put(
              id,
              session
                  .copyWith(
                    deletedAt: DateTime.now().toUtc(),
                    revision: session.revision + 1,
                  )
                  .toMap(),
            );
          }
        } else {
          await _focus.delete(id);
        }
      }
      await _focus.flush();
    });
  }

  static Future<void> removeFocusFor(String habitId) async {
    final ids = readFocusSessions()
        .where((s) => s.habitId == habitId)
        .map((s) => s.id)
        .toList();
    await removeFocusSessions(ids);
  }

  static List<HabitNote> readNotes() {
    final result = <HabitNote>[];
    for (final raw in _notes.values) {
      result.add(HabitNote.fromMap(Map<String, dynamic>.from(raw as Map)));
    }
    return result;
  }

  static Future<void> writeNote(HabitNote note) =>
      _notes.put(note.id, note.toMap());

  static Future<void> removeNote(String id) => _notes.delete(id);

  static Future<void> removeNotesFor(String habitId) async {
    final ids = readNotes()
        .where((n) => n.habitId == habitId)
        .map((n) => n.id)
        .toList();
    for (final id in ids) {
      await _notes.delete(id);
    }
  }

  static Map<String, Habit> readHabits() {
    final result = <String, Habit>{};
    for (final raw in _habits.values) {
      try {
        final habit = Habit.fromJson(raw as String);
        result[habit.id] = habit;
      } catch (e) {
        debugPrint('Skipped an unreadable habit: $e');
      }
    }
    return result;
  }

  static Future<void> writeHabit(Habit habit) =>
      _habits.put(habit.id, habit.toJson());

  static Future<void> removeHabit(String id) => _habits.delete(id);

  static Future<void> reloadHabits() async {
    if (_writing > 0) return;
    if (_habits.isOpen) await _habits.close();
    _habits = await Hive.openBox(_habitsBox);
  }

  static List<Category> readCategories() {
    final result = <Category>[];
    for (final raw in _categories.values) {
      try {
        result.add(Category.fromJson(raw as String));
      } catch (e) {
        debugPrint('Skipped an unreadable category: $e');
      }
    }
    return result;
  }

  static Future<void> writeCategory(Category category) =>
      _categories.put(category.id, category.toJson());

  static Future<void> removeCategory(String id) => _categories.delete(id);

  static bool get hasCategories => _categories.isNotEmpty;

  static T setting<T>(String key, T fallback) {
    final value = _settings.get(key, defaultValue: fallback);
    return value is T ? value : fallback;
  }

  static Map<String, dynamic> settingMap(String key) {
    final value = _settings.get(key);
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  static Future<void> writeSetting(
    String key,
    Object value, {
    bool flush = false,
  }) async {
    await _settings.put(key, value);
    if (flush) await _settings.flush();
  }

  static Future<void> clearProgress() async {
    for (final habit in readHabits().values) {
      await writeHabit(habit.copyWith(completions: const {}));
    }
    await _notes.clear();
    await _withFocusGate(() async {
      await _recoverFocusTransition();
      final workSessions = readFocusSessions(includeDeleted: true)
          .where((session) => session.target.kind == FocusTargetKind.workTask)
          .toList();
      await _focus.clear();
      for (final session in workSessions) {
        await _focus.put(session.id, session.toMap());
      }
      await _focus.flush();
      final active = settingMap('focusActive');
      final activeTarget = active['focusTarget'];
      final activeKind = activeTarget is Map ? activeTarget['kind'] : null;
      if (activeKind != FocusTargetKind.workTask.name) {
        await _settings.put('focusActive', {'open': false});
      }
    });
  }

  static Future<void> wipeContent({bool includeWork = true}) async {
    await _habits.clear();
    await _notes.clear();
    await _focus.clear();
    await _settings.put('focusActive', {'open': false});
    await _todos.clear();
    await _categories.clear();
    if (includeWork) await updateWork((_) => WorkData());
  }

  static Future<void> wipeEverything() async {
    await wipeContent();
    await _settings.clear();
  }
}

class _TodoMoveTarget {
  const _TodoMoveTarget({required this.areaId, required this.projectId});

  final String? areaId;
  final String? projectId;
}

class _PendingTodoMove {
  const _PendingTodoMove({
    required this.source,
    required this.targetTaskId,
    required this.work,
    this.areaId,
    this.projectId,
  });

  static const kind = 'todoMove';
  static const schemaVersion = 1;

  final Todo source;
  final String targetTaskId;
  final String? areaId;
  final String? projectId;
  final WorkData work;

  Map<String, dynamic> toMap() => {
    'kind': kind,
    'schemaVersion': schemaVersion,
    'source': source.toMap(),
    'targetTaskId': targetTaskId,
    'areaId': areaId,
    'projectId': projectId,
    'work': work.toMap(),
  };

  factory _PendingTodoMove.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    if (read.string('kind') != kind ||
        read.integer('schemaVersion') != schemaVersion) {
      throw const FormatException('Unsupported pending to-do move transaction');
    }
    final pending = _PendingTodoMove(
      source: Todo.fromMap(RecordReader.object(map['source'])),
      targetTaskId: read.string('targetTaskId'),
      areaId: read.optionalString('areaId'),
      projectId: read.optionalString('projectId'),
      work: WorkData.fromMap(RecordReader.object(map['work'])),
    );
    LocalStore._validatedPendingTodoMoveTask(pending);
    return pending;
  }
}
