import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/pages/focus_page.dart';
import 'package:streak/features/focus/pages/focus_setup_page.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/focus/state/work_focus_actions.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';

import 'support/app_harness.dart';

final _created = DateTime.utc(2026, 9, 9, 10);

WorkData _work() => WorkData(
  tasks: [
    WorkTask(
      meta: RecordMeta(id: 'task', createdAt: _created),
      title: 'Prepare release notes',
      focusMinutes: 0,
    ),
  ],
);

void main() {
  useEmptyStore();

  setUp(() {
    for (final name in const [
      'dev.fluttercommunity.plus/wakelock',
      'flutter.baseflow.com/permissions/methods',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async => 1);
    }
  });

  testWidgets('starts a Work task without treating it as a free session', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalStore.writeWork(_work(), expectedRevision: 0),
    );
    await pumpScreen(
      tester,
      FocusPage(
        startHabitId: '',
        startTarget: FocusTarget.fromWork(_work(), 'task'),
        startMinutes: 0,
      ),
      settings: {'focusKeepAwake': false},
      textScale: 1.6,
    );

    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(FocusPage), findsOneWidget);
    expect(find.text('Prepare release notes'), findsWidgets);
    expect(find.text('Free session'), findsNothing);
    final focus = tester
        .element(find.byType(FocusPage))
        .read<FocusController>();
    var persisted = false;
    focus.ready.then((_) => persisted = true);
    for (var turn = 0; turn < 100 && !persisted; turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(persisted, isTrue);
  });

  testWidgets('canceling a Work focus switch leaves active focus intact', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalStore.writeWork(_work(), expectedRevision: 0),
    );
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => openWorkFocus(context, taskId: 'task'),
            child: const Text('Focus task'),
          ),
        ),
      ),
      settings: {'focusKeepAwake': false},
    );
    final context = tester.element(find.text('Focus task'));
    final focus = context.read<FocusController>();
    await tester.runAsync(() async {
      focus.start(habitId: '', targetMinutes: 25);
      focus.pause();
      await focus.ready;
    });
    final original = focus.sessionId;

    await tester.tap(find.text('Focus task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(focus.isActive, isTrue);
    expect(focus.sessionId, original);
    expect(find.byType(FocusSetupPage), findsNothing);
  });

  for (final completeTask in [false, true]) {
    testWidgets('saving Work focus keeps completion explicit: $completeTask', (
      tester,
    ) async {
      final end = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      final start = end.subtract(const Duration(minutes: 2));
      await tester.runAsync(() async {
        await LocalStore.writeWork(_work(), expectedRevision: 0);
        await LocalStore.writeFocusActive({
          'habitId': '',
          'target': 25,
          'focus': 25,
          'break': 0,
          'isBreak': false,
          'round': 1,
          'acc': 120,
          'since': '',
          'open': true,
          'sessionId': 'timer',
          'phaseId': 'phase',
          'focusTarget': FocusTarget.fromWork(_work(), 'task').toMap(),
          'phaseStartedAt': start.toIso8601String(),
          'spanStartedAt': '',
          'spans': [FocusSpan(startedAt: start, endedAt: end).toMap()],
        });
      });
      await pumpScreen(
        tester,
        const FocusPage(),
        settings: {'focusKeepAwake': false},
      );
      await tester.tap(find.byTooltip('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End anyway'));
      for (
        var turn = 0;
        turn < 100 && find.byType(CheckboxListTile).evaluate().isEmpty;
        turn++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Next: review the draft.',
      );
      if (completeTask) {
        await tester.tap(find.byType(CheckboxListTile).last);
        await tester.pump();
      }
      await tester.tap(find.text('Save').last);
      for (
        var turn = 0;
        turn < 100 && find.byType(CheckboxListTile).evaluate().isNotEmpty;
        turn++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      await settleStoreWrites(tester);
      final session = LocalStore.readFocusSessions().single;
      expect(session.seconds, 120);
      expect(session.note, 'Next: review the draft.');
      expect(
        LocalStore.readWork().tasks.single.status,
        completeTask ? WorkTaskStatus.done : WorkTaskStatus.notStarted,
      );
    });
  }
}
