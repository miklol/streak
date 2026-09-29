import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/features/habits/data/day_plan.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_day_plan.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/state/work_planning_controller.dart';

import 'support/app_harness.dart';

RecordMeta _meta(String id, {DateTime? at, DateTime? archivedAt}) {
  final created = (at ?? DateTime(2026, 9, 9, 8)).toUtc();
  return RecordMeta(id: id, createdAt: created, archivedAt: archivedAt);
}

WorkTask _task(
  String id, {
  String title = 'Write proposal',
  String? areaId,
  String? projectId,
  String? parentTaskId,
  WorkTaskStatus status = WorkTaskStatus.notStarted,
  DateTime? completedAt,
}) => WorkTask(
  meta: _meta(id),
  title: title,
  areaId: areaId,
  projectId: projectId,
  parentTaskId: parentTaskId,
  status: status,
  completedAt: completedAt,
);

void main() {
  useEmptyStore();

  test(
    'unexpected refresh failures reach callers and do not strand future refreshes',
    () async {
      final work = WorkController();
      var fail = true;
      final planning = WorkPlanningController(
        work,
        scheduler: (_) async {
          if (fail) throw StateError('Broken scheduler');
        },
      );
      addTearDown(work.dispose);
      await expectLater(planning.refreshReminders(), throwsStateError);
      expect(planning.status, WorkPlanningStatus.failed);
      fail = false;
      await planning.refreshReminders();
      expect(planning.status, WorkPlanningStatus.scheduled);
      planning.dispose();
      await planning.refreshReminders();
    },
  );

  test('planned block CRUD persists without changing task dates', () async {
    final work = WorkController(now: () => DateTime(2026, 9, 9, 9));
    final planning = WorkPlanningController(
      work,
      scheduler: (_) async {},
    );
    addTearDown(planning.dispose);

    await work.saveTask(_task('task'));
    final block = await planning.saveBlock(
      taskId: 'task',
      startsAt: DateTime(2026, 9, 9, 14),
      minutes: 90,
      note: 'Draft outline',
    );

    expect(block.timeZone, isNotEmpty);
    expect(work.taskById('task')!.dueDate, isNull);
    expect(planning.blocksForTask('task').single.note, 'Draft outline');

    await coldStart();
    work.reload();
    expect(planning.blocksForDay(DateTime(2026, 9, 9)).single.id, block.id);

    final edited = await planning.saveBlock(
      taskId: 'task',
      startsAt: DateTime(2026, 9, 9, 15),
      minutes: 45,
      existing: planning.blocksForTask('task').single,
    );
    expect(edited.meta.revision, block.meta.revision + 1);

    await planning.removeBlock(edited.id, existing: edited);
    expect(planning.blocksForTask('task'), isEmpty);
  });

  test('stale edits and deletes are rejected', () async {
    final work = WorkController(now: () => DateTime(2026, 9, 9, 9));
    final planning = WorkPlanningController(
      work,
      scheduler: (_) async {},
    );
    addTearDown(planning.dispose);
    await work.saveTask(_task('task'));
    final block = await planning.saveBlock(
      taskId: 'task',
      startsAt: DateTime(2026, 9, 9, 10),
      minutes: 30,
    );
    await planning.saveBlock(
      taskId: 'task',
      startsAt: DateTime(2026, 9, 9, 11),
      minutes: 30,
      existing: block,
    );

    await expectLater(
      planning.saveBlock(
        taskId: 'task',
        startsAt: DateTime(2026, 9, 9, 12),
        minutes: 30,
        existing: block,
      ),
      throwsStateError,
    );
    await expectLater(
      planning.removeBlock(block.id, existing: block),
      throwsStateError,
    );
  });

  test('day projection keeps history but hides inactive future work', () async {
    final data = WorkData(
      areas: [
        WorkArea(meta: _meta('area'), name: 'Client'),
        WorkArea(
          meta: _meta('archived-area', archivedAt: DateTime(2026, 9, 8)),
          name: 'Archived',
        ),
      ],
      projects: [
        WorkProject(meta: _meta('project'), name: 'Launch', areaId: 'area'),
        WorkProject(
          meta: _meta('cancelled-project'),
          name: 'Cancelled',
          status: WorkProjectStatus.cancelled,
        ),
        WorkProject(
          meta: _meta('done-project'),
          name: 'Done',
          status: WorkProjectStatus.done,
        ),
      ],
      tasks: [
        _task('open', projectId: 'project'),
        _task(
          'done',
          status: WorkTaskStatus.done,
          completedAt: DateTime(2026, 9, 10, 9).toUtc(),
        ),
        _task('no-completed-at', status: WorkTaskStatus.done),
        _task('cancelled', projectId: 'cancelled-project'),
        _task('done-project-task', projectId: 'done-project'),
        _task('archived', areaId: 'archived-area'),
      ],
      blocks: [
        WorkPlanBlock(
          meta: _meta('midnight'),
          taskId: 'open',
          startsAt: DateTime(2026, 9, 8, 23, 30),
          minutes: 90,
        ),
        WorkPlanBlock(
          meta: _meta('history'),
          taskId: 'done',
          startsAt: DateTime(2026, 9, 9, 8),
          minutes: 30,
        ),
        WorkPlanBlock(
          meta: _meta('future-done'),
          taskId: 'done',
          startsAt: DateTime(2026, 9, 11, 8),
          minutes: 30,
        ),
        WorkPlanBlock(
          meta: _meta('missing-completion-cutoff'),
          taskId: 'no-completed-at',
          startsAt: DateTime(2026, 9, 9, 8),
          minutes: 30,
        ),
        WorkPlanBlock(
          meta: _meta('done-project-block'),
          taskId: 'done-project-task',
          startsAt: DateTime(2026, 9, 9, 8),
          minutes: 30,
        ),
        WorkPlanBlock(
          meta: _meta('cancelled-block'),
          taskId: 'cancelled',
          startsAt: DateTime(2026, 9, 9, 8),
          minutes: 30,
        ),
        WorkPlanBlock(
          meta: _meta('archived-block'),
          taskId: 'archived',
          startsAt: DateTime(2026, 9, 9, 8),
          minutes: 30,
        ),
      ],
    );

    final day = WorkPlanProjection.itemsForDay(
      data,
      DateTime(2026, 9, 9),
      now: DateTime(2026, 9, 12),
    );

    expect(day.map((item) => item.block.id), ['midnight', 'history']);
    expect(day.first.startMinute, 0);
    expect(day.first.endMinute, 60);
    expect(day.first.contextLabel, contains('Launch'));
  });

  test('calendar minutes do not depend on elapsed time since midnight', () {
    final day = DateTime(2026, 3, 29);
    final instant = DateTime(2026, 3, 29, 3, 30);

    expect(WorkPlanProjection.calendarMinuteOfDay(instant, day), 3 * 60 + 30);
  });

  test('work and habit slots merge chronologically without fictional gaps', () {
    final work = WorkData(
      tasks: [_task('task', title: 'Write')],
      blocks: [
        WorkPlanBlock(
          meta: _meta('work'),
          taskId: 'task',
          startsAt: DateTime(2026, 9, 9, 10),
          minutes: 60,
        ),
      ],
    );
    final habit = testHabit(
      id: 'habit',
      name: 'Read',
      startMinute: 9 * 60,
      durationMinutes: 60,
    );

    final plan = DayPlan.of([habit], DateTime(2026, 9, 9), workData: work);

    expect(plan.slots, hasLength(2));
    expect(plan.slots.first.habit?.id, 'habit');
    expect(plan.slots.last.work?.task.id, 'task');
    expect(plan.slots.where((slot) => slot.isGap), isEmpty);
  });

  test('conflicts are warnings across work blocks and habit slots', () {
    final data = WorkData(
      tasks: [
        _task('task'),
        _task('other', title: 'Review'),
      ],
      blocks: [
        WorkPlanBlock(
          meta: _meta('other-block'),
          taskId: 'other',
          startsAt: DateTime(2026, 9, 9, 10),
          minutes: 60,
        ),
      ],
    );
    final habit = testHabit(
      id: 'habit',
      name: 'Exercise',
      startMinute: 10 * 60 + 30,
      durationMinutes: 30,
    );

    final conflicts = WorkPlanProjection.conflictsForBlock(
      data: data,
      startsAt: DateTime(2026, 9, 9, 10, 15),
      minutes: 45,
      habits: [habit],
    );

    expect(conflicts.map((conflict) => conflict.kind), [
      WorkPlanConflictKind.work,
      WorkPlanConflictKind.habit,
    ]);
  });
}
