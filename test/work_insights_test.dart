import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_insights.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';

final _now = DateTime(2026, 9, 10, 12);
RecordMeta _meta(String id) => RecordMeta(id: id, createdAt: _now);

void main() {
  test('goal measurement history keeps its original units and target', () {
    final entry = WorkEntry(
      meta: _meta('progress'),
      entityKind: WorkEntityKind.goal,
      entityId: 'goal',
      kind: WorkEntryKind.progress,
      previousValue: 5,
      value: 12,
      measurementUnit: 'pages',
      measurementKind: 'number',
      measurementSource: 'manual',
      measurementBaseline: 0,
      measurementTarget: 100,
    );
    final restored = WorkEntry.fromMap(entry.toMap()).copyWith(text: 'A note');
    expect(restored.measurementUnit, 'pages');
    expect(restored.measurementTarget, 100);
    expect(restored.measurementKind, 'number');
    expect(restored.measurementSource, 'manual');
    expect(restored.previousValue, 5);
  });

  test('archived parent tasks do not create open work in insights', () {
    final data = WorkData(
      tasks: [
        WorkTask(
          meta: _meta('parent').revise(at: _now, archived: true),
          title: 'Finished',
        ),
        WorkTask(
          meta: _meta('child'),
          title: 'Hidden work',
          parentTaskId: 'parent',
        ),
      ],
    );
    final result = WorkInsights.compute(
      data: data,
      sessions: [],
      from: DateTime(2026, 9, 1),
      until: DateTime(2026, 9, 11),
      now: _now,
    );
    expect(result.openTasks, 0);
  });

  test('insights separate effort, leaf delivery, and the current workload', () {
    final data = WorkData(
      areas: [WorkArea(meta: _meta('area'), name: 'Studio')],
      projects: [
        WorkProject(meta: _meta('project'), name: 'Launch', areaId: 'area'),
      ],
      tasks: [
        WorkTask(
          meta: _meta('parent'),
          title: 'Build',
          projectId: 'project',
          status: WorkTaskStatus.done,
          completedAt: _now,
        ),
        WorkTask(
          meta: _meta('child'),
          title: 'Write',
          projectId: 'project',
          parentTaskId: 'parent',
          status: WorkTaskStatus.done,
          completedAt: _now,
        ),
        WorkTask(
          meta: _meta('blocked'),
          title: 'Waiting',
          status: WorkTaskStatus.blocked,
          dueDate: '09-09-2026',
        ),
        WorkTask(
          meta: _meta('archived').revise(at: _now, archived: true),
          title: 'Hidden',
          dueDate: '09-09-2026',
        ),
      ],
    );
    final start = _now.subtract(const Duration(minutes: 30));
    final session = FocusSession(
      id: 'time',
      habitId: '',
      target: FocusTarget.fromWork(data, 'child'),
      targetMinutes: 30,
      seconds: 1800,
      completed: true,
      startedAt: start,
      endedAt: _now,
      spans: [FocusSpan(startedAt: start, endedAt: _now)],
      source: FocusEntrySource.manual,
    );
    final insights = WorkInsights.compute(
      data: data,
      sessions: [session],
      from: DateTime(2026, 9, 4),
      until: DateTime(2026, 9, 11),
      now: _now,
    );
    expect(insights.seconds, 1800);
    expect(insights.manualSeconds, 1800);
    expect(insights.completedTasks, 1);
    expect(insights.openTasks, 1);
    expect(insights.blockedTasks, 1);
    expect(insights.overdueTasks, 1);
    expect(insights.projectSeconds, {'project': 1800});
    expect(insights.dailySeconds['10-09-2026'], 1800);
  });

  test('reopening work does not erase the recorded completion event', () {
    final data = WorkData(
      tasks: [WorkTask(meta: _meta('task'), title: 'Reopened')],
      entries: [
        WorkEntry(
          meta: _meta('event'),
          entityKind: WorkEntityKind.task,
          entityId: 'task',
          kind: WorkEntryKind.statusChange,
          previousStatus: WorkTaskStatus.inProgress.name,
          status: WorkTaskStatus.done.name,
        ),
      ],
    );
    final result = WorkInsights.compute(
      data: data,
      sessions: [],
      from: DateTime(2026, 9, 1),
      until: DateTime(2026, 9, 11),
      now: _now,
    );
    expect(result.completedTasks, 1);
    expect(result.openTasks, 1);
  });

  test(
    'time allocation retains the original project snapshot across moves',
    () {
      final original = WorkData(
        projects: [WorkProject(meta: _meta('project'), name: 'Old project')],
        tasks: [
          WorkTask(meta: _meta('task'), title: 'Task', projectId: 'project'),
        ],
      );
      final start = DateTime(2026, 9, 9, 23, 50);
      final end = DateTime(2026, 9, 10, 0, 10);
      final session = FocusSession(
        id: 'time',
        habitId: '',
        target: FocusTarget.fromWork(original, 'task'),
        targetMinutes: 20,
        seconds: 1200,
        completed: true,
        startedAt: start,
        endedAt: end,
        spans: [FocusSpan(startedAt: start, endedAt: end)],
      );
      final changed = original.copyWith(
        tasks: [
          original.tasks.single.copyWith(clearProject: true),
        ],
      );
      final result = WorkInsights.compute(
        data: changed,
        sessions: [session],
        from: DateTime(2026, 9, 10),
        until: DateTime(2026, 9, 11),
        now: _now,
      );
      expect(result.seconds, 600);
      expect(result.projectSeconds, {'project': 600});
      expect(result.projectTitles, {'project': 'Old project'});
    },
  );

  test('cancelled work and its subtasks never count as open or overdue', () {
    final data = WorkData(
      projects: [
        WorkProject(
          meta: _meta('dropped'),
          name: 'Dropped',
          status: WorkProjectStatus.cancelled,
        ),
      ],
      tasks: [
        WorkTask(
          meta: _meta('cancelled'),
          title: 'Abandoned',
          status: WorkTaskStatus.cancelled,
          dueDate: '01-09-2026',
        ),
        WorkTask(
          meta: _meta('orphan'),
          title: 'Under a cancelled parent',
          parentTaskId: 'cancelled',
          dueDate: '01-09-2026',
        ),
        WorkTask(
          meta: _meta('in-dropped'),
          title: 'Inside a cancelled project',
          projectId: 'dropped',
          dueDate: '01-09-2026',
        ),
        WorkTask(
          meta: _meta('live'),
          title: 'Still open',
          dueDate: '01-09-2026',
        ),
      ],
    );
    final result = WorkInsights.compute(
      data: data,
      sessions: [],
      from: DateTime(2026, 9, 1),
      until: DateTime(2026, 9, 11),
      now: _now,
    );
    expect(result.openTasks, 1);
    expect(result.overdueTasks, 1);
    expect(result.completedTasks, 0);
  });

  test('insights reject empty, inverted, and multi-year windows', () {
    WorkInsights compute(DateTime from, DateTime until) => WorkInsights.compute(
      data: WorkData(),
      sessions: [],
      from: from,
      until: until,
      now: _now,
    );
    expect(
      () => compute(DateTime(2026, 9, 10), DateTime(2026, 9, 10)),
      throwsArgumentError,
    );
    expect(
      () => compute(DateTime(2026, 9, 11), DateTime(2026, 9, 10)),
      throwsArgumentError,
    );
    expect(
      () => compute(DateTime(2025, 9, 1), DateTime(2026, 9, 11)),
      throwsArgumentError,
    );
    expect(
      compute(DateTime(2025, 9, 10), DateTime(2026, 9, 10)).dailySeconds,
      hasLength(365),
    );
  });

  test('duplicate time records are rejected instead of double counted', () {
    final data = WorkData(
      tasks: [WorkTask(meta: _meta('task'), title: 'Task')],
    );
    final start = _now.subtract(const Duration(minutes: 10));
    FocusSession session() => FocusSession(
      id: 'same',
      habitId: '',
      target: FocusTarget.fromWork(data, 'task'),
      targetMinutes: 10,
      seconds: 600,
      completed: true,
      startedAt: start,
      endedAt: _now,
      spans: [FocusSpan(startedAt: start, endedAt: _now)],
    );
    expect(
      () => WorkInsights.compute(
        data: data,
        sessions: [session(), session()],
        from: DateTime(2026, 9, 1),
        until: DateTime(2026, 9, 11),
        now: _now,
      ),
      throwsStateError,
    );
  });
}
