import 'package:provider/provider.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/services/focus_service.dart';

Future<void> applyFocusAction(FocusAction action) async {
  final context = AppNavigator.key.currentContext;
  if (context == null) return;

  final focus = context.read<FocusController>();
  if (!focus.isActive) return;

  final session = await focus.apply(action);
  if (session != null) await applySavedFocusSession(session);
}

Future<void> applySavedFocusSession(FocusSession session) async {
  if (session.target.kind != FocusTargetKind.habit) return;
  final context = AppNavigator.key.currentContext;
  if (context == null || !context.mounted) return;
  final habitId = session.target.id;
  final habits = context.read<HabitsController>();
  final habit = habits.byId(habitId);
  if (habit == null) return;

  final today = AppClock.now();
  if (habit.isTimeAmount) {
    await habits.addProgress(habit.id, today, session.seconds / 60);
    return;
  }

  if (!session.completed || habit.kind != HabitKind.positive) return;
  if (habit.isCompletedOn(today)) return;
  await habits.toggle(habit.id, today, fromFocus: true);
}

Future<void>? _draining;

Future<void> drainFocusActions() {
  final context = AppNavigator.key.currentContext;
  if (context == null || !context.mounted) return Future.value();
  return _draining ??= _drainActions().whenComplete(() => _draining = null);
}

Future<void> _drainActions() async {
  for (final action in await FocusService.drain()) {
    final context = AppNavigator.key.currentContext;
    if (context == null || !context.mounted) return;
    await applyFocusAction(action);
    final after = AppNavigator.key.currentContext;
    if (after == null || !after.mounted) return;
    await after.read<FocusController>().ready;
    await FocusService.ack([action]);
  }
}
