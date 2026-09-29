import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/utils/app_dirs.dart';
import 'package:streak/core/utils/cover_storage.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_progress.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/services/backup_service.dart';
import 'package:streak/services/backup_conflict.dart';
import 'package:streak/services/folder_sync.dart';
import 'package:streak/services/image_cleanup_service.dart';
import 'package:streak/services/vault_writer.dart';

import 'support/app_harness.dart';

final _now = DateTime.utc(2026, 9, 9, 10);
RecordMeta _meta(String id) => RecordMeta(id: id, createdAt: _now);
WorkTask _task(String id, {String? parent, WorkTaskStatus? status}) => WorkTask(
  meta: _meta(id),
  title: id,
  projectId: 'project',
  parentTaskId: parent,
  status: status ?? WorkTaskStatus.notStarted,
);

WorkData _sample() => WorkData(
  areas: [
    WorkArea(
      meta: _meta('area'),
      name: 'Client',
      type: WorkAreaType.client,
      role: 'Designer',
      links: ['https://example.com'],
      coverPath: 'area.jpg',
    ),
  ],
  projects: [
    WorkProject(
      meta: _meta('project'),
      name: 'Website',
      areaId: 'area',
      outcome: 'Publish the new site',
      startDate: '09-09-2026',
      dueDate: '30-09-2026',
      priority: TodoPriority.high,
      coverPath: 'project.jpg',
      tags: ['launch'],
    ),
  ],
  tasks: [
    _task('parent', status: WorkTaskStatus.inProgress),
    _task(
      'done',
      parent: 'parent',
      status: WorkTaskStatus.done,
    ).copyWith(completedAt: _now, photos: ['task.jpg']),
    _task('partial', parent: 'parent').copyWith(
      progressMode: WorkTaskProgress.manual,
      progress: 50,
      description: 'Implement the page',
      completionCriteria: 'Ready to publish',
      dueDate: '20-09-2026',
      dueMinute: 900,
      timeZone: 'Europe/Kyiv',
      estimatedMinutes: 120,
      reminders: [_now.add(const Duration(days: 1))],
    ),
  ],
  goals: [
    Goal(
      meta: _meta('goal'),
      title: 'Launch',
      scope: GoalScope.work,
      areaId: 'area',
      source: GoalSource.work,
      measurement: GoalMeasurement.percentage,
      target: 100,
      projectIds: ['project'],
      photos: ['goal.jpg'],
    ),
    Goal(meta: _meta('personal'), title: 'Learn typography'),
  ],
  habitLinks: [
    GoalHabitLink(meta: _meta('link'), goalId: 'personal', habitId: 'reading'),
  ],
  entries: [
    WorkEntry(
      meta: _meta('entry'),
      entityKind: WorkEntityKind.task,
      entityId: 'partial',
      kind: WorkEntryKind.progress,
      previousValue: 25,
      value: 50,
      text: 'Finished layout',
      photos: ['entry.jpg'],
    ),
  ],
  blocks: [
    WorkPlanBlock(
      meta: _meta('block'),
      taskId: 'partial',
      startsAt: _now,
      minutes: 45,
      timeZone: 'Europe/Kyiv',
    ),
  ],
);

String _encoded(WorkData data) => json.encode(data.toMap());

void main() {
  useEmptyStore();

  test('all Work and Goals fields survive JSON serialization', () {
    final data = _sample();
    final decoded = WorkData.fromMap(
      RecordReader.object(json.decode(_encoded(data))),
    );
    expect(_encoded(decoded), _encoded(data));
    expect(() => data.tasks.clear(), throwsUnsupportedError);
    expect(() => data.tasks.last.reminders.clear(), throwsUnsupportedError);
    expect(() => data.areas.single.workingDays.clear(), throwsUnsupportedError);
  });

  test('schema, enum, dates and nonfinite amounts are rejected', () {
    expect(
      () => WorkData.fromMap({..._sample().toMap(), 'version': 2}),
      throwsFormatException,
    );
    expect(
      () => WorkTask.fromMap({..._task('a').toMap(), 'status': 'unknown'}),
      throwsFormatException,
    );
    expect(
      () => _task('a').copyWith(dueDate: '31-02-2026'),
      throwsArgumentError,
    );
    expect(
      () => _task('a').copyWith(progress: double.nan),
      throwsArgumentError,
    );
    expect(() => _task('a').copyWith(dueMinute: 30), throwsArgumentError);
    expect(
      () => _task('a').copyWith(startDate: '20-09-2026', dueDate: '19-09-2026'),
      throwsArgumentError,
    );
  });

  test('graph rejects duplicate IDs, orphan references and deeper nesting', () {
    final data = _sample();
    expect(
      () => data.copyWith(tasks: [...data.tasks, data.tasks.first]),
      throwsArgumentError,
    );
    expect(() => data.copyWith(projects: []), throwsArgumentError);
    expect(
      () => data.copyWith(
        tasks: [
          ...data.tasks,
          _task('third', parent: 'partial'),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => data.copyWith(
        tasks: [
          data.tasks.first,
          data.tasks[1].copyWith(clearProject: true),
          data.tasks.last,
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => data.copyWith(
        habitLinks: [
          ...data.habitLinks,
          GoalHabitLink(
            meta: _meta('duplicate'),
            goalId: 'personal',
            habitId: 'reading',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('goal links are the same relationship viewed from either end', () {
    final data = _sample();
    expect(
      data.linksForHabit('reading').single.id,
      data.linksForGoal('personal').single.id,
    );
    expect(data.habitLinks.single.role, GoalHabitRole.supporting);
  });

  test(
    'progress counts leaf work once and never infers effort as progress',
    () {
      final data = _sample();
      final progress = data.projectProgress('project');
      expect(progress.total, 2);
      expect(progress.completed, 1);
      expect(progress.fraction, .75);
      expect(
        WorkProgress.of(
          data.tasks,
          taskIds: ['parent', 'partial'],
          projectIds: ['project'],
        ).fraction,
        .75,
      );
      expect(
        data.goalProgress('goal', habits: const {}, asOf: _now).fraction,
        .75,
      );
      expect(
        WorkProgress.of([
          WorkTask(
            meta: _meta('x'),
            title: 'X',
            estimatedMinutes: 120,
            focusMinutes: 120,
          ),
        ]).fraction,
        0,
      );
      expect(WorkProgress.of(const []).fraction, isNull);
    },
  );

  test(
    'archive retains scope; cancellation excludes it without closing parents',
    () {
      final data = _sample();
      final archived = data.tasks.last.copyWith(
        meta: data.tasks.last.meta.revise(at: _now, archived: true),
      );
      expect(
        WorkProgress.of([data.tasks.first, data.tasks[1], archived]).fraction,
        .75,
      );
      final cancelled = archived.copyWith(status: WorkTaskStatus.cancelled);
      expect(
        WorkProgress.of([data.tasks.first, data.tasks[1], cancelled]).fraction,
        1,
      );
      expect(
        () => data.copyWith(
          tasks: [
            data.tasks.first.copyWith(status: WorkTaskStatus.done),
            data.tasks[1],
            data.tasks.last,
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test('inbox tasks and standalone personal goals require no company', () {
    final data = WorkData(
      tasks: [WorkTask(meta: _meta('inbox'), title: 'Capture an idea')],
      goals: [Goal(meta: _meta('personal'), title: 'Learn')],
    );
    expect(data.areas, isEmpty);
    expect(data.projects, isEmpty);
    expect(WorkData.fromMap(data.toMap()).tasks.single.projectId, isNull);
  });

  test(
    'a complete graph survives a cold start and retains image references',
    () async {
      await LocalStore.writeWork(_sample(), expectedRevision: 0);
      final before = _encoded(LocalStore.readWork());
      await coldStart();
      expect(_encoded(LocalStore.readWork()), before);
      expect(
        ImageCleanupService.inUse(),
        containsAll([
          'area.jpg',
          'project.jpg',
          'task.jpg',
          'goal.jpg',
          'entry.jpg',
        ]),
      );
    },
  );

  test(
    'queued changes do not lose updates and stale snapshots are rejected',
    () async {
      final first = LocalStore.updateWork(
        (data) => data.copyWith(
          tasks: [
            ...data.tasks,
            WorkTask(meta: _meta('a'), title: 'A'),
          ],
        ),
      );
      final second = LocalStore.updateWork(
        (data) => data.copyWith(
          tasks: [
            ...data.tasks,
            WorkTask(meta: _meta('b'), title: 'B'),
          ],
        ),
      );
      await first;
      await second;
      expect(LocalStore.readWork().tasks.map((task) => task.id), ['a', 'b']);
      await expectLater(
        LocalStore.writeWork(WorkData(), expectedRevision: 0),
        throwsStateError,
      );
      expect(LocalStore.readWork().tasks, hasLength(2));
    },
  );

  test(
    'failed validation releases the writer and leaves the graph intact',
    () async {
      await LocalStore.writeWork(_sample(), expectedRevision: 0);
      final before = _encoded(LocalStore.readWork());
      await expectLater(
        LocalStore.updateWork((data) => data.copyWith(projects: [])),
        throwsArgumentError,
      );
      expect(_encoded(LocalStore.readWork()), before);
      expect(LocalStore.isWriting, isFalse);
      await LocalStore.updateWork((data) => data);
      expect(_encoded(LocalStore.readWork()), before);
    },
  );

  test('journal recovery completes an interrupted graph change once', () async {
    final pending = _sample().copyWith(revision: 1);
    final box = Hive.box('work');
    await box.put('pending', pending.toMap());
    await box.flush();
    await coldStart();
    expect(_encoded(LocalStore.readWork()), _encoded(pending));
    expect(Hive.box('work').containsKey('pending'), isFalse);
    await Hive.box('work').put('pending', pending.toMap());
    await coldStart();
    expect(LocalStore.readWork().revision, 1);
    expect(Hive.box('work').containsKey('pending'), isFalse);
  });

  test('unknown pending schema is not discarded as empty data', () async {
    await Hive.box('work').put('pending', {'version': 999});
    await expectLater(coldStart(), throwsFormatException);
    expect(Hive.box('work').containsKey('pending'), isTrue);
  });

  test(
    'automatic backup includes a Work-only graph and readable files',
    () async {
      await LocalStore.writeWork(_sample(), expectedRevision: 0);
      final dir = await Directory.systemTemp.createTemp('streak_work_backup');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = await BackupService.runAuto(folder: dir.path);
      final data = BackupService.parse(File(path!).readAsStringSync());
      expect(data.habits, isEmpty);
      expect(_encoded(data.work!), _encoded(LocalStore.readWork()));
      expect(
        File('${dir.path}/$vaultFolder/work.md').readAsStringSync(),
        contains('Website'),
      );
      expect(
        File('${dir.path}/$vaultFolder/goals.md').readAsStringSync(),
        contains('Learn typography'),
      );
      await LocalStore.wipeContent();
      expect(LocalStore.readWork().isEmpty, isTrue);
      await BackupService.restore(data, replace: true);
      expect(LocalStore.readWork().tasks, hasLength(3));
    },
  );

  test(
    'legacy replace restores habits without erasing Work or Goals',
    () async {
      await LocalStore.writeWork(_sample(), expectedRevision: 0);
      final before = _encoded(LocalStore.readWork());
      final data = BackupService.parse(
        json.encode({
          'version': 1,
          'habits': [testHabit(id: 'reading', name: 'Read').toMap()],
        }),
      );
      expect(data.work, isNull);
      await BackupService.restore(data, replace: true);
      expect(_encoded(LocalStore.readWork()), before);
      expect(LocalStore.readHabits().keys, ['reading']);
    },
  );

  test(
    'bad or future Work backups fail before any records are replaced',
    () async {
      await LocalStore.writeWork(_sample(), expectedRevision: 0);
      final before = _encoded(LocalStore.readWork());
      expect(
        () => BackupService.parse(
          json.encode({
            'version': 2,
            'habits': [],
            'work': {'version': 999},
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => BackupService.parse(
          json.encode({
            'version': 999,
            'habits': [],
            'work': _sample().toMap(),
          }),
        ),
        throwsFormatException,
      );
      expect(_encoded(LocalStore.readWork()), before);
    },
  );

  test(
    'repeated merges are idempotent and conflicting records require a choice',
    () async {
      final original = _sample();
      await LocalStore.writeWork(original, expectedRevision: 0);
      final before = _encoded(LocalStore.readWork());
      await LocalStore.updateWork((data) => data.merge(original));
      expect(_encoded(LocalStore.readWork()), before);
      final conflict = original.copyWith(
        tasks: [
          original.tasks.first.copyWith(title: 'A different title'),
          ...original.tasks.skip(1),
        ],
      );
      await expectLater(
        LocalStore.updateWork((data) => data.merge(conflict)),
        throwsA(isA<WorkConflict>()),
      );
      expect(_encoded(LocalStore.readWork()), before);
    },
  );

  test(
    'folder conflicts preserve local Work and do not mark a backup consumed',
    () async {
      final original = _sample();
      await LocalStore.writeWork(original, expectedRevision: 0);
      final dir = await Directory.systemTemp.createTemp('streak_work_sync');
      addTearDown(() => dir.deleteSync(recursive: true));
      await LocalStore.writeSetting('autoBackupFolder', dir.path);
      final conflict = original.copyWith(
        tasks: [
          original.tasks.first.copyWith(title: 'Conflicting title'),
          ...original.tasks.skip(1),
        ],
      );
      await File(
        '${dir.path}/streak_backup_2026-09-09_10-00-00.json',
      ).writeAsString(
        json.encode({
          'version': 2,
          'habits': [],
          'work': conflict.toMap(),
          'exportedAt': _now.toIso8601String(),
        }),
      );
      final before = _encoded(LocalStore.readWork());
      await FolderSync.pull();
      expect(_encoded(LocalStore.readWork()), before);
      expect(LocalStore.setting('folderSeenAt', ''), isEmpty);
      expect(BackupConflict.pendingPayload(dir.path), isNotNull);
      expect(await BackupService.runAuto(folder: dir.path), isNull);
      await File('${dir.path}/streak_backup_2026-09-09_10-00-00.json').delete();
      await File(
        '${dir.path}/streak_backup_2099-01-01_10-00-00.json',
      ).writeAsString(
        json.encode({
          'version': 2,
          'habits': [],
          'work': original.toMap(),
          'exportedAt': DateTime.utc(2099).toIso8601String(),
        }),
      );
      await FolderSync.pull();
      expect(_encoded(LocalStore.readWork()), before);
      expect(LocalStore.setting('folderSeenAt', ''), isEmpty);
      final preserved = BackupService.parse(
        BackupConflict.pendingPayload(dir.path)!,
      );
      expect(preserved.work!.tasks.first.title, 'Conflicting title');
      await BackupService.restore(preserved, replace: true);
      await FolderSync.pull();
      expect(BackupConflict.pendingPayload(dir.path), isNull);
      expect(LocalStore.readWork().tasks.first.title, 'Conflicting title');
    },
  );

  test(
    'habit progress clearing preserves Work; full wipe removes it',
    () async {
      await LocalStore.writeWork(_sample(), expectedRevision: 0);
      final before = _encoded(LocalStore.readWork());
      await LocalStore.clearProgress();
      expect(_encoded(LocalStore.readWork()), before);
      await LocalStore.wipeEverything();
      expect(LocalStore.readWork().isEmpty, isTrue);
    },
  );

  test(
    'explicit null collections and malformed revisions are not defaults',
    () {
      expect(
        () => WorkData.fromMap({..._sample().toMap(), 'tasks': null}),
        throwsFormatException,
      );
      expect(
        () => RecordMeta.fromMap({..._meta('x').toMap(), 'revision': 1.5}),
        throwsFormatException,
      );
      expect(
        () => _meta('x').revise(at: _now.subtract(const Duration(days: 1))),
        throwsArgumentError,
      );
    },
  );

  test(
    'deleting parents requires a consistent subtree and retains history',
    () {
      final data = _sample();
      final deletedParent = data.tasks.first.copyWith(
        meta: data.tasks.first.meta.revise(at: _now, deleted: true),
      );
      expect(
        () => data.copyWith(tasks: [deletedParent, ...data.tasks.skip(1)]),
        throwsArgumentError,
      );
      final deleted = data.copyWith(
        tasks: [
          for (final task in data.tasks)
            task.copyWith(meta: task.meta.revise(at: _now, deleted: true)),
        ],
      );
      expect(deleted.projectProgress('project').fraction, isNull);
      expect(deleted.entries, hasLength(1));
      expect(deleted.photoPaths, contains('task.jpg'));
    },
  );

  test('a cancelled project does not count as active delivery scope', () {
    final data = _sample().copyWith(
      projects: [
        _sample().projects.single.copyWith(status: WorkProjectStatus.cancelled),
      ],
    );
    expect(data.projectProgress('project').fraction, isNull);
  });

  test(
    'a restore conflict precedes writes to existing habit collections',
    () async {
      final original = _sample();
      await LocalStore.writeWork(original, expectedRevision: 0);
      final conflict = original.copyWith(
        tasks: [
          original.tasks.first.copyWith(title: 'Conflicting title'),
          ...original.tasks.skip(1),
        ],
      );
      final incoming = BackupService.parse(
        json.encode({
          'version': 2,
          'habits': [testHabit(id: 'new', name: 'Do not write yet').toMap()],
          'work': conflict.toMap(),
        }),
      );
      await expectLater(
        BackupService.restore(incoming),
        throwsA(isA<WorkConflict>()),
      );
      expect(LocalStore.readHabits(), isEmpty);
      expect(LocalStore.readWork().tasks.first.title, 'parent');
    },
  );

  test(
    'a personal-goals-only backup restores without habits or work tasks',
    () async {
      final data = WorkData(
        goals: [
          Goal(meta: _meta('personal-only'), title: 'Learn something new'),
        ],
      );
      final backup = BackupService.parse(
        json.encode({
          'version': 2,
          'work': data.toMap(),
        }),
      );
      expect(backup.isEmpty, isFalse);
      await BackupService.restore(backup);
      expect(LocalStore.readWork().goals.single.id, 'personal-only');
    },
  );

  test(
    'explicit habit image deletion keeps retained Work references',
    () async {
      final root = await appDataDir();
      final dir = Directory('${root.path}/journey')
        ..createSync(recursive: true);
      final image = File('${dir.path}/shared.jpg')..writeAsBytesSync([1, 2, 3]);
      await LocalStore.writeNote(
        testNote(
          id: 'note',
          habitId: 'habit',
          day: _now,
          text: 'Shared photo',
        ).copyWith(photos: [image.path]),
      );
      final reference = Platform.isWindows
          ? image.path.toUpperCase()
          : image.path;
      await LocalStore.writeWork(
        WorkData(
          tasks: [
            WorkTask(
              meta: _meta('retained').revise(at: _now, deleted: true),
              title: 'Retained task',
              photos: ['$reference?version=1'],
            ),
          ],
        ),
        expectedRevision: 0,
      );
      await HabitsController().clearProgress();
      expect(LocalStore.readNotes(), isEmpty);
      expect(image.existsSync(), isTrue);
      await CoverStorage.sweep(ImageCleanupService.inUse());
      expect(image.existsSync(), isTrue);
      await LocalStore.updateWork((_) => WorkData());
      await CoverStorage.forget(image.path);
      expect(image.existsSync(), isFalse);
    },
  );

  test(
    'new readable files never overwrite pre-existing personal notes',
    () async {
      final dir = await Directory.systemTemp.createTemp('streak_work_vault');
      addTearDown(() => dir.deleteSync(recursive: true));
      final personal = File('${dir.path}/work.md')
        ..writeAsStringSync('# My work notes\n');
      final personalGoals = File('${dir.path}/goals.md')
        ..writeAsStringSync('# Notes about generator: streak\n');
      for (var round = 0; round < 2; round++) {
        await VaultWriter.write(
          dir,
          habits: const [],
          categories: const [],
          notes: const [],
          todos: const [],
          focus: const [],
          work: _sample(),
        );
      }
      expect(personal.readAsStringSync(), '# My work notes\n');
      expect(
        personalGoals.readAsStringSync(),
        '# Notes about generator: streak\n',
      );
      expect(
        File('${dir.path}/work (Streak).md').readAsStringSync(),
        contains('Website'),
      );
      expect(
        File('${dir.path}/goals (Streak).md').readAsStringSync(),
        contains('Learn typography'),
      );
      expect(
        File('${dir.path}/README.md').readAsStringSync(),
        contains('`work (Streak).md`'),
      );
      expect(File('${dir.path}/work (Streak 2).md').existsSync(), isFalse);
    },
  );

  test(
    'unsupported shared-folder data is retained instead of bypassed',
    () async {
      final dir = await Directory.systemTemp.createTemp('streak_future_backup');
      addTearDown(() => dir.deleteSync(recursive: true));
      await LocalStore.writeSetting('autoBackupFolder', dir.path);
      final raw = json.encode({
        'version': 99,
        'habits': [],
        'work': {'version': 99},
      });
      await File(
        '${dir.path}/streak_backup_2099-01-01_10-00-00.json',
      ).writeAsString(raw);
      await FolderSync.pull();
      expect(BackupConflict.pendingPayload(dir.path), raw);
      expect(await BackupService.runAuto(folder: dir.path), isNull);
      expect(LocalStore.setting('folderSeenAt', ''), isEmpty);
    },
  );
}
