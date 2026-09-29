import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/services/backup_service.dart';
import 'package:streak/services/widget_action_service.dart';

import 'support/app_harness.dart';

void main() {
  useEmptyStore();
  const channel = MethodChannel('home_widget');

  test('an old widget action cannot recreate a moved To-do', () async {
    final todo = testTodo(id: 'moved', text: 'Move this task');
    await LocalStore.writeTodo(todo);
    final stale = [todo];
    await LocalStore.moveTodoToWork(todo.id);
    var cleared = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getWidgetData') {
            return json.encode(['streak://widget?todoId=moved']);
          }
          if (call.method == 'saveWidgetData') {
            cleared = true;
            return true;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect(await WidgetActionService.drain({}, todos: stale), isFalse);
    expect(stale, isEmpty);
    expect(LocalStore.readTodos(), isEmpty);
    expect(
      LocalStore.readWork().tasks.single.status,
      WorkTaskStatus.notStarted,
    );
    expect(cleared, isTrue);
  });

  test('a widget action still updates an existing To-do', () async {
    final todo = testTodo(id: 'existing', text: 'Keep this task');
    await LocalStore.writeTodo(todo);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getWidgetData') {
            return json.encode(['streak://widget?todoId=existing']);
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect(await WidgetActionService.drain({}, todos: [todo]), isTrue);
    expect(LocalStore.readTodos().single.done, isTrue);
  });

  test(
    'restore settles an interrupted move before replacing either domain',
    () async {
      final todo = testTodo(id: 'pending', text: 'Interrupted move');
      await LocalStore.writeTodo(todo);
      final task = WorkTask(
        meta: RecordMeta(id: todo.id, createdAt: todo.createdAt.toUtc()),
        title: todo.title,
        description: todo.body,
        sourceTodoId: todo.id,
      );
      final pending = WorkData(tasks: [task], revision: 1);
      await Hive.box('work').put('pending', {
        'kind': 'todoMove',
        'schemaVersion': 1,
        'source': todo.toMap(),
        'targetTaskId': task.id,
        'areaId': null,
        'projectId': null,
        'work': pending.toMap(),
      });
      final replacement = WorkTask(
        meta: RecordMeta(id: 'replacement', createdAt: todo.createdAt.toUtc()),
        title: 'Restored Work task',
      );
      final backup = BackupService.parse(
        json.encode({
          'version': 2,
          'habits': [testHabit(id: 'habit', name: 'Restored habit').toMap()],
          'todos': [testTodo(id: 'todo', text: 'Restored To-do').toMap()],
          'work': WorkData(tasks: [replacement]).toMap(),
        }),
      );
      await BackupService.restore(backup, replace: true);
      expect(LocalStore.readWork().tasks.single.id, 'replacement');
      expect(LocalStore.readTodos().single.id, 'todo');
      expect(LocalStore.readHabits().keys, ['habit']);
      expect(Hive.box('work').containsKey('pending'), isFalse);
    },
  );
}
