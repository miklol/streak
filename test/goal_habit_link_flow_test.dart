import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/goals/widgets/goal_habit_links.dart';
import 'package:streak/features/goals/widgets/related_goals_section.dart';
import 'package:streak/features/habits/pages/habit_details_page.dart';
import 'package:streak/features/habits/pages/habit_form_page.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';

import 'support/app_harness.dart';

Future<void> _seed(WidgetTester tester, {bool measured = false}) async {
  await seedHabits(tester, [
    testHabit(id: 'habit', name: 'Read daily', done: [AppClock.today()]),
  ]);
  await tester.runAsync(
    () => LocalStore.updateWork(
      (_) => WorkData(
        goals: [
          Goal(
            meta: RecordMeta(
              id: 'goal',
              createdAt: DateTime.now().subtract(const Duration(days: 5)),
            ),
            title: 'Read regularly',
            scope: GoalScope.personal,
            source: measured ? GoalSource.habits : GoalSource.manual,
            measurement: measured
                ? GoalMeasurement.number
                : GoalMeasurement.completion,
            unit: measured ? 'days' : '',
            target: measured ? 30 : 1,
          ),
        ],
      ),
    ),
  );
}

Future<void> _settleLink(WidgetTester tester) async {
  await settleStoreWrites(tester);
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  useEmptyStore();

  testWidgets(
    'linking from a goal defaults to support and appears on the habit',
    (tester) async {
      await _seed(tester);
      await pumpScreen(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            child: GoalHabitLinksSection(goalId: 'goal'),
          ),
        ),
      );

      await tester.tap(find.text('Link habit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read daily'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save connection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save connection'));
      await _settleLink(tester);
      final link = LocalStore.readWork().habitLinks.single;
      expect(link.role, GoalHabitRole.supporting);
      expect(link.habitId, 'habit');
      expect(link.goalId, 'goal');
      expect(LocalStore.readWork().goals.single.current, 0);
      expect(LocalStore.readHabits()['habit']!.completions, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpScreen(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            child: RelatedGoalsSection(habitId: 'habit'),
          ),
        ),
      );
      expect(find.text('Read regularly'), findsWidgets);
      expect(find.text('Supporting'), findsWidgets);
    },
  );

  testWidgets('measured linking previews existing activity before saving', (
    tester,
  ) async {
    await _seed(tester, measured: true);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: GoalHabitLinksSection(goalId: 'goal'),
        ),
      ),
    );
    final goals = tester
        .element(find.byType(GoalHabitLinksSection))
        .read<GoalsController>();
    await tester.tap(find.text('Link habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read daily'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<GoalHabitRole>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measured contribution').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save connection'));
    await tester.pumpAndSettle();
    expect(LocalStore.readWork().habitLinks, isEmpty);
    await tester.tap(find.text('Save connection'));
    await _settleLink(tester);
    expect(goals.progressFor('goal').progress!.value, 1);
    expect(goals.linksForHabit('habit').single.role, GoalHabitRole.contributor);
    await tester.runAsync(() => goals.habits.toggle('habit', AppClock.today()));
    await tester.pumpAndSettle();
    expect(goals.progressFor('goal').progress!.value, 0);
  });

  testWidgets('unlinking removes the relationship but never habit history', (
    tester,
  ) async {
    await _seed(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: GoalHabitLinksSection(goalId: 'goal'),
        ),
      ),
    );
    final goals = tester
        .element(find.byType(GoalHabitLinksSection))
        .read<GoalsController>();
    await tester.runAsync(
      () => goals.saveHabitLink(
        goals.buildHabitLink(goalId: 'goal', habitId: 'habit'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlink habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlink habit'));
    await _settleLink(tester);
    expect(goals.linksForGoal('goal'), isEmpty);
    expect(LocalStore.readWork().habitLinks.single.isDeleted, isTrue);
    expect(LocalStore.readHabits()['habit']!.completions, hasLength(1));
  });

  testWidgets('creating a habit from a goal saves its connection', (
    tester,
  ) async {
    await _seed(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: GoalHabitLinksSection(goalId: 'goal'),
        ),
      ),
    );
    await tester.tap(find.text('Create habit'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'Practice sketching');
    await tester.pump();
    await tester.tap(find.text('Save').first);
    await _settleLink(tester);
    final habit = LocalStore.readHabits().values.singleWhere(
      (habit) => habit.name == 'Practice sketching',
    );
    expect(LocalStore.readWork().habitLinks.single.habitId, habit.id);
    expect(LocalStore.readWork().habitLinks.single.goalId, 'goal');
  });

  testWidgets('habit detail offers related goals in the existing theme', (
    tester,
  ) async {
    await _seed(tester);
    await pumpScreen(tester, const HabitDetailsPage(habitId: 'habit'));
    await tester.scrollUntilVisible(
      find.byType(RelatedGoalsSection),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Link goal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the habit can link to an existing goal directly', (
    tester,
  ) async {
    await _seed(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: RelatedGoalsSection(habitId: 'habit'),
        ),
      ),
    );
    await tester.tap(find.text('Link goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read regularly'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save connection'));
    await _settleLink(tester);
    expect(LocalStore.readWork().habitLinks.single.goalId, 'goal');
    expect(LocalStore.readWork().habitLinks.single.habitId, 'habit');
    expect(find.text('Read regularly'), findsOneWidget);
  });

  for (final style in [0, 1, 2]) {
    testWidgets('habit form saves a selected goal in style $style', (
      tester,
    ) async {
      await _seed(tester);
      await pumpScreen(
        tester,
        const HabitFormPage(relatedGoalId: 'goal'),
        minimal: style == 1,
        settings: {'appStyle': style},
        theme: AppTheme.light(null, style),
        darkTheme: AppTheme.dark(null, style),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'Practice sketching',
      );
      await tester.pump();
      await tester.tap(find.text('Save').first);
      await _settleLink(tester);
      final saved = LocalStore.readHabits().values.singleWhere(
        (habit) => habit.name == 'Practice sketching',
      );
      final link = LocalStore.readWork().habitLinks.single;
      expect(link.habitId, saved.id);
      expect(link.goalId, 'goal');
      expect(link.role, GoalHabitRole.supporting);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('creating a goal from a habit creates a supporting connection', (
    tester,
  ) async {
    await _seed(tester);
    await pumpScreen(
      tester,
      const Scaffold(
        body: SingleChildScrollView(
          child: RelatedGoalsSection(habitId: 'habit'),
        ),
      ),
    );
    await tester.tap(find.text('Create goal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Practice art');
    await tester.pump();
    await tester.ensureVisible(find.text('Save').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await _settleLink(tester);
    final goal = LocalStore.readWork().goals.singleWhere(
      (goal) => goal.title == 'Practice art',
    );
    final link = LocalStore.readWork().habitLinks.single;
    expect(link.goalId, goal.id);
    expect(link.habitId, 'habit');
    expect(link.role, GoalHabitRole.supporting);
    expect(LocalStore.readHabits()['habit']!.completions, hasLength(1));
  });

  for (final measured in [false, true]) {
    testWidgets(
      'a Work task can connect an existing goal (measured: $measured)',
      (tester) async {
        await tester.runAsync(
          () => LocalStore.updateWork(
            (_) => WorkData(
              tasks: [
                WorkTask(
                  meta: RecordMeta(id: 'task', createdAt: DateTime.now()),
                  title: 'Publish the page',
                  status: WorkTaskStatus.done,
                ),
              ],
              goals: [
                Goal(
                  meta: RecordMeta(id: 'goal', createdAt: DateTime.now()),
                  title: 'Build a portfolio',
                  scope: GoalScope.work,
                  source: measured ? GoalSource.work : GoalSource.manual,
                  measurement: measured
                      ? GoalMeasurement.percentage
                      : GoalMeasurement.completion,
                  target: measured ? 100 : 1,
                ),
              ],
            ),
          ),
        );
        await pumpScreen(
          tester,
          const Scaffold(
            body: SingleChildScrollView(
              child: RelatedGoalsSection(taskId: 'task'),
            ),
          ),
        );
        final goals = tester
            .element(find.byType(RelatedGoalsSection))
            .read<GoalsController>();
        await tester.tap(find.text('Link goal'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Build a portfolio'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save').last);
        await _settleLink(tester);
        expect(goals.byId('goal')!.taskIds, ['task']);
        expect(goals.progressFor('goal').progress!.value, measured ? 100 : 0);
        expect(goals.byId('goal')!.status, GoalStatus.notStarted);
      },
    );
  }

  testWidgets(
    'habit form retries a failed goal connection without duplicating the habit',
    (tester) async {
      await _seed(tester);
      await pumpScreen(tester, const HabitFormPage(relatedGoalId: 'goal'));
      await tester.enterText(find.byType(TextField).first, 'Sketch daily');
      await tester.pump();
      // The goal is archived after the form opened, so the habit saves but its
      // connection is rejected.
      await tester.runAsync(
        () => LocalStore.updateWork(
          (data) => data.copyWith(
            goals: [
              data.goals.single.copyWith(
                meta: data.goals.single.meta.revise(
                  at: DateTime.now(),
                  archived: true,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Save').first);
      await _settleLink(tester);
      expect(
        find.textContaining('goal connections were not', skipOffstage: false),
        findsWidgets,
      );
      expect(find.byType(HabitFormPage), findsOneWidget);
      var habits = LocalStore.readHabits().values.where(
        (habit) => habit.name == 'Sketch daily',
      );
      expect(habits, hasLength(1));
      expect(LocalStore.readWork().habitLinks, isEmpty);

      await tester.runAsync(
        () => LocalStore.updateWork(
          (data) => data.copyWith(
            goals: [
              data.goals.single.copyWith(
                meta: data.goals.single.meta.revise(
                  at: DateTime.now(),
                  archived: false,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'Sketch nightly');
      await tester.pump();
      await tester.tap(find.text('Save').first);
      await _settleLink(tester);
      habits = LocalStore.readHabits().values.where(
        (habit) => habit.name.startsWith('Sketch'),
      );
      expect(habits, hasLength(1));
      expect(habits.single.name, 'Sketch nightly');
      final link = LocalStore.readWork().habitLinks.single;
      expect(link.habitId, habits.single.id);
      expect(link.goalId, 'goal');
      expect(link.role, GoalHabitRole.supporting);
      expect(tester.takeException(), isNull);
    },
  );
}
