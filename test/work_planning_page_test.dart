import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/state/work_planning_controller.dart';
import 'package:streak/features/work/widgets/work_planning_section.dart';
import 'package:streak/l10n/app_localizations.dart';
import 'package:streak/services/reminder_schedule.dart';

import 'support/app_harness.dart';

RecordMeta _meta(String id) =>
    RecordMeta(id: id, createdAt: DateTime(2026, 9, 9, 8));

WorkTask _task(String id, {List<DateTime> reminders = const []}) =>
    WorkTask(meta: _meta(id), title: 'Draft launch', reminders: reminders);

Future<void> _seedTask(String id, {List<DateTime> reminders = const []}) =>
    LocalStore.updateWork(
      (data) => data.copyWith(tasks: [_task(id, reminders: reminders)]),
    );

Future<void> _pumpPlanning(
  WidgetTester tester, {
  Future<void> Function(WorkData data)? scheduler,
  WorkReminderFailure? reminderFailure,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final work = WorkController(now: () => DateTime(2026, 9, 9, 9));
  final planning = WorkPlanningController(
    work,
    scheduler: scheduler ?? (_) async {},
  )..reminderFailure = reminderFailure;
  addTearDown(planning.dispose);
  addTearDown(work.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider.value(value: work),
        ChangeNotifierProvider.value(value: planning),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: WorkPlanningSection(taskId: 'task'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  useEmptyStore();

  testWidgets('saving a planned block keeps its timestamp and task deadline independent', (tester) async {
    await tester.runAsync(() => _seedTask('task'));
    await _pumpPlanning(tester);
    await tester.tap(find.byKey(const ValueKey('work-plan-add-block')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('work-plan-start-date')), '2099-01-01');
    await tester.enterText(find.byKey(const ValueKey('work-plan-start-time')), '10:30');
    await tester.enterText(find.byKey(const ValueKey('work-plan-duration')), '45');
    await tester.tap(find.byKey(const ValueKey('work-plan-save-block')));
    for (var index = 0; index < 100 &&
        find.byKey(const ValueKey('work-plan-start-date')).evaluate().isNotEmpty; index++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    final data = LocalStore.readWork();
    expect(data.blocks.single.minutes, 45);
    expect(data.blocks.single.startsAt, DateTime(2099, 1, 1, 10, 30).toUtc());
    expect(data.tasks.single.dueDate, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extreme plan input is rejected without evaluating an unbounded interval', (tester) async {
    await tester.runAsync(() => _seedTask('task'));
    await _pumpPlanning(tester, textScale: 2);
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('work-plan-add-block')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('work-plan-duration')), '999999999999');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('work-plan-save-block')));
    await tester.pumpAndSettle();
    expect(find.text('Use a duration from 1 minute to 24 hours.'), findsOneWidget);
    expect(LocalStore.readWork().blocks, isEmpty);
  });

  testWidgets('plan editor validates and cancels without saving', (
    tester,
  ) async {
    await tester.runAsync(() => _seedTask('task'));
    await _pumpPlanning(tester);

    await tester.tap(find.byKey(const ValueKey('work-plan-add-block')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).at(0), '2099-01-01');
    await tester.enterText(find.byType(TextField).at(1), '10:00');
    await tester.enterText(find.byType(TextField).at(2), '0');
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('work-plan-save-block')),
          )
          .onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(
      find.text('Use a duration from 1 minute to 24 hours.'),
      findsOneWidget,
    );

    tester
        .widget<TextButton>(
          find.ancestor(
            of: find.text('Cancel'),
            matching: find.byType(TextButton),
          ),
        )
        .onPressed!();
    await tester.pump(const Duration(milliseconds: 300));
    expect(LocalStore.readWork().blocks, isEmpty);
    expect(
      find.text('No planned work yet'),
      findsOneWidget,
    );
    expect(
      find.text('Add a time block to plan when you want to work on this task.'),
      findsOneWidget,
    );
  });

  testWidgets('reminder scheduling errors stay visible', (tester) async {
    await tester.runAsync(
      () => _seedTask(
        'task',
        reminders: [DateTime(2099, 1, 1, 9, 30).toUtc()],
      ),
    );
    await _pumpPlanning(
      tester,
      reminderFailure: WorkReminderFailure.platformUnsupported,
    );

    expect(LocalStore.readWork().tasks.single.reminders, hasLength(1));
    expect(
      find.textContaining('scheduled work reminders are not supported'),
      findsOneWidget,
    );
  });

  testWidgets('planning section fits large text without overflow', (
    tester,
  ) async {
    await tester.runAsync(() => _seedTask('task'));
    await _pumpPlanning(tester, textScale: 2);

    expect(find.text('PLAN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
