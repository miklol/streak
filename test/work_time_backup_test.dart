import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/services/backup_service.dart';
import 'package:streak/services/vault_writer.dart';

import 'support/app_harness.dart';

final _start = DateTime.utc(2026, 9, 9, 10);
WorkData _work() => WorkData(
  tasks: [
    WorkTask(
      meta: RecordMeta(id: 'task', createdAt: _start),
      title: 'Prepare notes',
    ),
  ],
);
FocusSession _session({String note = 'First draft'}) => FocusSession(
  id: 'work-session',
  habitId: '',
  target: FocusTarget.fromWork(_work(), 'task'),
  startedAt: _start,
  endedAt: _start.add(const Duration(minutes: 20)),
  seconds: 1200,
  targetMinutes: 20,
  completed: true,
  spans: [
    FocusSpan(
      startedAt: _start,
      endedAt: _start.add(const Duration(minutes: 20)),
    ),
  ],
  note: note,
);

void main() {
  useEmptyStore();

  test(
    'Work focus snapshots, notes and spans round trip through actual backup',
    () async {
      await LocalStore.writeWork(_work(), expectedRevision: 0);
      await LocalStore.writeFocusSession(_session());
      final dir = await Directory.systemTemp.createTemp(
        'streak_work_time_backup',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = await BackupService.runAuto(folder: dir.path);
      final data = BackupService.parse(File(path!).readAsStringSync());
      expect(data.supportsWorkTime, isTrue);
      expect(data.focus.single.toMap(), _session().toMap());
      final readable = File(
        '${dir.path}/$vaultFolder/focus.md',
      ).readAsStringSync();
      expect(readable, contains('Prepare notes'));
      expect(readable, contains('First draft'));
      await LocalStore.wipeEverything();
      await BackupService.restore(data, replace: true);
      expect(LocalStore.readFocusSessions().single.toMap(), _session().toMap());
    },
  );

  test(
    'legacy replacement has no authority to erase Work time history',
    () async {
      await LocalStore.writeFocusSession(_session());
      final legacy = BackupService.parse(
        jsonEncode({
          'version': 2,
          'habits': [testHabit(id: 'habit', name: 'Restored habit').toMap()],
          'focus': [],
        }),
      );
      await BackupService.restore(legacy, replace: true);
      expect(
        LocalStore.readFocusSessions().single.target.kind,
        FocusTargetKind.workTask,
      );
      expect(LocalStore.readFocusSessions().single.note, 'First draft');
      expect(LocalStore.readHabits().keys, ['habit']);
    },
  );

  test(
    'merging conflicting Work time does not overwrite notes or legacy data',
    () async {
      await LocalStore.writeFocusSession(_session());
      final conflicting = BackupService.parse(
        jsonEncode({
          'version': 3,
          'habits': [testHabit(id: 'new', name: 'Do not write').toMap()],
          'focus': [_session(note: 'Other device').toMap()],
        }),
      );
      await expectLater(
        BackupService.restore(conflicting),
        throwsA(isA<WorkConflict>()),
      );
      expect(LocalStore.readFocusSessions().single.note, 'First draft');
      expect(LocalStore.readHabits(), isEmpty);
    },
  );

  test(
    'malformed typed Work sessions reject the backup rather than disappearing',
    () {
      final bad = _session().toMap();
      bad['spans'] = [{}];
      expect(
        () => BackupService.parse(
          jsonEncode({
            'version': 3,
            'habits': [testHabit(id: 'habit', name: 'Valid habit').toMap()],
            'focus': [bad],
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'deleted Work time is backed up and never silently resurrected by merge',
    () async {
      final original = _session();
      await LocalStore.writeFocusSession(original);
      await LocalStore.removeFocusSessions({original.id});
      expect(LocalStore.readFocusSessions(), isEmpty);
      final deleted = LocalStore.readFocusSessions(includeDeleted: true).single;
      expect(deleted.isDeleted, isTrue);
      final dir = await Directory.systemTemp.createTemp(
        'streak_deleted_work_time',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = await BackupService.runAuto(
        folder: dir.path,
        readable: false,
      );
      final backup = BackupService.parse(File(path!).readAsStringSync());
      expect(backup.focus.single.isDeleted, isTrue);
      expect(
        () => BackupService.mergeFocusSessions([deleted], [original]),
        throwsA(isA<WorkConflict>()),
      );
      await LocalStore.wipeEverything();
      await BackupService.restore(backup, replace: true);
      expect(LocalStore.readFocusSessions(), isEmpty);
      expect(
        LocalStore.readFocusSessions(includeDeleted: true).single.isDeleted,
        isTrue,
      );
    },
  );

  test(
    'different IDs cannot double count an overlapping imported Work interval',
    () {
      final first = _session();
      final second = first.copyWith(id: 'duplicate-interval');
      expect(
        () => BackupService.mergeFocusSessions([first], [second]),
        throwsA(isA<WorkConflict>()),
      );
    },
  );
}
