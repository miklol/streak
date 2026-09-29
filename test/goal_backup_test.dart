import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/services/backup_service.dart';
import 'package:streak/services/vault_writer.dart';

import 'support/app_harness.dart';

void main() {
  useEmptyStore();

  test(
    'real backups retain goal pins, ordering, history units, and removed links',
    () async {
      final date = DateTime.utc(2026, 9, 10, 12);
      RecordMeta meta(String id) => RecordMeta(id: id, createdAt: date);
      final goal = Goal(
        meta: meta('goal'),
        title: 'Practice piano',
        measurement: GoalMeasurement.number,
        unit: 'hours',
        current: 2,
        target: 10,
        pinned: true,
        order: 7,
      );
      final entry = WorkEntry(
        meta: meta('entry'),
        entityKind: WorkEntityKind.goal,
        entityId: 'goal',
        kind: WorkEntryKind.progress,
        previousValue: 90,
        value: 120,
        measurementUnit: 'minutes',
        measurementKind: 'number',
        measurementSource: 'manual',
        measurementBaseline: 0,
        measurementTarget: 600,
        text: 'Finished the first piece.',
      );
      final removedLink = GoalHabitLink(
        meta: meta('link').revise(at: date, deleted: true),
        goalId: 'goal',
        habitId: 'habit',
      );
      await LocalStore.writeHabit(testHabit(id: 'habit', name: 'Practice'));
      await LocalStore.updateWork(
        (_) => WorkData(
          goals: [goal],
          entries: [entry],
          habitLinks: [removedLink],
        ),
      );
      final folder = await Directory.systemTemp.createTemp(
        'streak_goal_backup',
      );
      addTearDown(() => folder.deleteSync(recursive: true));

      final path = await BackupService.runAuto(folder: folder.path);
      final backup = BackupService.parse(File(path!).readAsStringSync());
      final readable = File(
        '${folder.path}\\$vaultFolder\\goals.md',
      ).readAsStringSync();
      expect(readable, contains('Finished the first piece.'));
      expect(readable, contains('120.0 minutes'));
      expect(readable, contains('Target at update: 600.0'));
      await LocalStore.wipeEverything();
      await BackupService.restore(backup, replace: true);
      final restored = LocalStore.readWork();
      expect(restored.goals.single.toMap(), goal.toMap());
      expect(restored.entries.single.toMap(), entry.toMap());
      expect(restored.habitLinks.single.toMap(), removedLink.toMap());
      expect(LocalStore.readHabits().keys, ['habit']);
    },
  );
}
