import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/widgets/goal_form.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';

import 'support/app_harness.dart';

RecordMeta _meta(String id) =>
    RecordMeta(id: id, createdAt: DateTime(2026, 1, 1));

Future<void> _pumpFormButton(
  WidgetTester tester, {
  Goal? goal,
  GoalScope scope = GoalScope.personal,
  String? areaId,
  String? projectId,
  String? habitId,
  String? taskId,
}) async {
  await pumpScreen(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showGoalForm(
              context,
              goal: goal,
              scope: scope,
              areaId: areaId,
              projectId: projectId,
              habitId: habitId,
              taskId: taskId,
            ),
            child: const Text('Open form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open form'));
  await tester.pumpAndSettle();
}

Future<void> _tapText(
  WidgetTester tester,
  String text, {
  bool last = false,
}) async {
  final finder = find.text(text, skipOffstage: false);
  final target = last ? finder.last : finder.first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _chooseDropdown(WidgetTester tester, Key key, String label) async {
  final visible = find.byKey(key);
  final scrollable = find.byType(Scrollable).last;
  for (var i = 0; i < 8 && visible.evaluate().isEmpty; i++) {
    await tester.drag(scrollable, const Offset(0, -420), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
  await tester.tap(visible);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  useEmptyStore();

  testWidgets('creates a title-only Personal goal from actual form fields', (
    tester,
  ) async {
    await _pumpFormButton(tester);
    await tester.enterText(
      find.byKey(const ValueKey('goal-title-field')),
      'Read more',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await settleStoreWrites(tester);

    final goal = LocalStore.readWork().goals.single;
    expect(goal.title, 'Read more');
    expect(goal.scope, GoalScope.personal);
    expect(goal.source, GoalSource.manual);
    expect(goal.measurement, GoalMeasurement.completion);
  });

  testWidgets(
    'creates a Work rollup and prevents project task double-counting',
    (
      tester,
    ) async {
      await tester.runAsync(
        () => LocalStore.updateWork(
          (_) => WorkData(
            areas: [WorkArea(meta: _meta('area'), name: 'Client')],
            projects: [
              WorkProject(
                meta: _meta('project'),
                name: 'Launch',
                areaId: 'area',
              ),
            ],
            tasks: [
              WorkTask(
                meta: _meta('task'),
                title: 'Draft landing page',
                projectId: 'project',
              ),
            ],
          ),
        ),
      );
      await _pumpFormButton(tester, scope: GoalScope.work);
      await tester.enterText(
        find.byKey(const ValueKey('goal-title-field')),
        'Ship launch',
      );
      await _chooseDropdown(
        tester,
        const ValueKey('goal-source-field'),
        'Work delivery',
      );
      await _tapText(tester, 'Select work contributors');
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Launch'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Draft landing page', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Already counted by a selected parent or project.'),
        findsOneWidget,
      );
      await _tapText(tester, 'Done');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await settleStoreWrites(tester);

      final goal = LocalStore.readWork().goals.single;
      expect(goal.scope, GoalScope.work);
      expect(goal.source, GoalSource.work);
      expect(goal.measurement, GoalMeasurement.percentage);
      expect(goal.projectIds, ['project']);
      expect(goal.taskIds, isEmpty);
    },
  );

  testWidgets(
    'manual number goals keep invalid input and allow decreasing targets',
    (
      tester,
    ) async {
      await _pumpFormButton(tester);
      await tester.enterText(
        find.byKey(const ValueKey('goal-title-field')),
        'Reduce backlog',
      );
      await _chooseDropdown(
        tester,
        const ValueKey('goal-measurement-field'),
        'Number',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Baseline'),
        '100',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current value'),
        'NaN',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Target'),
        '10',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Unit'),
        'tasks',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(find.text('Enter a finite number.'), findsOneWidget);
      expect(find.text('NaN'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current value'),
        '75',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await settleStoreWrites(tester);
      final goal = LocalStore.readWork().goals.single;
      expect(goal.baseline, 100);
      expect(goal.current, 75);
      expect(goal.target, 10);
    },
  );

  testWidgets('task-scoped Work goal keeps the task as a related reference', (
    tester,
  ) async {
    await tester.runAsync(
      () => LocalStore.updateWork(
        (_) => WorkData(
          areas: [WorkArea(meta: _meta('area'), name: 'Client')],
          projects: [
            WorkProject(meta: _meta('project'), name: 'Launch', areaId: 'area'),
          ],
          tasks: [
            WorkTask(
              meta: _meta('task'),
              title: 'Draft landing page',
              projectId: 'project',
            ),
          ],
        ),
      ),
    );
    await _pumpFormButton(
      tester,
      scope: GoalScope.work,
      areaId: 'area',
      projectId: 'project',
      taskId: 'task',
    );
    await tester.enterText(
      find.byKey(const ValueKey('goal-title-field')),
      'Improve launch quality',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await settleStoreWrites(tester);

    final goal = LocalStore.readWork().goals.single;
    expect(goal.scope, GoalScope.work);
    expect(goal.source, GoalSource.manual);
    expect(goal.taskIds, ['task']);
  });

  testWidgets(
    'creating from a habit adds one supporting relationship atomically',
    (
      tester,
    ) async {
      await seedHabits(tester, [testHabit(id: 'habit', name: 'Read daily')]);
      await _pumpFormButton(tester, habitId: 'habit');
      await tester.enterText(
        find.byKey(const ValueKey('goal-title-field')),
        'Read consistently',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await settleStoreWrites(tester);

      final data = LocalStore.readWork();
      expect(data.goals.single.title, 'Read consistently');
      expect(data.habitLinks.single.goalId, data.goals.single.id);
      expect(data.habitLinks.single.habitId, 'habit');
      expect(data.habitLinks.single.role, GoalHabitRole.supporting);
    },
  );
}
