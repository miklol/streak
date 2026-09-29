import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/todos/state/todos_controller.dart';
import 'package:streak/features/work/data/todo_move_exception.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';

import 'support/app_harness.dart';

final _stamp = DateTime.utc(2026, 9, 9, 12);

RecordMeta _meta(String id, {bool archived = false, bool deleted = false}) {
  final touched = _stamp.add(const Duration(hours: 1));
  return RecordMeta(
    id: id,
    createdAt: _stamp,
    updatedAt: touched,
    archivedAt: archived ? touched : null,
    deletedAt: deleted ? touched : null,
  );
}

Todo _todo(
  String id, {
  String text = 'Title\nBody',
  String date = '',
  int? minutes,
  TodoPriority priority = TodoPriority.none,
  List<String> photos = const [],
  DateTime? createdAt,
  bool done = false,
  DateTime? doneAt,
}) {
  final created = createdAt ?? DateTime(2026, 9, 7, 9, 30);
  return Todo(
    id: id,
    text: text,
    date: date,
    minutes: minutes,
    priority: priority,
    photos: photos,
    createdAt: created,
    done: done,
    doneAt: done ? (doneAt ?? created) : null,
  );
}

WorkTask _movedTask(
  Todo source, {
  String? id,
  String? areaId,
  String? projectId,
  int order = 0,
}) {
  final createdAt = source.createdAt.toUtc();
  final completedAt = source.done
      ? (source.doneAt ?? source.createdAt).toUtc()
      : null;
  return WorkTask(
    meta: RecordMeta(
      id: id ?? source.id,
      createdAt: createdAt,
      createdDay: source.createdAt
          .toLocal()
          .subtract(Duration(hours: AppClock.cutoffHour))
          .dayKey,
      updatedAt: completedAt != null && completedAt.isAfter(createdAt)
          ? completedAt
          : createdAt,
    ),
    title: source.title,
    order: order,
    sourceTodoId: source.id,
    areaId: areaId,
    projectId: projectId,
    status: source.done ? WorkTaskStatus.done : WorkTaskStatus.notStarted,
    description: source.body,
    priority: source.priority,
    dueDate: source.date.isEmpty ? null : source.date,
    dueMinute: source.minutes,
    completedAt: completedAt,
    photos: source.photos,
  );
}

WorkData _withTask(WorkData current, WorkTask task) => current
    .copyWith(tasks: [...current.tasks, task], revision: current.revision)
    .copyWith(revision: current.revision + 1);

Map<String, dynamic> _pendingMove(WorkTask task, Todo source, WorkData work) =>
    {
      'kind': 'todoMove',
      'schemaVersion': 1,
      'source': source.toMap(),
      'targetTaskId': task.id,
      'areaId': task.areaId,
      'projectId': task.projectId,
      'work': work.toMap(),
    };

Matcher _moveFailure(TodoMoveFailure code) => throwsA(
  isA<TodoMoveException>().having((error) => error.code, 'code', code),
);

String _encodedWork(WorkData data) => json.encode(data.toMap());

void main() {
  useEmptyStore();

  test(
    'move preserves completed to-do fields and appends after siblings',
    () async {
      final source = _todo(
        'done-todo',
        text: 'Ship launch\nAdd screenshots',
        date: '11-09-2026',
        minutes: 17 * 60 + 15,
        priority: TodoPriority.high,
        photos: const ['one.jpg', 'two.jpg'],
        createdAt: DateTime(2026, 9, 5, 9, 45),
        done: true,
        doneAt: DateTime(2026, 9, 6, 18, 5),
      );
      await LocalStore.writeWork(
        WorkData(
          areas: [WorkArea(meta: _meta('area'), name: 'Client')],
          projects: [
            WorkProject(
              meta: _meta('project'),
              name: 'Website',
              areaId: 'area',
              status: WorkProjectStatus.active,
            ),
          ],
          tasks: [
            WorkTask(
              meta: _meta('existing'),
              title: 'Existing sibling',
              areaId: 'area',
              projectId: 'project',
              order: 0,
            ),
          ],
        ),
        expectedRevision: 0,
      );
      await LocalStore.writeTodo(source);

      final moved = await LocalStore.moveTodoToWork(
        source.id,
        projectId: 'project',
      );

      expect(moved.id, source.id);
      expect(moved.sourceTodoId, source.id);
      expect(moved.title, 'Ship launch');
      expect(moved.description, 'Add screenshots');
      expect(moved.areaId, 'area');
      expect(moved.projectId, 'project');
      expect(moved.status, WorkTaskStatus.done);
      expect(moved.dueDate, '11-09-2026');
      expect(moved.dueMinute, 17 * 60 + 15);
      expect(moved.priority, TodoPriority.high);
      expect(moved.photos, ['one.jpg', 'two.jpg']);
      expect(moved.order, 1);
      expect(
        moved.meta.createdAt.isAtSameMomentAs(source.createdAt.toUtc()),
        isTrue,
      );
      expect(
        moved.completedAt!.isAtSameMomentAs(source.doneAt!.toUtc()),
        isTrue,
      );
      expect(LocalStore.readTodos(), isEmpty);
      expect(LocalStore.readWork().tasks.map((task) => task.id), [
        'existing',
        'done-todo',
      ]);
    },
  );

  test(
    'legacy done to-do with unknown completion time stays unknown',
    () async {
      final source = Todo(
        id: 'legacy-done',
        text: 'Legacy complete',
        done: true,
        createdAt: DateTime(2026, 9, 5, 9, 45),
      );
      await LocalStore.writeTodo(source);

      final moved = await LocalStore.moveTodoToWork(source.id);

      expect(moved.status, WorkTaskStatus.done);
      expect(moved.completedAt, isNull);
      expect(
        moved.meta.createdAt.isAtSameMomentAs(source.createdAt.toUtc()),
        isTrue,
      );
      expect(
        moved.meta.updatedAt.isAtSameMomentAs(source.createdAt.toUtc()),
        isTrue,
      );
    },
  );

  test('move supports inbox, area, and project destinations', () async {
    await LocalStore.writeWork(
      WorkData(
        areas: [WorkArea(meta: _meta('area'), name: 'Client')],
        projects: [
          WorkProject(
            meta: _meta('project'),
            name: 'Website',
            areaId: 'area',
            status: WorkProjectStatus.active,
          ),
        ],
      ),
      expectedRevision: 0,
    );
    await LocalStore.writeTodo(_todo('inbox', text: 'Inbox'));
    await LocalStore.writeTodo(_todo('area-1', text: 'Area one'));
    await LocalStore.writeTodo(_todo('area-2', text: 'Area two'));
    await LocalStore.writeTodo(_todo('project', text: 'Project task'));

    final inbox = await LocalStore.moveTodoToWork('inbox');
    final areaOne = await LocalStore.moveTodoToWork('area-1', areaId: 'area');
    final areaTwo = await LocalStore.moveTodoToWork('area-2', areaId: 'area');
    final projectTask = await LocalStore.moveTodoToWork(
      'project',
      projectId: 'project',
    );

    expect(inbox.areaId, isNull);
    expect(inbox.projectId, isNull);
    expect(areaOne.areaId, 'area');
    expect(areaOne.projectId, isNull);
    expect(areaOne.order, 0);
    expect(areaTwo.areaId, 'area');
    expect(areaTwo.projectId, isNull);
    expect(areaTwo.order, 1);
    expect(projectTask.areaId, 'area');
    expect(projectTask.projectId, 'project');
  });

  test('invalid destinations leave the source intact', () async {
    await LocalStore.writeWork(
      WorkData(
        areas: [
          WorkArea(meta: _meta('area'), name: 'Active'),
          WorkArea(meta: _meta('other'), name: 'Other'),
          WorkArea(meta: _meta('archived-area', archived: true), name: 'Old'),
          WorkArea(meta: _meta('deleted-area', deleted: true), name: 'Gone'),
        ],
        projects: [
          WorkProject(
            meta: _meta('project'),
            name: 'Live',
            areaId: 'area',
            status: WorkProjectStatus.active,
          ),
          WorkProject(
            meta: _meta('archived-project', archived: true),
            name: 'Archived',
            areaId: 'area',
          ),
          WorkProject(
            meta: _meta('deleted-project', deleted: true),
            name: 'Deleted',
            areaId: 'area',
          ),
          WorkProject(
            meta: _meta('done-project'),
            name: 'Done',
            areaId: 'area',
            status: WorkProjectStatus.done,
          ),
          WorkProject(
            meta: _meta('cancelled-project'),
            name: 'Cancelled',
            areaId: 'area',
            status: WorkProjectStatus.cancelled,
          ),
        ],
      ),
      expectedRevision: 0,
    );
    await LocalStore.writeTodo(_todo('todo', text: 'Keep me'));

    await expectLater(
      LocalStore.moveTodoToWork('todo', areaId: 'missing'),
      _moveFailure(TodoMoveFailure.invalidDestination),
    );
    await expectLater(
      LocalStore.moveTodoToWork('todo', areaId: 'archived-area'),
      _moveFailure(TodoMoveFailure.invalidDestination),
    );
    await expectLater(
      LocalStore.moveTodoToWork('todo', areaId: 'deleted-area'),
      _moveFailure(TodoMoveFailure.invalidDestination),
    );
    await expectLater(
      LocalStore.moveTodoToWork('todo', projectId: 'archived-project'),
      _moveFailure(TodoMoveFailure.invalidDestination),
    );
    await expectLater(
      LocalStore.moveTodoToWork('todo', projectId: 'deleted-project'),
      _moveFailure(TodoMoveFailure.invalidDestination),
    );
    await expectLater(
      LocalStore.moveTodoToWork('todo', projectId: 'done-project'),
      _moveFailure(TodoMoveFailure.invalidDestination),
    );
    await expectLater(
      LocalStore.moveTodoToWork('todo', projectId: 'cancelled-project'),
      _moveFailure(TodoMoveFailure.invalidDestination),
    );
    await expectLater(
      LocalStore.moveTodoToWork(
        'todo',
        areaId: 'other',
        projectId: 'project',
      ),
      _moveFailure(TodoMoveFailure.invalidDestination),
    );

    expect(LocalStore.readTodos().single.id, 'todo');
    expect(
      LocalStore.readWork().tasks.where((task) => task.sourceTodoId == 'todo'),
      isEmpty,
    );
  });

  test(
    'id collisions use a stable alternate id and repeats are idempotent',
    () async {
      await LocalStore.writeWork(
        WorkData(
          tasks: [WorkTask(meta: _meta('todo-1'), title: 'Existing root')],
        ),
        expectedRevision: 0,
      );
      await LocalStore.writeTodo(_todo('todo-1', text: 'Moved source'));

      final first = await LocalStore.moveTodoToWork('todo-1');
      final second = await LocalStore.moveTodoToWork('todo-1');
      final tasks = LocalStore.readWork().tasks;

      expect(first.id, isNot('todo-1'));
      expect(first.id, 'todo:todo-1');
      expect(first.sourceTodoId, 'todo-1');
      expect(second.id, first.id);
      expect(tasks.map((task) => task.title), [
        'Existing root',
        'Moved source',
      ]);
      expect(
        tasks.singleWhere((task) => task.id == 'todo-1').sourceTodoId,
        isNull,
      );
      expect(LocalStore.readTodos(), isEmpty);
    },
  );

  test('restored or changed sources cannot overwrite existing work', () async {
    final original = _todo('todo', text: 'Original\nNotes');
    await LocalStore.writeTodo(original);

    final moved = await LocalStore.moveTodoToWork('todo');

    await LocalStore.writeTodo(original);
    await expectLater(
      LocalStore.moveTodoToWork('todo'),
      _moveFailure(TodoMoveFailure.alreadyMoved),
    );

    final current = LocalStore.readWork();
    final edited = current.tasks.single.copyWith(
      meta: current.tasks.single.meta.revise(
        at: current.tasks.single.meta.updatedAt.add(const Duration(minutes: 1)),
      ),
      title: 'Edited work copy',
    );
    await LocalStore.writeWork(
      current.copyWith(tasks: [edited]),
      expectedRevision: current.revision,
    );
    final changed = _todo('todo', text: 'Restored again\nDifferent body');
    await LocalStore.writeTodo(changed);

    await expectLater(
      LocalStore.moveTodoToWork('todo'),
      _moveFailure(TodoMoveFailure.changedSource),
    );

    expect(LocalStore.readTodos().single.text, changed.text);
    expect(LocalStore.readWork().tasks.single.id, moved.id);
    expect(LocalStore.readWork().tasks.single.title, 'Edited work copy');
  });

  test('cold start recovers a pending move before work publish', () async {
    final source = _todo('todo', text: 'Recover me');
    final base = WorkData(
      areas: [WorkArea(meta: _meta('area'), name: 'Client')],
      projects: [
        WorkProject(
          meta: _meta('project'),
          name: 'Website',
          areaId: 'area',
          status: WorkProjectStatus.active,
        ),
      ],
    );
    await LocalStore.writeWork(base, expectedRevision: 0);
    await LocalStore.writeTodo(source);
    final current = LocalStore.readWork();
    final task = _movedTask(source, areaId: 'area', projectId: 'project');
    final next = _withTask(current, task);
    await Hive.box('work').put('pending', _pendingMove(task, source, next));
    await Hive.box('work').flush();

    await coldStart();

    expect(_encodedWork(LocalStore.readWork()), _encodedWork(next));
    expect(LocalStore.readTodos(), isEmpty);
    expect(Hive.box('work').containsKey('pending'), isFalse);
  });

  test('cold start recovers a pending move after work publish', () async {
    final source = _todo('todo', text: 'Recover me too');
    final base = WorkData();
    await LocalStore.writeWork(base, expectedRevision: 0);
    await LocalStore.writeTodo(source);
    final task = _movedTask(source);
    final next = _withTask(base, task);
    await Hive.box('work').put('state', next.toMap());
    await Hive.box('work').put('pending', _pendingMove(task, source, next));
    await Hive.box('work').flush();

    await coldStart();

    expect(_encodedWork(LocalStore.readWork()), _encodedWork(next));
    expect(LocalStore.readTodos(), isEmpty);
    expect(Hive.box('work').containsKey('pending'), isFalse);
  });

  test('changed source during interrupted conversion is preserved', () async {
    final source = _todo('todo', text: 'Original');
    final changed = _todo('todo', text: 'Changed later');
    final base = WorkData();
    await LocalStore.writeWork(base, expectedRevision: 0);
    await LocalStore.writeTodo(source);
    final task = _movedTask(source);
    final next = _withTask(base, task);
    await Hive.box('work').put('pending', _pendingMove(task, source, next));
    await Hive.box('work').flush();
    await Hive.box('todos').put(changed.id, changed.toMap());
    await Hive.box('todos').flush();

    await coldStart();

    expect(LocalStore.readTodos().single.text, 'Changed later');
    expect(LocalStore.readWork().tasks, isEmpty);
    expect(Hive.box('work').containsKey('pending'), isFalse);
  });

  test(
    'malformed pending move without its target does not delete the source',
    () async {
      final source = _todo('todo', text: 'Keep source');
      final published = WorkData(
        revision: 1,
        tasks: [WorkTask(meta: _meta('other'), title: 'Unrelated work')],
      );
      await LocalStore.writeTodo(source);
      await Hive.box('work').put('state', published.toMap());
      await Hive.box('work').put('pending', {
        'kind': 'todoMove',
        'schemaVersion': 1,
        'source': source.toMap(),
        'targetTaskId': 'todo',
        'areaId': null,
        'projectId': null,
        'work': published.toMap(),
      });
      await Hive.box('work').flush();

      await expectLater(coldStart(), throwsFormatException);

      expect(LocalStore.readTodos().single.text, 'Keep source');
      expect(_encodedWork(LocalStore.readWork()), _encodedWork(published));
      expect(Hive.box('work').containsKey('pending'), isTrue);
    },
  );

  test(
    'malformed pending move with mismatched source fields is rejected',
    () async {
      final source = _todo('todo', text: 'Original\nBody');
      final badTask = WorkTask(
        meta: _meta('todo'),
        title: 'Changed title',
        sourceTodoId: 'todo',
        status: WorkTaskStatus.notStarted,
      );
      final badWork = WorkData(revision: 1, tasks: [badTask]);
      await LocalStore.writeTodo(source);
      await Hive.box(
        'work',
      ).put('pending', _pendingMove(badTask, source, badWork));
      await Hive.box('work').flush();

      await expectLater(coldStart(), throwsFormatException);

      expect(LocalStore.readTodos().single.text, 'Original\nBody');
      expect(LocalStore.readWork().tasks, isEmpty);
      expect(Hive.box('work').containsKey('pending'), isTrue);
    },
  );

  test(
    'changed source after work publish keeps both copies during recovery',
    () async {
      final source = _todo('todo', text: 'Original');
      final changed = _todo('todo', text: 'Changed later');
      final base = WorkData();
      await LocalStore.writeWork(base, expectedRevision: 0);
      await LocalStore.writeTodo(source);
      final task = _movedTask(source);
      final next = _withTask(base, task);
      await Hive.box('work').put('state', next.toMap());
      await Hive.box('work').put('pending', _pendingMove(task, source, next));
      await Hive.box('work').flush();
      await Hive.box('todos').put(changed.id, changed.toMap());
      await Hive.box('todos').flush();

      await coldStart();

      expect(_encodedWork(LocalStore.readWork()), _encodedWork(next));
      expect(LocalStore.readTodos().single.text, 'Changed later');
      expect(Hive.box('work').containsKey('pending'), isFalse);
    },
  );

  test('plain work pending recovery still works', () async {
    final pending = WorkData(
      revision: 1,
      tasks: [WorkTask(meta: _meta('task'), title: 'Legacy pending')],
    );
    await Hive.box('work').put('pending', pending.toMap());
    await Hive.box('work').flush();

    await coldStart();

    expect(_encodedWork(LocalStore.readWork()), _encodedWork(pending));
    expect(Hive.box('work').containsKey('pending'), isFalse);
  });

  test('controller moveToWork reloads its list', () async {
    await LocalStore.writeTodo(_todo('one', text: 'First'));
    await LocalStore.writeTodo(_todo('two', text: 'Second'));
    final controller = TodosController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final moved = await controller.moveToWork('one');
    await Future<void>.delayed(const Duration(milliseconds: 750));

    expect(moved.sourceTodoId, 'one');
    expect(controller.all.map((todo) => todo.id), ['two']);
    expect(notifications, greaterThan(0));
    expect(LocalStore.readTodos().map((todo) => todo.id), ['two']);
    expect(LocalStore.readWork().tasks.single.sourceTodoId, 'one');
  });

  test('queued stale update after move does not recreate the source', () async {
    final original = _todo('todo', text: 'Original');
    await LocalStore.writeTodo(original);
    final controller = TodosController();
    addTearDown(controller.dispose);

    final move = LocalStore.moveTodoToWork('todo');
    final update = controller.update(original.copyWith(text: 'Edited later'));

    await move;
    await expectLater(update, _moveFailure(TodoMoveFailure.alreadyMoved));

    expect(LocalStore.readTodos(), isEmpty);
    expect(LocalStore.readWork().tasks.single.title, 'Original');
    expect(controller.all, isEmpty);
  });

  test('queued stale toggle after move does not recreate the source', () async {
    await LocalStore.writeTodo(_todo('todo', text: 'Original'));
    final controller = TodosController();
    addTearDown(controller.dispose);

    final move = LocalStore.moveTodoToWork('todo');
    final toggle = controller.toggle('todo');

    await move;
    await expectLater(toggle, _moveFailure(TodoMoveFailure.alreadyMoved));

    expect(LocalStore.readTodos(), isEmpty);
    expect(
      LocalStore.readWork().tasks.single.status,
      WorkTaskStatus.notStarted,
    );
    expect(controller.all, isEmpty);
  });
}
