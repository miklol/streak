import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/widgets/work_time_section.dart';

import 'support/app_harness.dart';

Future<void> _seed(WidgetTester tester) async {
  await tester.runAsync(
    () => LocalStore.updateWork(
      (_) => WorkData(
        tasks: [
          WorkTask(
            meta: RecordMeta(
              id: 'task',
              createdAt: DateTime.now().subtract(const Duration(days: 3)),
            ),
            title: 'Prepare release',
          ),
        ],
      ),
    ),
  );
}

void main() {
  useEmptyStore();

  testWidgets('manual Work time saves independently from task completion', (
    tester,
  ) async {
    await _seed(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: WorkTimeSection(taskId: 'task')),
      ),
    );
    await tester.tap(find.text('Log time'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('work-time-minutes')),
      '10',
    );
    await tester.enterText(
      find.byKey(const ValueKey('work-time-note')),
      'Drafted the notes',
    );
    await tester.tap(find.text('Save').last);
    for (
      var count = 0;
      count < 100 &&
          find.byKey(const ValueKey('work-time-minutes')).evaluate().isNotEmpty;
      count++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    final session = LocalStore.readFocusSessions().single;
    expect(session.source, FocusEntrySource.manual);
    expect(session.seconds, 600);
    expect(session.note, 'Drafted the notes');
    expect(session.target.id, 'task');
    expect(
      LocalStore.readWork().tasks.single.status,
      WorkTaskStatus.notStarted,
    );
    expect(find.text('Manually recorded'), findsOneWidget);
  });

  testWidgets('time entry validates its duration before writing', (
    tester,
  ) async {
    await _seed(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: WorkTimeSection(taskId: 'task')),
      ),
    );
    await tester.tap(find.text('Log time'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('work-time-minutes')),
      '0',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Enter a duration greater than zero and no longer than 24 hours.',
      ),
      findsOneWidget,
    );
    expect(LocalStore.readFocusSessions(), isEmpty);
  });

  testWidgets('read-only history has no add or edit controls', (tester) async {
    await _seed(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: WorkTimeSection(taskId: 'task', readOnly: true),
        ),
      ),
    );
    expect(find.text('Log time'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    final focus = tester
        .element(find.byType(WorkTimeSection))
        .read<FocusController>();
    expect(focus.sessions, isEmpty);
  });

  testWidgets('time entry and summaries reflow at enlarged text', (
    tester,
  ) async {
    await _seed(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: WorkTimeSection(taskId: 'task')),
      ),
      textScale: 2,
    );
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Log time'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
