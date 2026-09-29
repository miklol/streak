import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/todos/pages/todos_page.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/pages/work_task_page.dart';

import 'support/app_harness.dart';

void main() {
  useEmptyStore();

  testWidgets('a To-do moves through the picker into the chosen project', (
    tester,
  ) async {
    await seedTodos(tester, [
      testTodo(id: 'todo', text: 'Prepare the release\nWrite the notes'),
    ]);
    await tester.runAsync(
      () => LocalStore.updateWork(
        (_) => WorkData(
          projects: [
            WorkProject(
              meta: RecordMeta(id: 'release', createdAt: DateTime.now()),
              name: 'Release project',
            ),
          ],
        ),
      ),
    );
    await pumpScreen(tester, const TodosPage());
    await tester.tap(find.byTooltip('Actions for Prepare the release'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Release project'));
    for (
      var turn = 0;
      turn < 100 && find.byType(WorkTaskPage).evaluate().isEmpty;
      turn++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(LocalStore.readTodos(), isEmpty);
    final moved = LocalStore.readWork().tasks.single;
    expect(moved.projectId, 'release');
    expect(moved.title, 'Prepare the release');
    expect(moved.description, 'Write the notes');
    expect(find.byType(WorkTaskPage), findsOneWidget);
  });

  testWidgets(
    'To-do actions expose Move to Work without replacing quick editing',
    (tester) async {
      await seedTodos(tester, [
        testTodo(id: 'todo', text: 'Prepare the release'),
      ]);
      await pumpScreen(tester, const TodosPage());
      await tester.tap(find.byTooltip('Actions for Prepare the release'));
      await tester.pumpAndSettle();
      expect(find.text('Move to Work'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(LocalStore.readTodos().single.id, 'todo');
    },
  );

  testWidgets('cancelling a Work destination leaves the To-do intact', (
    tester,
  ) async {
    await seedTodos(tester, [
      testTodo(id: 'todo', text: 'Prepare the release'),
    ]);
    await pumpScreen(tester, const TodosPage());
    await tester.tap(find.byTooltip('Actions for Prepare the release'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Work'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(LocalStore.readTodos().single.id, 'todo');
    expect(LocalStore.readWork().tasks, isEmpty);
    expect(find.text('Prepare the release'), findsWidgets);
  });

  testWidgets('hiding Work removes its To-do action without altering data', (
    tester,
  ) async {
    await seedTodos(tester, [
      testTodo(id: 'todo', text: 'Prepare the release'),
    ]);
    await pumpScreen(
      tester,
      const TodosPage(),
      settings: {'workEnabled': false},
    );
    expect(find.byTooltip('Actions for Prepare the release'), findsNothing);
    expect(LocalStore.readTodos().single.id, 'todo');
  });
}
