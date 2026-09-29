import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/app_background.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/focus/pages/focus_page.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/pages/work_task_page.dart';
import 'package:streak/features/work/widgets/work_planning_section.dart';
import 'package:streak/features/work/widgets/work_time_section.dart';

import 'support/app_harness.dart';
import 'support/preview_harness.dart';

void main() {
  useEmptyStore();

  testWidgets(
    'capture task focus planning and time history across styles',
    (tester) async {
      final output = Platform.environment['STREAK_STAGE3_PREVIEW_DIR']!;
      await loadPreviewFonts();
      final now = DateTime.now();
      RecordMeta meta(String id) =>
          RecordMeta(id: id, createdAt: now.subtract(const Duration(days: 2)));
      final work = WorkData(
        projects: [WorkProject(meta: meta('project'), name: 'Website refresh')],
        tasks: [
          WorkTask(
            meta: meta('task'),
            title: 'Build the landing page',
            projectId: 'project',
            status: WorkTaskStatus.inProgress,
            description: 'Create a clear introduction to our latest work.',
          ),
          WorkTask(
            meta: meta('child'),
            title: 'Write the introduction',
            parentTaskId: 'task',
            projectId: 'project',
            status: WorkTaskStatus.done,
          ),
        ],
        blocks: [
          WorkPlanBlock(
            meta: meta('block'),
            taskId: 'task',
            startsAt: DateTime(now.year, now.month, now.day + 1, 10),
            minutes: 45,
            note: 'Finish the responsive layout',
          ),
        ],
      );
      final target = FocusTarget.fromWork(work, 'task');
      await tester.runAsync(() async {
        await LocalStore.writeWork(work, expectedRevision: 0);
        final start = now.subtract(const Duration(hours: 2));
        final end = start.add(const Duration(minutes: 25));
        await LocalStore.writeFocusSession(
          FocusSession(
            id: 'session',
            habitId: '',
            target: target,
            targetMinutes: 25,
            startedAt: start,
            endedAt: end,
            seconds: 1500,
            completed: true,
            note: 'Outlined the content. Next: refine spacing.',
            spans: [FocusSpan(startedAt: start, endedAt: end)],
          ),
        );
      });
      for (final style in [0, 1, 2]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(() => LocalStore.writeFocusActive({}));
          Future<GlobalKey> show(Widget page) async {
            final key = GlobalKey();
            await pumpScreen(
              tester,
              RepaintBoundary(
                key: key,
                child: AppBackground(child: page),
              ),
              minimal: style == 1,
              settings: {'appStyle': style, 'focusKeepAwake': false},
              theme: AppTheme.light(null, style),
              darkTheme: AppTheme.dark(null, style),
              themeMode: mode,
            );
            tester.view.physicalSize = const Size(430, 932);
            tester.view.devicePixelRatio = 1;
            await tester.pumpAndSettle();
            return key;
          }

          Future<void> capture(GlobalKey key, String name) => savePreview(
            tester,
            key,
            File.fromUri(
              Directory(output).uri.resolve('$name-$style-${mode.name}.png'),
            ).path,
          );
          final key = await show(const WorkTaskPage(taskId: 'task'));
          await capture(key, 'task');
          await tester.scrollUntilVisible(
            find.byType(WorkPlanningSection),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await capture(key, 'planning');
          await tester.scrollUntilVisible(
            find.byType(WorkTimeSection),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await capture(key, 'time');
          final focus = tester
              .element(find.byType(WorkTaskPage))
              .read<FocusController>();
          await tester.runAsync(() async {
            focus.start(habitId: '', target: target, targetMinutes: 25);
            focus.pause(at: DateTime.now().add(const Duration(minutes: 2)));
            await focus.ready;
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          final timer = await show(const FocusPage());
          await capture(timer, 'focus');
          expect(tester.takeException(), isNull);
          await settleStoreWrites(tester);
        }
      }
    },
    skip: Platform.environment['STREAK_STAGE3_PREVIEW_DIR'] == null,
  );
}
