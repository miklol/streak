import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/pages/goal_details_page.dart';
import 'package:streak/features/goals/pages/goals_page.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';

import 'support/app_harness.dart';

RecordMeta _meta(String id, {int daysAgo = 0}) => RecordMeta(
  id: id,
  createdAt: DateTime(2026, 1, 10).subtract(Duration(days: daysAgo)),
);

Future<void> _seedGoals(WidgetTester tester) async {
  final archivedMeta = _meta('archived', daysAgo: 2).revise(
    at: DateTime(2026, 1, 11),
    archived: true,
  );
  await tester.runAsync(
    () => LocalStore.updateWork(
      (_) => WorkData(
        goals: [
          Goal(
            meta: _meta('pinned'),
            title: 'Read 3,000 pages',
            status: GoalStatus.active,
            measurement: GoalMeasurement.number,
            unit: 'pages',
            current: 900,
            target: 3000,
            pinned: true,
          ),
          Goal(
            meta: _meta('paused', daysAgo: 1),
            title: 'Save for a camera',
            status: GoalStatus.paused,
            measurement: GoalMeasurement.currency,
            currency: 'USD',
            current: 50,
            target: 600,
          ),
          Goal(
            meta: archivedMeta,
            title: 'Old marathon plan',
            status: GoalStatus.cancelled,
          ),
          Goal(
            meta: _meta('habit'),
            title: 'Meditate 30 days',
            source: GoalSource.habits,
            measurement: GoalMeasurement.number,
            unit: 'days',
            target: 30,
          ),
          Goal(
            meta: _meta('snapshot'),
            title: 'Historical distance',
            status: GoalStatus.active,
            measurement: GoalMeasurement.number,
            unit: 'books',
            current: 2,
            target: 5,
          ),
        ],
        entries: [
          WorkEntry(
            meta: _meta('entry'),
            entityKind: WorkEntityKind.goal,
            entityId: 'pinned',
            kind: WorkEntryKind.progress,
            previousValue: 650,
            value: 900,
            measurementUnit: 'pages',
            measurementKind: 'number',
            measurementSource: 'manual',
            measurementBaseline: 0,
            measurementTarget: 3000,
            text: 'Finished another book.',
          ),
          WorkEntry(
            meta: _meta('snapshot-entry'),
            entityKind: WorkEntityKind.goal,
            entityId: 'snapshot',
            kind: WorkEntryKind.progress,
            previousValue: 1,
            value: 2,
            measurementUnit: 'km',
            measurementKind: 'number',
            measurementSource: 'manual',
            measurementBaseline: 0,
            measurementTarget: 10,
          ),
        ],
      ),
    ),
  );
}

void main() {
  useEmptyStore();

  testWidgets(
    'Goals hub filters Personal goals, archives and pinned ordering',
    (
      tester,
    ) async {
      await _seedGoals(tester);
      await pumpScreen(tester, const GoalsPage());

      expect(find.text('Read 3,000 pages'), findsOneWidget);
      expect(find.text('Save for a camera'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Read 3,000 pages')).dy,
        lessThan(tester.getTopLeft(find.text('Save for a camera')).dy),
      );

      await tester.enterText(find.byType(TextField).first, 'camera');
      await tester.pumpAndSettle();
      expect(find.text('Read 3,000 pages'), findsNothing);
      expect(find.text('Save for a camera'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();
      expect(find.text('Old marathon plan'), findsOneWidget);
      expect(find.text('Read 3,000 pages'), findsNothing);
    },
  );

  testWidgets('Goal detail records manual progress and renders dated history', (
    tester,
  ) async {
    await _seedGoals(tester);
    await pumpScreen(tester, const GoalDetailsPage(goalId: 'pinned'));
    await tester.tap(find.text('Record progress'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('goal-progress-value-field')),
      '1200',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Note'),
      'Read during commute.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await settleStoreWrites(tester);

    final goals = tester
        .element(find.byType(GoalDetailsPage))
        .read<GoalsController>();
    expect(goals.byId('pinned')!.current, 1200);
    await scrollToEnd(tester, drags: 4);
    expect(find.text('Read during commute.'), findsOneWidget);
    expect(find.textContaining('Progress changed'), findsWidgets);
  });

  testWidgets('source setup problems render as text, never a spinner', (
    tester,
  ) async {
    await _seedGoals(tester);
    await pumpScreen(tester, const GoalDetailsPage(goalId: 'habit'));
    expect(
      find.text('Add a measured habit contribution to update this goal.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'history uses entry measurement snapshots instead of current goal unit',
    (tester) async {
      await _seedGoals(tester);
      await pumpScreen(tester, const GoalDetailsPage(goalId: 'snapshot'));
      await scrollToEnd(tester, drags: 4);
      expect(find.text('Progress changed from 1 km to 2 km.'), findsOneWidget);
      expect(find.textContaining('1 books'), findsNothing);
    },
  );

  testWidgets(
    'archive, status and pin actions update without leaving the detail',
    (
      tester,
    ) async {
      await _seedGoals(tester);
      await pumpScreen(tester, const GoalDetailsPage(goalId: 'pinned'));
      await tester.tap(find.byTooltip('Unpin from Today'));
      await settleStoreWrites(tester);
      expect(
        LocalStore.readWork().goals.firstWhere((g) => g.id == 'pinned').pinned,
        isFalse,
      );

      await tester.tap(find.byTooltip('Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paused').last);
      await settleStoreWrites(tester);
      expect(
        LocalStore.readWork().goals.firstWhere((g) => g.id == 'pinned').status,
        GoalStatus.paused,
      );

      await tester.tap(find.byTooltip('Archive'));
      await settleStoreWrites(tester);
      expect(
        LocalStore.readWork().goals
            .firstWhere((g) => g.id == 'pinned')
            .isArchived,
        isTrue,
      );
    },
  );

  testWidgets(
    'hub and detail survive narrow two-times text in every app style',
    (
      tester,
    ) async {
      await _seedGoals(tester);
      for (final style in [0, 1, 2]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await pumpScreen(
            tester,
            const GoalsPage(),
            minimal: style == 1,
            settings: {'appStyle': style},
            theme: AppTheme.light(null, style),
            darkTheme: AppTheme.dark(null, style),
            themeMode: mode,
            textScale: 2,
          );
          tester.view.physicalSize = const Size(640, 1280);
          tester.view.devicePixelRatio = 2;
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await pumpScreen(
            tester,
            const GoalDetailsPage(goalId: 'pinned'),
            minimal: style == 1,
            settings: {'appStyle': style},
            theme: AppTheme.light(null, style),
            darkTheme: AppTheme.dark(null, style),
            themeMode: mode,
            textScale: 2,
          );
          tester.view.physicalSize = const Size(640, 1280);
          tester.view.devicePixelRatio = 2;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
