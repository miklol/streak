import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/app/app_background.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/widgets/goal_habit_links.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/pages/work_insights_page.dart';

import 'support/app_harness.dart';
import 'support/preview_harness.dart';

Future<GoalHabitLink> _seed(WidgetTester tester) async {
  final habit = testHabit(
    id: 'habit',
    name: 'Read something thoughtful',
    done: [AppClock.today()],
  );
  final goal = Goal(
    meta: RecordMeta(id: 'goal', createdAt: DateTime.now()),
    title: 'Make steady progress through the reading list',
    measurement: GoalMeasurement.number,
    source: GoalSource.habits,
    unit: 'days',
    target: 30,
  );
  final link = GoalHabitLink.forHabit(
    meta: RecordMeta(id: 'link', createdAt: DateTime.now()),
    goalId: goal.id,
    habit: habit,
    role: GoalHabitRole.contributor,
  );
  await seedHabits(tester, [habit]);
  await tester.runAsync(
    () => LocalStore.updateWork(
      (_) => WorkData(goals: [goal], habitLinks: [link]),
    ),
  );
  return link;
}

Widget _opener(GoalHabitLink link) => AppBackground(
  child: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showGoalHabitLinkEditor(
            context,
            goalId: 'goal',
            habitId: 'habit',
            existing: link,
          ),
          child: const Text('Open connection'),
        ),
      ),
    ),
  ),
);

void main() {
  useEmptyStore();

  for (final style in [0, 1, 2]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'connection editor reflows at 320px and 200% in $style ${mode.name}',
        (tester) async {
          final link = await _seed(tester);
          final semantics = tester.ensureSemantics();
          try {
            await pumpScreen(
              tester,
              _opener(link),
              textScale: 2,
              minimal: style == 1,
              settings: {'appStyle': style},
              themeMode: mode,
              theme: AppTheme.light(null, style),
              darkTheme: AppTheme.dark(null, style),
            );
            tester.view.physicalSize = const Size(320, 900);
            tester.view.devicePixelRatio = 1;
            await tester.pumpAndSettle();
            await tester.tap(find.text('Open connection'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text('Save connection'));
            await tester.pumpAndSettle();
            expect(find.bySemanticsLabel('Save connection'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.text('Save connection'), findsNothing);
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'Work insights reflows at 320px and 200% in $style ${mode.name}',
        (tester) async {
          await pumpScreen(
            tester,
            const WorkInsightsPage(),
            textScale: 2,
            minimal: style == 1,
            settings: {'appStyle': style},
            themeMode: mode,
            theme: AppTheme.light(null, style),
            darkTheme: AppTheme.dark(null, style),
          );
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          await tester.pumpAndSettle();
          final outcomes = find.textContaining(
            RegExp(r'^Goal outcomes$', caseSensitive: false),
          );
          await tester.scrollUntilVisible(
            outcomes,
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(outcomes, findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'capture measured connection in all styles and appearances',
    (tester) async {
      final folder = Platform.environment['STREAK_GOALS_PREVIEW_DIR']!;
      await loadPreviewFonts();
      final link = await _seed(tester);
      for (final style in [0, 1, 2]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          final key = GlobalKey();
          await pumpScreen(
            tester,
            _opener(link),
            previewKey: key,
            minimal: style == 1,
            settings: {'appStyle': style},
            themeMode: mode,
            theme: AppTheme.light(null, style),
            darkTheme: AppTheme.dark(null, style),
          );
          tester.view.physicalSize = const Size(430, 1030);
          tester.view.devicePixelRatio = 1;
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open connection'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await savePreview(
            tester,
            key,
            '$folder\\goals-connection-$style-${mode.name}.png',
          );
        }
      }
    },
    skip: Platform.environment['STREAK_GOALS_PREVIEW_DIR'] == null,
  );
}
