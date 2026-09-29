import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/data/work_time_summary.dart';

final _now = DateTime(2026, 9, 9, 12);
RecordMeta _meta(String id) => RecordMeta(id: id, createdAt: _now);

WorkData _work() => WorkData(
  areas: [WorkArea(meta: _meta('area'), name: 'Studio')],
  projects: [
    WorkProject(meta: _meta('project'), name: 'Launch', areaId: 'area'),
    WorkProject(meta: _meta('other'), name: 'Second project'),
  ],
  tasks: [
    WorkTask(
      meta: _meta('parent'),
      title: 'Build the site',
      projectId: 'project',
    ),
    WorkTask(
      meta: _meta('child'),
      title: 'Write copy',
      projectId: 'project',
      parentTaskId: 'parent',
    ),
    WorkTask(meta: _meta('different'), title: 'Research', projectId: 'other'),
  ],
);

FocusSession _session(
  String id,
  String taskId,
  DateTime start,
  int seconds, {
  FocusEntrySource source = FocusEntrySource.timer,
}) {
  final end = start.add(Duration(seconds: seconds));
  return FocusSession(
    id: id,
    habitId: '',
    target: FocusTarget.fromWork(_work(), taskId),
    targetMinutes: seconds ~/ 60,
    seconds: seconds,
    completed: true,
    startedAt: start,
    endedAt: end,
    source: source,
    spans: [FocusSpan(startedAt: start, endedAt: end)],
  );
}

void main() {
  test(
    'task time distinguishes direct and subtask work without double counting',
    () {
      final records = [
        _session('parent-session', 'parent', _now, 600),
        _session(
          'child-session',
          'child',
          _now.add(const Duration(hours: 1)),
          300,
        ),
        _session(
          'other-session',
          'different',
          _now.add(const Duration(hours: 2)),
          900,
          source: FocusEntrySource.manual,
        ),
        FocusSession(
          id: 'habit',
          habitId: 'reading',
          targetMinutes: 10,
          seconds: 600,
          completed: true,
          startedAt: _now,
        ),
        FocusSession(
          id: 'free',
          habitId: '',
          targetMinutes: 10,
          seconds: 600,
          completed: true,
          startedAt: _now,
        ),
      ];
      final parent = WorkTimeSummary.of(records, taskId: 'parent');
      expect(parent.totalSeconds, 900);
      expect(parent.directSeconds, 600);
      expect(parent.childSeconds, 300);
      expect(
        WorkTimeSummary.of(
          records,
          taskId: 'parent',
          includeSubtasks: false,
        ).totalSeconds,
        600,
      );
      expect(
        WorkTimeSummary.of(records, projectId: 'project').totalSeconds,
        900,
      );
      expect(WorkTimeSummary.of(records, areaId: 'area').totalSeconds, 900);
      final all = WorkTimeSummary.of(records);
      expect(all.totalSeconds, 1800);
      expect(all.manualSeconds, 900);
      expect(all.timedSeconds, 900);
      expect(all.sessions.first.id, 'other-session');
    },
  );

  test('recorded attribution survives a task move and rename', () {
    final record = _session('old', 'child', _now, 600);
    final updated = _work().copyWith(
      tasks: [
        _work().tasks.first,
        _work().tasks[1].copyWith(
          projectId: 'other',
          clearParent: true,
          title: 'New title',
        ),
        _work().tasks.last,
      ],
    );
    expect(updated.tasks[1].projectId, 'other');
    expect(record.target.title, 'Write copy');
    expect(
      WorkTimeSummary.of([record], projectId: 'project').totalSeconds,
      600,
    );
    expect(WorkTimeSummary.of([record], projectId: 'other').totalSeconds, 0);
    expect(WorkTimeSummary.of([record], taskId: 'child').totalSeconds, 600);
  });

  test(
    'Work time is split across midnight and respects the reporting cutoff',
    () {
      final record = _session(
        'midnight',
        'parent',
        DateTime(2026, 9, 9, 23, 50),
        1200,
      );
      final summary = WorkTimeSummary.of([record]);
      expect(summary.secondsOnDay(DateTime(2026, 9, 9)), 600);
      expect(summary.secondsOnDay(DateTime(2026, 9, 10)), 600);
      expect(summary.secondsOnDay(DateTime(2026, 9, 9), cutoffHour: 4), 1200);
      expect(summary.secondsOnDay(DateTime(2026, 9, 10), cutoffHour: 4), 0);
    },
  );

  test('overlapping representations of the same record are rejected', () {
    final record = _session('unique', 'parent', _now, 120);
    expect(() => WorkTimeSummary.of([record, record]), throwsStateError);
    expect(
      () =>
          WorkTimeSummary.of([record], taskId: 'parent', projectId: 'project'),
      throwsArgumentError,
    );
  });
}
