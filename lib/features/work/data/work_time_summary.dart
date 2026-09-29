import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';

class WorkTimeSummary {
  WorkTimeSummary._(List<FocusSession> sessions, this.directSeconds)
    : sessions = List.unmodifiable(sessions);

  final List<FocusSession> sessions;
  final int directSeconds;

  int get totalSeconds =>
      sessions.fold(0, (sum, session) => sum + session.seconds);
  int get childSeconds => totalSeconds - directSeconds;
  int get manualSeconds => sessions
      .where((session) => session.source == FocusEntrySource.manual)
      .fold(0, (sum, session) => sum + session.seconds);
  int get timedSeconds => totalSeconds - manualSeconds;

  int secondsOnDay(DateTime day, {int cutoffHour = 0}) => sessions.fold(
    0,
    (sum, session) => sum + session.secondsOnDay(day, cutoffHour: cutoffHour),
  );

  factory WorkTimeSummary.of(
    Iterable<FocusSession> sessions, {
    String? taskId,
    String? projectId,
    String? areaId,
    bool includeSubtasks = true,
  }) {
    if ([taskId, projectId, areaId].whereType<String>().length > 1) {
      throw ArgumentError('Choose one Work time scope');
    }
    final unique = <String, FocusSession>{};
    var direct = 0;
    for (final session in sessions) {
      if (session.isDeleted) continue;
      final target = session.target;
      if (target.kind != FocusTargetKind.workTask) continue;
      if (taskId != null &&
          target.id != taskId &&
          !(includeSubtasks && target.parentTaskId == taskId)) {
        continue;
      }
      if (projectId != null && target.projectId != projectId) continue;
      if (areaId != null && target.areaId != areaId) continue;
      if (unique.containsKey(session.id)) {
        throw StateError('Duplicate Work time record ${session.id}');
      }
      unique[session.id] = session;
      if (taskId == null || target.id == taskId) direct += session.seconds;
    }
    final sorted = unique.values.toList()
      ..sort((a, b) {
        final time = b.startedAt.compareTo(a.startedAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    return WorkTimeSummary._(sorted, direct);
  }
}
