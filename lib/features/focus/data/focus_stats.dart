import 'package:flutter/foundation.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';

enum FocusRange { week, month, year }

enum FocusStatsFilter { all, habits, work }

@immutable
class FocusStats {
  const FocusStats({
    required this.todaySeconds,
    required this.weekSeconds,
    required this.monthSeconds,
    required this.totalSeconds,
    required this.sessionCount,
    required this.buckets,
    required this.series,
    required this.perHabit,
    required this.rangeCount,
  });

  final int todaySeconds;
  final int weekSeconds;
  final int monthSeconds;
  final int totalSeconds;
  final int sessionCount;
  final List<DateTime> buckets;
  final List<int> series;
  final Map<String, int> perHabit;
  final int rangeCount;

  int get averageSeconds =>
      sessionCount == 0 ? 0 : totalSeconds ~/ sessionCount;

  int get rangeSeconds => series.fold(0, (sum, value) => sum + value);

  int get bestBucket {
    var best = 0;
    for (var i = 1; i < series.length; i++) {
      if (series[i] > series[best]) best = i;
    }
    return best;
  }

  static List<DateTime> _bucketsFor(
    FocusRange range,
    DateTime today,
    int weekStart,
    int offset,
  ) {
    switch (range) {
      case FocusRange.week:
        final first = today
            .startOfWeek(weekStart)
            .add(Duration(days: offset * 7));
        return [for (var i = 0; i < 7; i++) first.add(Duration(days: i))];
      case FocusRange.month:
        final anchor = DateTime(today.year, today.month + offset);
        final days = DateTime(anchor.year, anchor.month + 1, 0).day;
        return [
          for (var i = 1; i <= days; i++)
            DateTime(anchor.year, anchor.month, i),
        ];
      case FocusRange.year:
        final year = today.year + offset;
        return [for (var m = 1; m <= 12; m++) DateTime(year, m)];
    }
  }

  static bool _matches(
    FocusSession session,
    FocusStatsFilter filter,
    String? habitId,
  ) {
    if (session.isDeleted) return false;
    if (habitId != null) {
      return session.target.kind == FocusTargetKind.habit &&
          session.target.id == habitId;
    }
    return switch (filter) {
      FocusStatsFilter.all => true,
      FocusStatsFilter.habits => session.target.kind == FocusTargetKind.habit,
      FocusStatsFilter.work => session.target.kind == FocusTargetKind.workTask,
    };
  }

  static int _secondsInBucket(
    FocusSession session,
    FocusRange range,
    DateTime bucket,
  ) {
    if (range == FocusRange.year) {
      final cutoff = session.isWork ? AppClock.cutoffHour : 0;
      return session.secondsInPeriod(
        DateTime(bucket.year, bucket.month, 1, cutoff),
        DateTime(bucket.year, bucket.month + 1, 1, cutoff),
      );
    }
    return session.secondsOnDay(bucket, cutoffHour: AppClock.cutoffHour);
  }

  static FocusStats compute({
    required List<FocusSession> sessions,
    required FocusRange range,
    required DateTime now,
    required int weekStart,
    String? habitId,
    FocusStatsFilter filter = FocusStatsFilter.all,
    int offset = 0,
  }) {
    final scoped = sessions
        .where((session) => _matches(session, filter, habitId))
        .toList();

    final today = now.atMidnight;
    final weekFrom = today.startOfWeek(weekStart);
    final buckets = _bucketsFor(range, today, weekStart, offset);
    final series = List<int>.filled(buckets.length, 0);
    final perHabit = <String, int>{};

    var rangeCount = 0;
    var todaySeconds = 0;
    var weekSeconds = 0;
    var monthSeconds = 0;
    var totalSeconds = 0;

    for (final session in scoped) {
      totalSeconds += session.seconds;
      todaySeconds += session.secondsOnDay(
        today,
        cutoffHour: AppClock.cutoffHour,
      );
      for (var i = 0; i < 7; i++) {
        weekSeconds += session.secondsOnDay(
          weekFrom.addDays(i),
          cutoffHour: AppClock.cutoffHour,
        );
      }
      final monthDays = DateTime(today.year, today.month + 1, 0).day;
      for (var i = 1; i <= monthDays; i++) {
        monthSeconds += session.secondsOnDay(
          DateTime(today.year, today.month, i),
          cutoffHour: AppClock.cutoffHour,
        );
      }

      var inRange = false;
      for (var i = 0; i < buckets.length; i++) {
        final seconds = _secondsInBucket(session, range, buckets[i]);
        if (seconds == 0) continue;
        inRange = true;
        series[i] += seconds;
      }
      if (inRange) {
        rangeCount++;
        if (session.target.kind == FocusTargetKind.habit) {
          perHabit[session.target.id] =
              (perHabit[session.target.id] ?? 0) + session.seconds;
        } else if (session.target.kind == FocusTargetKind.free) {
          perHabit[''] = (perHabit[''] ?? 0) + session.seconds;
        }
      }
    }

    return FocusStats(
      todaySeconds: todaySeconds,
      weekSeconds: weekSeconds,
      monthSeconds: monthSeconds,
      totalSeconds: totalSeconds,
      sessionCount: scoped.length,
      buckets: buckets,
      series: series,
      perHabit: perHabit,
      rangeCount: rangeCount,
    );
  }
}
