import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/work/pages/work_area_page.dart';
import 'package:streak/features/work/pages/work_page.dart';
import 'package:streak/features/work/pages/work_project_page.dart';
import 'package:streak/features/work/pages/work_task_page.dart';
import 'package:streak/features/work/state/work_controller.dart';

import 'support/app_harness.dart';

Future<void> _commit(
  WidgetTester tester,
  WorkController work,
  Finder button,
) async {
  final changed = Completer<void>();
  final revision = work.data.revision;
  void listener() {
    if (work.data.revision > revision && !changed.isCompleted) {
      changed.complete();
    }
  }

  work.addListener(listener);
  try {
    await tester.tap(button);
    for (var turn = 0; turn < 100 && !changed.isCompleted; turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      changed.isCompleted,
      isTrue,
      reason: 'Save must publish the persisted record',
    );
    await tester.pumpAndSettle();
  } finally {
    work.removeListener(listener);
  }
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  useEmptyStore();

  for (final style in [0, 1, 2]) {
    testWidgets(
      'style $style creates area, project, task and subtask through forms',
      (tester) async {
        await pumpScreen(
          tester,
          const WorkPage(),
          minimal: style == 1,
          settings: {'appStyle': style},
          theme: AppTheme.light(null, style),
          darkTheme: AppTheme.dark(null, style),
        );
        final work = tester
            .element(find.byType(WorkPage))
            .read<WorkController>();

        await tester.tap(find.text('Add area').first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('work-area-name-field')),
          'Studio',
        );
        await _commit(tester, work, find.text('Save').last);
        final area = work.data.areas.single;
        expect(area.name, 'Studio');
        await _show(tester, find.byKey(ValueKey('work-area-${area.id}')));
        expect(find.byType(WorkAreaPage), findsOneWidget);

        await tester.tap(find.byTooltip('Add project'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('work-project-name-field')),
          'Launch',
        );
        await _commit(tester, work, find.text('Save').last);
        final project = work.data.projects.single;
        expect(project.areaId, area.id);
        await _show(tester, find.text('Launch'));
        expect(find.byType(WorkProjectPage), findsOneWidget);

        await _show(tester, find.widgetWithText(TextButton, 'Add task'));
        await tester.enterText(
          find.byKey(const ValueKey('work-task-title-field')),
          'Build homepage',
        );
        await _commit(tester, work, find.text('Save').last);
        final task = work.data.tasks.single;
        expect(task.projectId, project.id);
        await _show(tester, find.text('Build homepage'));
        expect(find.byType(WorkTaskPage), findsOneWidget);

        await _show(tester, find.text('Add subtask'));
        await tester.enterText(
          find.byKey(const ValueKey('work-task-title-field')),
          'Write introduction',
        );
        await _commit(tester, work, find.text('Save').last);
        final subtask = work.data.tasks.singleWhere(
          (entry) => entry.id != task.id,
        );
        expect(subtask.parentTaskId, task.id);
        expect(subtask.projectId, project.id);
        expect(LocalStore.readWork().tasks, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
