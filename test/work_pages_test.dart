import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/pages/work_page.dart';
import 'package:streak/features/work/pages/work_task_page.dart';
import 'package:streak/features/work/state/work_controller.dart';

import 'support/app_harness.dart';

final _now = DateTime.utc(2026, 9, 9, 12);

RecordMeta _meta(String id) => RecordMeta(id: id, createdAt: _now);

Future<void> _seedOverview(WidgetTester tester) async {
  await tester.runAsync(
    () => LocalStore.updateWork(
      (_) => WorkData(
        areas: [
          WorkArea(meta: _meta('studio'), name: 'Independent studio'),
        ],
        projects: [
          WorkProject(
            meta: _meta('site'),
            name: 'Website refresh',
            areaId: 'studio',
            status: WorkProjectStatus.active,
          ),
        ],
        tasks: [
          WorkTask(
            meta: _meta('landing'),
            title: 'Landing page',
            projectId: 'site',
            status: WorkTaskStatus.inProgress,
          ),
          WorkTask(
            meta: _meta('layout'),
            title: 'Design responsive layout',
            parentTaskId: 'landing',
            projectId: 'site',
            priority: TodoPriority.high,
          ),
          WorkTask(
            meta: _meta('ideas'),
            title: 'Collect research notes',
          ),
          WorkTask(
            meta: _meta('invoice'),
            title: 'Send September invoice',
            dueDate: _now.subtract(const Duration(days: 1)).dayKey,
          ),
        ],
      ),
    ),
  );
}

Future<void> _seedTaskHierarchy(WidgetTester tester) async {
  await tester.runAsync(
    () => LocalStore.updateWork(
      (_) => WorkData(
        areas: [
          WorkArea(meta: _meta('client'), name: 'Client work'),
        ],
        projects: [
          WorkProject(
            meta: _meta('launch'),
            name: 'Launch site',
            areaId: 'client',
            status: WorkProjectStatus.active,
          ),
        ],
        tasks: [
          WorkTask(
            meta: _meta('parent'),
            title: 'Ship homepage',
            projectId: 'launch',
          ),
          WorkTask(
            meta: _meta('child'),
            title: 'Finish hero copy',
            projectId: 'launch',
            parentTaskId: 'parent',
            progressMode: WorkTaskProgress.manual,
            progress: 40,
          ),
        ],
      ),
    ),
  );
}

void main() {
  useEmptyStore();

  testWidgets('the Work overview reacts to new inbox tasks', (
    tester,
  ) async {
    await pumpScreen(tester, const WorkPage());

    final work = Provider.of<WorkController>(
      tester.element(find.byType(WorkPage)),
      listen: false,
    );
    await tester.runAsync(
      () => work.saveTask(
        WorkTask(meta: WorkController.newMeta(), title: 'Plan stakeholder workshop'),
      ),
    );
    await tester.pumpAndSettle();
    expect(work.tasks(inboxOnly: true).single.title, 'Plan stakeholder workshop');
  });

  testWidgets('shows search and filter states including matching subtasks', (
    tester,
  ) async {
    await _seedOverview(tester);
    await pumpScreen(tester, const WorkPage());

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('work-search-field')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('work-search-field')), 'responsive');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('work-task-layout')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('work-task-layout')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('work-search-field')), 'no-match-query');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches that search.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('work-search-field')), '');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inbox').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Collect research notes'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Collect research notes'), findsOneWidget);

    await tester.tap(find.text('Overdue').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Send September invoice'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Send September invoice'), findsOneWidget);
  });

  testWidgets('shows subtasks and supports editable notes on task details', (
    tester,
  ) async {
    await _seedTaskHierarchy(tester);
    await pumpScreen(tester, const WorkTaskPage(taskId: 'parent'));

    final work = Provider.of<WorkController>(
      tester.element(find.byType(WorkTaskPage)),
      listen: false,
    );
    await tester.scrollUntilVisible(find.text('Finish hero copy'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Finish hero copy'), findsOneWidget);

    await tester.runAsync(
      () => work.setTaskStatus(
        'parent',
        WorkTaskStatus.done,
        completeSubtasks: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(work.taskById('parent')!.status, WorkTaskStatus.done);
    expect(work.taskById('child')!.status, WorkTaskStatus.done);
    await tester.scrollUntilVisible(find.text('1 of 1 done'), -250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 done'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Add note'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('work-note-field')), 'Keep the client posted.');
    await tester.tap(find.text('Save').last);
    for (var i = 0; i < 100 &&
        work.entriesFor(WorkEntityKind.task, 'parent').where((entry) =>
            entry.text == 'Keep the client posted.').isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Keep the client posted.'), findsOneWidget);
  });

  testWidgets('updates archive and restore affordances for tasks', (tester) async {
    await _seedTaskHierarchy(tester);
    await pumpScreen(tester, const WorkTaskPage(taskId: 'child'));

    final work = Provider.of<WorkController>(
      tester.element(find.byType(WorkTaskPage)),
      listen: false,
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsNothing);
    expect(find.text('Move down'), findsNothing);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => work.setArchived(WorkEntityKind.task, 'child', true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(work.taskById('child')!.isArchived, isTrue);
    expect(find.byTooltip('Restore'), findsOneWidget);

    await tester.runAsync(
      () => work.setArchived(WorkEntityKind.task, 'child', false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(work.taskById('child')!.isArchived, isFalse);
    expect(find.byTooltip('Archive'), findsOneWidget);
  });

  testWidgets('shows inline validation errors for empty quick add', (
    tester,
  ) async {
    await pumpScreen(tester, const WorkPage());
    await tester.tap(find.text('Add task').first);
    await tester.pumpAndSettle();
    expect(find.text('Enter a title first.'), findsOneWidget);
  });

  for (final style in [0, 1, 2]) {
    testWidgets('style $style work pages reflow at narrow large text', (
      tester,
    ) async {
      await _seedOverview(tester);
      await pumpScreen(
        tester,
        const WorkPage(),
        minimal: style == 1,
        settings: {'appStyle': style},
        textScale: 2,
        theme: AppTheme.light(null, style),
        darkTheme: AppTheme.dark(null, style),
      );
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
