import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_day_plan.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/services/notification_service.dart';
import 'package:streak/services/reminder_schedule.dart';
import 'package:uuid/uuid.dart';

typedef WorkReminderScheduler = Future<void> Function(WorkData data);

enum WorkPlanningStatus { idle, scheduling, scheduled, failed }

class WorkPlanningController extends ChangeNotifier {
  WorkPlanningController(
    this.work, {
    WorkReminderScheduler? scheduler,
  }) : _scheduler = scheduler ?? NotificationService().rescheduleWork {
    work.addListener(_onWorkChanged);
  }

  final WorkController work;
  final WorkReminderScheduler _scheduler;

  WorkPlanningStatus status = WorkPlanningStatus.idle;
  String? reminderError;
  WorkReminderFailure? reminderFailure;

  bool _disposed = false;
  bool _remindersRunning = false;
  bool _remindersPending = false;
  final _reminderWaiters = <Completer<void>>[];

  static const maxBlockMinutes = 24 * 60;
  static const maxRemindersPerTask = ReminderSchedule.maxWorkRemindersPerTask;

  void _onWorkChanged() {
    unawaited(
      refreshReminders().then<void>((_) {}, onError: _reportAutomaticFailure),
    );
  }

  void reload() {
    work.reload();
  }

  void _reportAutomaticFailure(Object error, StackTrace stack) {
    debugPrint('Automatic Work reminder refresh failed: $error');
    debugPrintStack(stackTrace: stack);
  }

  List<WorkPlanBlock> blocksForTask(String taskId) =>
      work.data.blocks
          .where((block) => block.taskId == taskId && !block.isDeleted)
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  List<WorkPlanBlock> blocksForDay(DateTime day) =>
      WorkPlanProjection.blocksForDay(work.data, day, now: AppClock.wallNow());

  List<WorkDayPlanItem> itemsForDay(DateTime day) =>
      WorkPlanProjection.itemsForDay(work.data, day, now: AppClock.wallNow());

  List<WorkPlanConflict> conflictsForBlock({
    required DateTime startsAt,
    required int minutes,
    String? excludingBlockId,
  }) => WorkPlanProjection.conflictsForBlock(
    data: work.data,
    startsAt: startsAt,
    minutes: minutes,
    excludingBlockId: excludingBlockId,
    habits: LocalStore.readHabits().values,
    now: AppClock.wallNow(),
  );

  bool canEditTask(WorkTask task) =>
      WorkPlanProjection.isTaskEditable(work.data, task);

  Future<WorkPlanBlock> saveBlock({
    required String taskId,
    required DateTime startsAt,
    required int minutes,
    String note = '',
    WorkPlanBlock? existing,
  }) async {
    _validateBlock(startsAt: startsAt, minutes: minutes);
    late WorkPlanBlock saved;
    await LocalStore.updateWork((state) {
      final task = WorkPlanProjection.taskById(state, taskId);
      if (task == null || !WorkPlanProjection.isTaskEditable(state, task)) {
        throw ArgumentError(
          'Unable to plan this task. Reload Work and make sure it is still open.',
        );
      }

      WorkPlanBlock? old;
      if (existing != null) {
        old = _findBlock(state, existing.id);
        if (old == null ||
            old.isDeleted ||
            old.meta.revision != existing.meta.revision ||
            old.taskId != taskId) {
          throw StateError('This plan changed. Reload and try again.');
        }
      }

      saved = WorkPlanBlock(
        meta: old == null ? _newMeta() : _revise(old.meta),
        taskId: taskId,
        startsAt: startsAt,
        minutes: minutes,
        timeZone: _systemTimeZoneFor(startsAt),
        note: note.trim(),
      );
      return state.copyWith(blocks: _put(state.blocks, saved));
    });
    work.reload();
    return saved;
  }

  Future<void> removeBlock(String id, {WorkPlanBlock? existing}) async {
    await LocalStore.updateWork((state) {
      final old = _findBlock(state, id);
      if (old == null || old.isDeleted) {
        throw StateError('This plan changed. Reload and try again.');
      }
      if (existing != null && old.meta.revision != existing.meta.revision) {
        throw StateError('This plan changed. Reload and try again.');
      }
      return state.copyWith(
        blocks: _put(
          state.blocks,
          old.copyWith(meta: _revise(old.meta, deleted: true)),
        ),
      );
    });
    work.reload();
  }

  Future<void> saveReminders(
    WorkTask original,
    List<DateTime> instants,
  ) async {
    final reminders = _sanitizeReminders(original, instants);
    final upcoming = reminders
        .where((instant) => instant.toUtc().isAfter(AppClock.wallNow().toUtc()))
        .length;
    if (upcoming > maxRemindersPerTask) {
      throw ArgumentError('Use 10 or fewer reminders for one task.');
    }
    final saved = await work.saveTask(
      original.copyWith(reminders: reminders),
      expectedRevision: original.meta.revision,
    );
    await refreshReminders();
    if (reminderError != null) {
      debugPrint('Task ${saved.id} saved, but reminders are unavailable.');
    }
  }

  Future<void> refreshReminders() {
    if (_disposed) return Future.value();
    final waiter = Completer<void>();
    _reminderWaiters.add(waiter);
    _remindersPending = true;
    if (!_remindersRunning) {
      _remindersRunning = true;
      scheduleMicrotask(() {
        unawaited(
          _drainReminderRuns().then<void>(
            (_) {},
            onError: _reportAutomaticFailure,
          ),
        );
      });
    }
    return waiter.future;
  }

  Future<void> _drainReminderRuns() async {
    if (_disposed) {
      _completeReminderWaiters();
      _remindersRunning = false;
      return;
    }
    status = WorkPlanningStatus.scheduling;
    _safeNotify();
    var finished = false;
    try {
      while (_remindersPending && !_disposed) {
        _remindersPending = false;
        try {
          await _scheduler(work.data);
          reminderError = null;
          reminderFailure = null;
          status = WorkPlanningStatus.scheduled;
        } on WorkReminderSchedulingException catch (error) {
          reminderFailure = error.failure;
          reminderError = error.failure.name;
          status = WorkPlanningStatus.failed;
        }
        _safeNotify();
      }
      finished = true;
      _completeReminderWaiters();
      _remindersRunning = false;
    } finally {
      if (!finished) {
        status = WorkPlanningStatus.failed;
        reminderFailure = WorkReminderFailure.schedulingFailed;
        reminderError = WorkReminderFailure.schedulingFailed.name;
        _safeNotify();
        _completeReminderWaiters(
          StateError('Work reminder refresh failed unexpectedly.'),
        );
        _remindersRunning = false;
      }
    }
  }

  void _completeReminderWaiters([Object? error, StackTrace? stack]) {
    final waiters = List<Completer<void>>.from(_reminderWaiters);
    _reminderWaiters.clear();
    for (final waiter in waiters) {
      if (waiter.isCompleted) continue;
      if (error == null) {
        waiter.complete();
      } else {
        waiter.completeError(error, stack);
      }
    }
  }

  List<DateTime> _sanitizeReminders(
    WorkTask original,
    List<DateTime> instants,
  ) {
    final now = AppClock.wallNow().toUtc();
    final unique = <String, DateTime>{};
    final existing = original.reminders
        .map((instant) => instant.toUtc().toIso8601String())
        .toSet();
    for (final instant in instants) {
      final utc = instant.toUtc();
      if (!utc.isAfter(now) && !existing.contains(utc.toIso8601String())) {
        throw ArgumentError('Choose a future reminder time.');
      }
      unique[utc.toIso8601String()] = utc;
    }
    final reminders = unique.values.toList()..sort();
    return List.unmodifiable(reminders);
  }

  void _validateBlock({required DateTime startsAt, required int minutes}) {
    if (minutes <= 0 || minutes > maxBlockMinutes) {
      throw ArgumentError('Use a duration from 1 minute to 24 hours.');
    }
    final utc = startsAt.toUtc();
    if (utc.year < 1970 || utc.year > 9999) {
      throw ArgumentError('Choose a valid start time.');
    }
  }

  RecordMeta _newMeta() =>
      RecordMeta(id: const Uuid().v4(), createdAt: AppClock.wallNow().toUtc());

  RecordMeta _revise(RecordMeta meta, {bool? deleted}) {
    final now = AppClock.wallNow().toUtc();
    return meta.revise(
      at: now.isBefore(meta.updatedAt) ? meta.updatedAt : now,
      deleted: deleted,
    );
  }

  WorkPlanBlock? _findBlock(WorkData data, String id) {
    for (final block in data.blocks) {
      if (block.id == id) return block;
    }
    return null;
  }

  List<WorkPlanBlock> _put(List<WorkPlanBlock> blocks, WorkPlanBlock block) => [
    for (final existing in blocks)
      if (existing.id == block.id) block else existing,
    if (!blocks.any((existing) => existing.id == block.id)) block,
  ];

  static String _systemTimeZoneFor(DateTime instant) {
    final local = instant.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absolute = offset.abs();
    final hours = absolute.inHours.toString().padLeft(2, '0');
    final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
    final name = local.timeZoneName.trim();
    return name.isEmpty
        ? 'UTC$sign$hours:$minutes'
        : '$name UTC$sign$hours:$minutes';
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    work.removeListener(_onWorkChanged);
    _completeReminderWaiters();
    super.dispose();
  }
}
