import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_stats.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';

final _now = DateTime(2026, 9, 10, 12);
final _start = DateTime(2026, 9, 9, 23, 50);

WorkData _work() => WorkData(
  tasks: [
    WorkTask(
      meta: RecordMeta(id: 'task', createdAt: DateTime.utc(2026, 9, 1)),
      title: 'Design release',
    ),
  ],
);

FocusSession _workSession() => FocusSession(
  id: 'work',
  habitId: '',
  target: FocusTarget.fromWork(_work(), 'task'),
  targetMinutes: 20,
  seconds: 1200,
  completed: true,
  startedAt: _start,
  endedAt: _start.add(const Duration(minutes: 20)),
  spans: [
    FocusSpan(
      startedAt: _start,
      endedAt: _start.add(const Duration(minutes: 20)),
    ),
  ],
);

FocusSession _habitSession() => FocusSession(
  id: 'habit',
  habitId: 'read',
  targetMinutes: 30,
  seconds: 1800,
  completed: true,
  startedAt: _now,
);

void main() {
  test('Work stats split spans by day and filter away habit time', () {
    final stats = FocusStats.compute(
      sessions: [_workSession(), _habitSession()],
      range: FocusRange.week,
      now: _now,
      weekStart: DateTime.monday,
      filter: FocusStatsFilter.work,
    );

    expect(stats.totalSeconds, 1200);
    expect(stats.todaySeconds, 600);
    expect(stats.weekSeconds, 1200);
    expect(stats.sessionCount, 1);
    expect(stats.perHabit, isEmpty);
  });

  test('habit filters do not bucket Work into free focus', () {
    final stats = FocusStats.compute(
      sessions: [_workSession(), _habitSession()],
      range: FocusRange.week,
      now: _now,
      weekStart: DateTime.monday,
      filter: FocusStatsFilter.all,
    );

    expect(stats.totalSeconds, 3000);
    expect(stats.perHabit['read'], 1800);
    expect(stats.perHabit.containsKey(''), isFalse);
  });

  test('cutoff keeps a cross-midnight Work session on the prior day', () {
    final session = _workSession();
    expect(session.secondsOnDay(DateTime(2026, 9, 9), cutoffHour: 4), 1200);
    expect(session.secondsOnDay(DateTime(2026, 9, 10), cutoffHour: 4), 0);
  });
}
