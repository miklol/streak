import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/state/work_planning_controller.dart';
import 'package:streak/services/reminder_schedule.dart';

import 'support/app_harness.dart';

RecordMeta _meta(String id, {DateTime? archivedAt}) => RecordMeta(
  id: id,
  createdAt: DateTime(2026, 9, 9, 8),
  archivedAt: archivedAt,
);

WorkTask _task(
  String id, {
  WorkTaskStatus status = WorkTaskStatus.notStarted,
  List<DateTime> reminders = const [],
  String? areaId,
  String? projectId,
}) => WorkTask(
  meta: _meta(id),
  title: id,
  status: status,
  reminders: reminders,
  areaId: areaId,
  projectId: projectId,
);

void main() {
  useEmptyStore();

  test('work reminder specs are future-only, bounded and disjoint', () {
    final now = DateTime(2026, 9, 9, 9).toUtc();
    final reminders = [
      now.subtract(const Duration(minutes: 1)),
      for (var i = 1; i <= 12; i++) now.add(Duration(minutes: i)),
    ];
    final data = WorkData(tasks: [_task('task', reminders: reminders)]);

    final specs = ReminderSchedule.workReminderSpecs(data, now: now);

    expect(specs, hasLength(ReminderSchedule.maxWorkRemindersPerTask));
    expect(specs.every((spec) => spec.at.isAfter(now)), isTrue);
    expect(specs.map((spec) => spec.id).toSet(), hasLength(specs.length));
    expect(
      specs.every((spec) => spec.id >= ReminderSchedule.workIdBase),
      isTrue,
    );
    expect(
      specs.every((spec) => spec.id >= ReminderSchedule.todoIdBase + 100000000),
      isTrue,
    );
    expect(specs.first.payload, isNot(equals('task')));
    expect(ReminderSchedule.workTaskIdFromPayload(specs.first.payload), 'task');
  });

  test(
    'completed cancelled and inherited inactive tasks are not scheduled',
    () {
      final future = DateTime(2026, 9, 9, 12).toUtc();
      final data = WorkData(
        areas: [
          WorkArea(
            meta: _meta('archived-area', archivedAt: future),
            name: 'Archive',
          ),
        ],
        projects: [
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
          _task('open', reminders: [future]),
          _task('done', status: WorkTaskStatus.done, reminders: [future]),
          _task(
            'cancelled',
            status: WorkTaskStatus.cancelled,
            reminders: [future],
          ),
          _task('area', areaId: 'archived-area', reminders: [future]),
          _task('project', projectId: 'cancelled-project', reminders: [future]),
          _task(
            'done-project-task',
            projectId: 'done-project',
            reminders: [future],
          ),
        ],
      );

      expect(
        ReminderSchedule.workReminderSpecs(
          data,
          now: DateTime(2026, 9, 9, 9).toUtc(),
        ).map((spec) => spec.taskId),
        ['open'],
      );
    },
  );

  test('re-enabled task reminders schedule from the latest graph', () {
    final future = DateTime(2026, 9, 9, 12).toUtc();
    final disabled = WorkData(
      tasks: [
        _task('task', status: WorkTaskStatus.cancelled, reminders: [future]),
      ],
    );
    final enabled = WorkData(
      tasks: [
        _task('task', status: WorkTaskStatus.inProgress, reminders: [future]),
      ],
    );

    expect(
      ReminderSchedule.workReminderSpecs(
        disabled,
        now: DateTime(2026, 9, 9, 9).toUtc(),
      ),
      isEmpty,
    );
    expect(
      ReminderSchedule.workReminderSpecs(
        enabled,
        now: DateTime(2026, 9, 9, 9).toUtc(),
      ).single.taskId,
      'task',
    );
  });

  test('controller saves data even when scheduling is unavailable', () async {
    final work = WorkController(now: () => DateTime(2026, 9, 9, 9));
    final planning = WorkPlanningController(
      work,
      scheduler: (_) async => throw const WorkReminderSchedulingException(
        WorkReminderFailure.permissionDenied,
      ),
    );
    addTearDown(planning.dispose);
    final task = await work.saveTask(_task('task'));

    await planning.saveReminders(task, [DateTime(2099, 9, 9, 12)]);

    expect(LocalStore.readWork().tasks.single.reminders, hasLength(1));
    expect(planning.reminderFailure, WorkReminderFailure.permissionDenied);
    expect(planning.reminderError, WorkReminderFailure.permissionDenied.name);
  });

  test(
    'new past reminders are rejected but existing expired reminders can stay',
    () async {
      final work = WorkController(now: () => DateTime(2026, 9, 9, 9));
      final planning = WorkPlanningController(work, scheduler: (_) async {});
      addTearDown(planning.dispose);
      final expired = DateTime.now().subtract(const Duration(days: 1)).toUtc();
      final task = await work.saveTask(_task('task', reminders: [expired]));

      await expectLater(
        planning.saveReminders(task, [
          expired,
          DateTime.now().subtract(const Duration(minutes: 1)),
        ]),
        throwsArgumentError,
      );

      await planning.saveReminders(task, [
        expired,
        DateTime.now().add(const Duration(hours: 1)),
      ]);
      expect(LocalStore.readWork().tasks.single.reminders, hasLength(2));
    },
  );

  test('snoozes persist in pure specs until the task becomes inactive', () {
    final now = DateTime(2026, 9, 9, 9).toUtc();
    final snooze = now.add(const Duration(minutes: 10));
    final active = WorkData(tasks: [_task('task')]);
    final done = WorkData(
      tasks: [_task('task', status: WorkTaskStatus.done)],
    );

    final specs = ReminderSchedule.workReminderSpecs(
      active,
      now: now,
      snoozes: {'task': snooze},
    );

    expect(specs.single.id, ReminderSchedule.workSnoozeNotificationId('task'));
    expect(specs.single.at, snooze);
    expect(
      ReminderSchedule.workReminderSpecs(
        done,
        now: now,
        snoozes: {'task': snooze},
      ),
      isEmpty,
    );
  });

  test('work and snooze IDs are stable and stay below platform limits', () {
    final at = DateTime(2026, 9, 9, 12).toUtc();
    final workId = ReminderSchedule.workNotificationId('task', at);
    final snoozeId = ReminderSchedule.workSnoozeNotificationId('task');

    expect(workId, ReminderSchedule.workNotificationId('task', at));
    expect(snoozeId, ReminderSchedule.workSnoozeNotificationId('task'));
    expect(workId, isNot(snoozeId));
    expect(workId, lessThan(2147483647));
    expect(snoozeId, lessThan(2147483647));
    expect(ReminderSchedule.isWorkNotificationId(workId), isTrue);
    expect(ReminderSchedule.isWorkNotificationId(snoozeId), isTrue);
  });

  test(
    'reminder refreshes are coalesced and use the latest Work graph',
    () async {
      final work = WorkController(now: () => DateTime(2026, 9, 9, 9));
      final seen = <WorkData>[];
      final gate = Completer<void>();
      final planning = WorkPlanningController(
        work,
        scheduler: (data) async {
          seen.add(data);
          if (seen.length == 1) await gate.future;
        },
      );
      addTearDown(planning.dispose);
      final task = await work.saveTask(_task('task'));
      final first = planning.refreshReminders();
      await Future<void>.delayed(Duration.zero);
      await work.saveTask(
        task.copyWith(status: WorkTaskStatus.done, progress: 1),
        expectedRevision: task.meta.revision,
      );
      final second = planning.refreshReminders();
      gate.complete();
      await Future.wait([first, second]);

      expect(seen.length, greaterThanOrEqualTo(2));
      expect(seen.last.tasks.single.status, WorkTaskStatus.done);
    },
  );
}
