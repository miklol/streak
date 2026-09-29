import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/home_shell.dart';
import 'package:streak/app/app_background.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/pages/work_page.dart';

import 'support/app_harness.dart';
import 'support/preview_harness.dart';

final _day = DateTime(2026, 9, 9, 12);
RecordMeta _meta(String id) => RecordMeta(id: id, createdAt: _day);

Future<void> _seedWork(WidgetTester tester) async {
  await tester.runAsync(
    () => LocalStore.updateWork(
      (_) => WorkData(
        areas: [
          WorkArea(
            meta: _meta('studio'),
            name: 'Independent studio',
            description: 'Design and development',
            role: 'Product designer',
          ),
        ],
        projects: [
          WorkProject(
            meta: _meta('website'),
            name: 'Website refresh',
            areaId: 'studio',
            status: WorkProjectStatus.active,
            description: 'A clearer home for our latest work.',
          ),
        ],
        tasks: [
          WorkTask(
            meta: _meta('landing'),
            title: 'Build the new landing page',
            projectId: 'website',
            status: WorkTaskStatus.inProgress,
          ),
          WorkTask(
            meta: _meta('copy'),
            title: 'Write the introduction',
            parentTaskId: 'landing',
            projectId: 'website',
            status: WorkTaskStatus.done,
          ),
          WorkTask(
            meta: _meta('layout'),
            title: 'Design the responsive layout',
            parentTaskId: 'landing',
            projectId: 'website',
            order: 1,
          ),
          WorkTask(
            meta: _meta('research'),
            title: 'Collect references for the next project',
            description:
                'Review useful examples and note what makes them work.',
          ),
        ],
      ),
    ),
  );
}

void main() {
  useEmptyStore();

  for (final style in [0, 2]) {
    testWidgets('Work opens from the style $style floating navigation', (
      tester,
    ) async {
      await _seedWork(tester);
      await pumpScreen(
        tester,
        const HomeShell(),
        settings: {'appStyle': style},
        theme: AppTheme.light(null, style),
        darkTheme: AppTheme.dark(null, style),
      );
      await tester.tap(find.byTooltip('Work').first);
      await tester.pumpAndSettle();
      expect(find.byType(WorkPage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Build the new landing page'),
        200,
        scrollable: find.descendant(
          of: find.byType(WorkPage),
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(find.text('Build the new landing page'), findsWidgets);
    });
  }

  testWidgets('Work can be hidden without deleting its records', (
    tester,
  ) async {
    await _seedWork(tester);
    await pumpScreen(
      tester,
      const HomeShell(),
      settings: {'workEnabled': false},
    );
    expect(find.byTooltip('Work'), findsNothing);
    expect(LocalStore.readWork().tasks, hasLength(4));
    final settings = Provider.of<SettingsController>(
      tester.element(find.byType(HomeShell)),
      listen: false,
    );
    await tester.runAsync(() => settings.setWorkEnabled(true));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Work'), findsOneWidget);
  });

  testWidgets('minimal mobile exposes Work through the labeled page switcher', (
    tester,
  ) async {
    await _seedWork(tester);
    await pumpScreen(tester, const HomeShell(), minimal: true);
    await tester.tap(find.byTooltip('Today').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    expect(find.byType(WorkPage), findsOneWidget);
  });

  for (final style in [0, 1, 2]) {
    testWidgets('style $style navigation survives narrow enlarged text', (
      tester,
    ) async {
      await _seedWork(tester);
      await pumpScreen(
        tester,
        const HomeShell(),
        minimal: style == 1,
        settings: {'appStyle': style, 'planningEnabled': true},
        textScale: 2,
        theme: AppTheme.light(null, style),
        darkTheme: AppTheme.dark(null, style),
      );
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (style == 1) {
        await tester.tap(find.byTooltip('Today').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Work').last);
      } else {
        await tester.tap(find.byTooltip('Work').first);
      }
      await tester.pumpAndSettle();
      expect(find.byType(WorkPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('style $style desktop Work navigation accepts the keyboard', (
      tester,
    ) async {
      await _seedWork(tester);
      await pumpScreen(
        tester,
        const HomeShell(),
        minimal: style == 1,
        settings: {'appStyle': style},
        theme: AppTheme.light(null, style),
        darkTheme: AppTheme.dark(null, style),
      );
      tester.view.physicalSize = const Size(1450, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      final icon = find.byIcon(LucideIcons.briefcase).first;
      final focus = Focus.of(tester.element(icon));
      expect(focus.canRequestFocus, isTrue);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(WorkPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Work overview reflows in RTL', (tester) async {
    await _seedWork(tester);
    await pumpScreen(
      tester,
      const Directionality(textDirection: TextDirection.rtl, child: WorkPage()),
      textScale: 2,
    );
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'capture the Work overview in the existing visual styles',
    (tester) async {
      final output = Platform.environment['STREAK_WORK_PREVIEW_DIR']!;
      await loadPreviewFonts();
      await _seedWork(tester);
      for (final style in [0, 1, 2]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          final boundaryKey = GlobalKey();
          await pumpScreen(
            tester,
            RepaintBoundary(key: boundaryKey, child: const AppBackground(child: WorkPage())),
            minimal: style == 1,
            settings: {'appStyle': style},
            theme: AppTheme.light(null, style),
            darkTheme: AppTheme.dark(null, style),
            themeMode: mode,
          );
          tester.view.physicalSize = const Size(430, 900);
          tester.view.devicePixelRatio = 1;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await savePreview(tester, boundaryKey, '$output\\work-style-$style-${mode.name}.png');
        }
      }
    },
    skip: Platform.environment['STREAK_WORK_PREVIEW_DIR'] == null,
  );
}
