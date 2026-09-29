import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/pages/work_page.dart';
import 'package:streak/features/work/pages/work_project_page.dart';
import 'package:streak/features/work/pages/work_task_page.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

import 'support/app_harness.dart';

RecordMeta _meta(String id) =>
    RecordMeta(id: id, createdAt: DateTime(2026, 9, 9));

void main() {
  useEmptyStore();

  testWidgets('editing a task preserves reference URLs containing commas', (
    tester,
  ) async {
    const link = 'https://www.google.com/maps?q=51.5074,-0.1278';
    await tester.runAsync(
      () => LocalStore.updateWork(
        (_) => WorkData(
          tasks: [
            WorkTask(meta: _meta('linked'), title: 'Original', links: [link]),
          ],
        ),
      ),
    );
    await pumpScreen(tester, const WorkTaskPage(taskId: 'linked'));
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('work-task-title-field')),
      'Renamed',
    );
    await tester.tap(find.text('Save').last);
    for (
      var turn = 0;
      turn < 100 &&
          find
              .byKey(const ValueKey('work-task-title-field'))
              .evaluate()
              .isNotEmpty;
      turn++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(LocalStore.readWork().tasks.single.links, [link]);
  });

  testWidgets('inbox tasks can be reordered without creating a project', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalStore.updateWork(
        (_) => WorkData(
          tasks: [
            WorkTask(meta: _meta('first'), title: 'First task', order: 0),
            WorkTask(meta: _meta('second'), title: 'Second task', order: 1),
          ],
        ),
      ),
    );
    await pumpScreen(tester, const WorkPage());
    await tester.ensureVisible(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Move up').last,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move up').last);
    for (
      var turn = 0;
      turn < 100 &&
          LocalStore.readWork().tasks
                  .singleWhere((task) => task.id == 'second')
                  .order !=
              0;
      turn++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      LocalStore.readWork().tasks
          .singleWhere((task) => task.id == 'second')
          .order,
      0,
    );
    expect(LocalStore.readWork().projects, isEmpty);
    await settleStoreWrites(tester);
  });

  testWidgets(
    'archiving an unfinished subtask does not inflate displayed progress',
    (tester) async {
      await tester.runAsync(
        () => LocalStore.updateWork(
          (_) => WorkData(
            tasks: [
              WorkTask(meta: _meta('parent'), title: 'Parent'),
              WorkTask(
                meta: _meta('done'),
                title: 'Done step',
                parentTaskId: 'parent',
                status: WorkTaskStatus.done,
              ),
              WorkTask(
                meta: _meta(
                  'hidden',
                ).revise(at: DateTime(2026, 9, 9), archived: true),
                title: 'Archived step',
                parentTaskId: 'parent',
              ),
            ],
          ),
        ),
      );
      await pumpScreen(tester, const WorkTaskPage(taskId: 'parent'));
      final work = tester
          .element(find.byType(WorkTaskPage))
          .read<WorkController>();
      expect(workTaskFraction(work, work.taskById('parent')!), .5);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('1 of 2 done'), findsOneWidget);
    },
  );

  testWidgets('an empty project has no indefinite loading animation', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalStore.updateWork(
        (_) => WorkData(
          projects: [
            WorkProject(meta: _meta('empty'), name: 'Empty project'),
          ],
        ),
      ),
    );
    await pumpScreen(tester, const WorkProjectPage(projectId: 'empty'));
    for (final bar in tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    )) {
      expect(bar.value, 0);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate dialog validates and survives its closing animation', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalStore.updateWork(
        (_) => WorkData(
          tasks: [
            WorkTask(meta: _meta('task'), title: 'Original task'),
          ],
        ),
      ),
    );
    await pumpScreen(tester, const WorkTaskPage(taskId: 'task'));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Duplicate task'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a title first.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'New task');
    await tester.tap(find.widgetWithText(FilledButton, 'Duplicate task'));
    for (
      var turn = 0;
      turn < 100 && LocalStore.readWork().tasks.length < 2;
      turn++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      LocalStore.readWork().tasks.map((task) => task.title),
      containsAll(['Original task', 'New task']),
    );
    await settleStoreWrites(tester);
    expect(tester.takeException(), isNull);
  });

  for (final color in [
    AppTokens.light.info,
    AppTokens.light.success,
    AppTokens.light.warning,
    AppTokens.light.danger,
    AppTokens.light.muted,
  ]) {
    testWidgets('status badge ${color.toARGB32()} uses a readable foreground', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: WorkBadge(
            icon: Icons.check,
            label: 'Status',
            color: color,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('Status'));
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(WorkBadge),
              matching: find.byType(Container),
            )
            .first,
      );
      final background = (box.decoration! as BoxDecoration).color!;
      final foreground = text.style!.color!;
      final a = background.computeLuminance();
      final b = foreground.computeLuminance();
      final ratio = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('changing Work styles keeps native button typography valid', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) {
          final style = context.watch<SettingsController>().appStyle;
          return Theme(
            data: AppTheme.light(null, style),
            child: const WorkPage(),
          );
        },
      ),
    );
    final settings = tester
        .element(find.byType(WorkPage))
        .read<SettingsController>();
    for (final style in [2, 1, 0]) {
      await tester.runAsync(() => settings.setAppStyle(style));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
