import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/app/app_background.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/pages/goal_details_page.dart';
import 'package:streak/features/goals/pages/goals_page.dart';
import 'package:streak/features/habits/pages/home_page.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/pages/work_page.dart';

import 'support/app_harness.dart';
import 'support/preview_harness.dart';

void main() {
  useEmptyStore();

  for (final style in [0, 1, 2]) {
    testWidgets(
      'Today opens Personal goals in style $style without requiring a habit',
      (tester) async {
        await pumpScreen(
          tester,
          const HomePage(),
          minimal: style == 1,
          settings: {'appStyle': style},
          theme: AppTheme.light(null, style),
          darkTheme: AppTheme.dark(null, style),
        );
        await tester.tap(find.text('Goals').first);
        await tester.pumpAndSettle();
        expect(
          tester.widget<GoalsPage>(find.byType(GoalsPage)).initialScope,
          GoalScope.personal,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Work opens its view of the same Goals hub in style $style', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const WorkPage(),
        minimal: style == 1,
        settings: {'appStyle': style},
        theme: AppTheme.light(null, style),
        darkTheme: AppTheme.dark(null, style),
      );
      await tester.tap(find.text('Goals').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<GoalsPage>(find.byType(GoalsPage)).initialScope,
        GoalScope.work,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pinned personal goal is visible on Today with no habits', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalStore.updateWork(
        (data) => data.copyWith(
          goals: [
            Goal(
              meta: RecordMeta(id: 'goal', createdAt: DateTime.now()),
              title: 'Learn the piano',
              scope: GoalScope.personal,
              pinned: true,
            ),
          ],
        ),
      ),
    );
    await pumpScreen(tester, const HomePage());
    expect(find.text('Learn the piano'), findsOneWidget);
  });

  testWidgets(
    'capture shared goals hub and progress detail in all themes',
    (tester) async {
      final folder = Platform.environment['STREAK_GOALS_PREVIEW_DIR']!;
      await loadPreviewFonts();
      final now = DateTime.now();
      RecordMeta meta(String id) =>
          RecordMeta(id: id, createdAt: now.subtract(const Duration(days: 20)));
      await tester.runAsync(
        () => LocalStore.updateWork(
          (_) => WorkData(
            goals: [
              Goal(
                meta: meta('read'),
                title: 'Read 3,000 pages',
                scope: GoalScope.personal,
                description: 'Make more room for thoughtful reading.',
                category: 'Learning',
                status: GoalStatus.active,
                measurement: GoalMeasurement.number,
                unit: 'pages',
                current: 900,
                target: 3000,
                pinned: true,
              ),
              Goal(
                meta: meta('save'),
                title: 'Build an emergency fund',
                scope: GoalScope.personal,
                status: GoalStatus.active,
                measurement: GoalMeasurement.currency,
                currency: 'USD',
                current: 2500,
                target: 8000,
                category: 'Finances',
              ),
              Goal(
                meta: meta('launch'),
                title: 'Launch the portfolio',
                scope: GoalScope.work,
              ),
            ],
            entries: [
              WorkEntry(
                meta: meta('entry'),
                entityKind: WorkEntityKind.goal,
                entityId: 'read',
                kind: WorkEntryKind.progress,
                previousValue: 650,
                value: 900,
                measurementUnit: 'pages',
                measurementKind: 'number',
                measurementSource: 'manual',
                measurementBaseline: 0,
                measurementTarget: 3000,
                text: 'Finished the next book. Choose a biography next.',
              ),
            ],
          ),
        ),
      );
      for (final style in [0, 1, 2]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          for (final detail in [false, true]) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            final key = GlobalKey();
            await pumpScreen(
              tester,
              RepaintBoundary(
                key: key,
                child: AppBackground(
                  child: detail
                      ? const GoalDetailsPage(goalId: 'read')
                      : const GoalsPage(),
                ),
              ),
              minimal: style == 1,
              settings: {'appStyle': style},
              theme: AppTheme.light(null, style),
              darkTheme: AppTheme.dark(null, style),
              themeMode: mode,
            );
            tester.view.physicalSize = const Size(430, 932);
            tester.view.devicePixelRatio = 1;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await savePreview(
              tester,
              key,
              '$folder\\goals-${detail ? 'detail' : 'hub'}-$style-${mode.name}.png',
            );
            await settleStoreWrites(tester);
          }
        }
      }
    },
    skip: Platform.environment['STREAK_GOALS_PREVIEW_DIR'] == null,
  );
}
