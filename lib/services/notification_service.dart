import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show HiveError;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:streak/core/constants/motivational_quotes.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/utils/amount_format.dart';
import 'package:streak/features/habits/data/completion.dart';
import 'package:streak/features/habits/data/completion_ops.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/data/reminder.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_day_plan.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/services/reminder_schedule.dart';
import 'package:streak/l10n/app_localizations.dart';
import 'package:streak/l10n/app_localizations_en.dart';
import 'package:streak/services/home_widget_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'habit_reminders';
  static const _channelName = 'Habit Reminders';

  static const actionDone = 'habit_done';
  static const actionSnooze = 'habit_snooze';
  static const actionAdd = 'habit_add';
  static const actionWorkSnooze = 'work_snooze';

  static bool takesAmount(Habit habit) =>
      habit.kind == HabitKind.quantitative || habit.effectiveTarget > 1;

  static void Function(String habitId)? onOpenHabit;
  static void Function()? onOpenTodos;
  static void Function(String taskId)? onOpenWorkTask;

  static const _todoPayload = 'todo:';

  String? pendingHabitId;
  String? pendingWorkTaskId;

  bool _ready = false;
  Future<void> _workScheduleTail = Future.value();

  Future<void> _withWorkScheduling(Future<void> Function() action) async {
    final previous = _workScheduleTail;
    final release = Completer<void>();
    _workScheduleTail = release.future;
    await previous;
    try {
      await action();
    } on PlatformException catch (error) {
      throw WorkReminderSchedulingException(
        WorkReminderFailure.schedulingFailed,
        error,
      );
    } on FileSystemException catch (error) {
      throw WorkReminderSchedulingException(
        WorkReminderFailure.schedulingFailed,
        error,
      );
    } on HiveError catch (error) {
      throw WorkReminderSchedulingException(
        WorkReminderFailure.schedulingFailed,
        error,
      );
    } on FormatException catch (error) {
      throw WorkReminderSchedulingException(
        WorkReminderFailure.schedulingFailed,
        error,
      );
    } finally {
      release.complete();
    }
  }

  void _handleResponse(NotificationResponse response) {
    final id = response.payload;
    if (id == null || id.isEmpty) return;
    if (ReminderSchedule.isWorkPayload(id)) {
      final taskId = ReminderSchedule.workTaskIdFromPayload(id);
      if (response.actionId == actionWorkSnooze) {
        WorkNotificationActions.apply(response.actionId!, taskId);
        return;
      }
      final open = onOpenWorkTask;
      if (open == null) {
        pendingWorkTaskId = taskId;
      } else {
        open(taskId);
      }
      return;
    }
    if (id.startsWith(_todoPayload)) {
      onOpenTodos?.call();
      return;
    }
    if (NotificationActions.handles(response.actionId)) {
      NotificationActions.apply(
        response.actionId!,
        id,
        response.input,
        response.id,
      );
      return;
    }
    onOpenHabit?.call(id);
  }

  Future<void> initialize() async {
    if (_ready) return;

    tz.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));

    const android = AndroidInitializationSettings('ic_stat_notify');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const windows = WindowsInitializationSettings(
      appName: 'Streak',
      appUserModelId: 'com.streak.app',
      guid: 'cfb32a7d-9c06-495b-8afa-df8829d33edc',
    );
    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: darwin,
        windows: windows,
      ),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionEntrypoint,
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final payload = launch!.notificationResponse?.payload;
      if (ReminderSchedule.isWorkPayload(payload)) {
        pendingWorkTaskId = ReminderSchedule.workTaskIdFromPayload(payload!);
      } else if (payload?.startsWith(_todoPayload) != true) {
        pendingHabitId = payload;
      }
    }

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Reminders to keep your streaks alive',
              importance: Importance.max,
            ),
          );
    }

    await _repairStore();

    _ready = true;
  }

  Future<void> _repairStore() async {
    try {
      await _plugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('Scheduled notification store unreadable, resetting: $e');
      await _plugin.cancelAll();
    }
  }

  Future<bool> requestNotifications() async {
    try {
      if (await Permission.notification.isGranted) return true;
      return (await Permission.notification.request()).isGranted;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    if (!await requestNotifications()) return false;
    if (Platform.isAndroid) {
      final exact = await Permission.scheduleExactAlarm.status;
      if (!exact.isGranted) {
        final result = await Permission.scheduleExactAlarm.request();
        if (!result.isGranted) return false;
      }
    }
    return true;
  }

  Future<void> scheduleFor(Habit habit) async {
    if (!_ready) {
      try {
        await initialize();
      } catch (e) {
        debugPrint('Reminders unavailable, skipping ${habit.name}: $e');
        return;
      }
    }
    if (habit.isOnVacation) {
      await cancelFor(habit.id);
      return;
    }
    final live = <int>{};
    for (final reminder in habit.reminders) {
      try {
        live.addAll(await _schedule(habit, reminder));
      } catch (e) {
        debugPrint('Scheduling ${habit.name} / ${reminder.id} failed: $e');
      }
    }
    await _cancelExcept(habit.id, live);
  }

  static int get _intervalWindow => Platform.isIOS ? 8 : 24;

  Future<Set<int>> _schedule(Habit habit, Reminder reminder) async {
    final strings = await localizations();
    final body = _bodyFor(habit, reminder, strings);
    if (reminder.isHourly) {
      return _scheduleHourly(habit, reminder, body, strings);
    }
    return reminder.isInterval
        ? _scheduleInterval(habit, reminder, body, strings)
        : _scheduleWeekly(habit, reminder, body, strings);
  }

  Future<AppLocalizations> localizations() async {
    final tag = LocalStore.setting('locale', '').trim();
    for (final candidate in [if (tag.isNotEmpty) tag, 'en']) {
      try {
        return await AppLocalizations.delegate.load(_localeOf(candidate));
      } catch (_) {}
    }
    return AppLocalizationsEn();
  }

  Locale _localeOf(String tag) {
    final parts = tag.split(RegExp('[_-]'));
    return parts.length > 1
        ? Locale(parts.first, parts[1])
        : Locale(parts.first);
  }

  String _bodyFor(Habit habit, Reminder? reminder, AppLocalizations strings) {
    final lang = LocalStore.setting('locale', '') == 'es' ? 'es' : 'en';
    final message = reminder?.message.trim() ?? '';
    final quotesOff = LocalStore.setting('quoteSource', 0) == 3;
    var body = message.isNotEmpty
        ? message
        : (quotesOff ? '' : MotivationalQuotes.random(lang));
    final name = LocalStore.setting('profileName', '').trim();
    if (name.isNotEmpty && body.isNotEmpty) {
      body = (lang == 'es' ? 'Hola $name, ' : 'Hi $name, ') + body;
    }
    final streak = habit.currentStreak;
    if (streak > 0) {
      body = '$body\n${strings.notif_streak('$streak')}';
    }
    return body;
  }

  Future<Set<int>> _scheduleHourly(
    Habit habit,
    Reminder reminder,
    String body,
    AppLocalizations strings,
  ) async {
    final ids = <int>{};
    final slots = ReminderSchedule.hourlySlots(
      hour: reminder.hour,
      minute: reminder.minute,
      everyHours: reminder.everyHours,
    );
    final now = tz.TZDateTime.now(tz.local);

    for (final day in reminder.days) {
      if (!habit.ringsOnWeekday(day)) continue;
      for (var slot = 0; slot < slots.length; slot++) {
        final id = ReminderSchedule.hourlyId(habit.id, reminder.id, day, slot);
        ids.add(id);
        final next = ReminderSchedule.nextWeekly(
          now: now,
          weekday: day,
          hour: slots[slot] ~/ 60,
          minute: slots[slot] % 60,
        );
        await _plugin.zonedSchedule(
          id,
          habit.name,
          body,
          tz.TZDateTime.from(next, tz.local),
          _details(habit, body, strings),
          payload: habit.id,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
    return ids;
  }

  Future<Set<int>> _scheduleWeekly(
    Habit habit,
    Reminder reminder,
    String body,
    AppLocalizations strings,
  ) async {
    final ids = <int>{};
    for (final day in reminder.days) {
      if (!habit.ringsOnWeekday(day)) continue;
      final id = _notificationId(habit.id, reminder.id, day);
      ids.add(id);
      final now = tz.TZDateTime.now(tz.local);
      final next = ReminderSchedule.nextWeekly(
        now: now,
        weekday: day,
        hour: reminder.hour,
        minute: reminder.minute,
      );
      final when = tz.TZDateTime.from(next, tz.local);

      await _plugin.zonedSchedule(
        id,
        habit.name,
        body,
        when,
        _details(habit, body, strings),
        payload: habit.id,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
    return ids;
  }

  Future<Set<int>> _scheduleInterval(
    Habit habit,
    Reminder reminder,
    String body,
    AppLocalizations strings,
  ) async {
    final every = reminder.everyDays;
    final now = tz.TZDateTime.now(tz.local);
    final todayEpoch = DateTime(now.year, now.month, now.day).epochDay;
    final anchor = reminder.anchorEpochDay ?? todayEpoch;

    final phase = ((todayEpoch - anchor) % every + every) % every;
    var first = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminder.hour,
      reminder.minute,
    );
    if (phase != 0) {
      first = first.add(Duration(days: every - phase));
    } else if (first.isBefore(now)) {
      first = first.add(Duration(days: every));
    }

    final ids = <int>{};
    for (var i = 0; i < _intervalWindow; i++) {
      final when = first.add(Duration(days: every * i));
      if (!habit.ringsOnWeekday(when.weekday)) continue;
      final id = _notificationId(habit.id, reminder.id, i);
      ids.add(id);
      await _plugin.zonedSchedule(
        id,
        habit.name,
        body,
        when,
        _details(habit, body, strings),
        payload: habit.id,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
    return ids;
  }

  NotificationDetails _details(
    Habit habit,
    String body,
    AppLocalizations strings,
  ) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Reminders to keep your streaks alive',
      importance: Importance.high,
      priority: Priority.high,
      color: habit.color,
      playSound: true,
      icon: 'ic_stat_notify',
      styleInformation: BigTextStyleInformation(body),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: [
        if (habit.kind != HabitKind.negative)
          AndroidNotificationAction(
            actionDone,
            strings.notif_action_done,
            showsUserInterface: false,
            cancelNotification: true,
          ),
        if (takesAmount(habit))
          AndroidNotificationAction(
            actionAdd,
            strings.notif_action_add,
            showsUserInterface: false,
            cancelNotification: true,
            inputs: [
              AndroidNotificationActionInput(
                label: strings.notif_action_add_hint,
              ),
            ],
          ),
        AndroidNotificationAction(
          actionSnooze,
          strings.notif_action_snooze,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    ),
  );

  Future<void> snooze(Habit habit) async {
    if (!_ready) await initialize();
    final reminder = habit.reminders.isEmpty ? null : habit.reminders.first;
    final strings = await localizations();
    final body = _bodyFor(habit, reminder, strings);
    final minutes = reminder?.snoozeMinutes ?? Reminder.defaultSnoozeMinutes;
    await _plugin.zonedSchedule(
      _snoozeId(habit.id),
      habit.name,
      body,
      tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes)),
      _details(habit, body, strings),
      payload: habit.id,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  static const _focusEndId = -987654;

  Future<void> scheduleFocusEnd({
    required String title,
    required String body,
    required Duration after,
  }) async {
    if (!_ready) await initialize();
    await _plugin.cancel(_focusEndId);
    if (after.inSeconds <= 0) return;
    try {
      await _plugin.zonedSchedule(
        _focusEndId,
        title,
        body,
        tz.TZDateTime.now(tz.local).add(after),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Reminders to keep your streaks alive',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {}
  }

  Future<void> cancelFocusEnd() async {
    try {
      await _plugin.cancel(_focusEndId);
    } catch (_) {}
  }

  int _snoozeId(String habitId) => -(habitId.hashCode.abs() % 1000000) - 1;

  Future<void> confirm(Habit habit, String text, int id) async {
    await _plugin.show(
      id,
      habit.name,
      text,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          onlyAlertOnce: true,
          color: habit.color,
          icon: 'ic_stat_notify',
          timeoutAfter: 4000,
        ),
      ),
      payload: habit.id,
    );
  }

  Future<void> scheduleTodo(Todo todo) async {
    try {
      await _scheduleTodo(todo);
    } catch (e) {
      debugPrint('Scheduling to-do ${todo.id} failed: $e');
    }
  }

  Future<void> _scheduleTodo(Todo todo) async {
    if (!_ready) await initialize();
    final id = ReminderSchedule.todoNotificationId(todo.id);
    await _plugin.cancel(id);

    final at = ReminderSchedule.todoFireAt(
      now: DateTime.now(),
      done: todo.done,
      due: todo.due,
      minutes: todo.minutes,
    );
    if (at == null) return;

    final strings = await localizations();
    await _plugin.zonedSchedule(
      id,
      todo.title,
      todo.body.isEmpty ? strings.todos : todo.body,
      tz.TZDateTime.from(at, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Reminders to keep your streaks alive',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(todo.body),
        ),
      ),
      payload: '$_todoPayload${todo.id}',
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelTodo(String todoId) async {
    try {
      if (!_ready) await initialize();
      await _plugin.cancel(ReminderSchedule.todoNotificationId(todoId));
    } catch (e) {
      debugPrint('Cancelling to-do $todoId failed: $e');
    }
  }

  Future<void> rescheduleTodos(List<Todo> todos) async {
    for (final todo in todos.toList()) {
      await scheduleTodo(todo);
    }
  }

  Future<void> rescheduleWork(WorkData data) =>
      _withWorkScheduling(() => _rescheduleWork(data));

  Future<void> _rescheduleWork(WorkData data) async {
    final snoozes = {
      for (final entry in _workSnoozes().entries)
        if (entry.value.isAfter(DateTime.now().toUtc()) &&
            data.tasks.any(
              (task) =>
                  task.id == entry.key &&
                  WorkPlanProjection.shouldScheduleTask(data, task),
            ))
          entry.key: entry.value,
    };
    await _writeWorkSnoozes(snoozes);
    final allSpecs = ReminderSchedule.workReminderSpecs(
      data,
      now: DateTime.now(),
      snoozes: snoozes,
      maxNotifications:
          data.tasks.length * (ReminderSchedule.maxWorkRemindersPerTask + 1),
    );
    final specs = allSpecs
        .take(ReminderSchedule.maxScheduledWorkReminders)
        .toList();
    if (specs.isNotEmpty && !supportsWorkScheduling) {
      throw const WorkReminderSchedulingException(
        WorkReminderFailure.platformUnsupported,
      );
    }
    if (specs.isEmpty && !supportsWorkScheduling) return;
    if (!_ready) await initialize();
    final live = {for (final spec in specs) spec.id: spec.payload};
    await _cancelWorkExcept(live);
    if (specs.isEmpty) return;
    if (!await _hasWorkPermissions()) {
      await _cancelWorkExcept(const {});
      throw const WorkReminderSchedulingException(
        WorkReminderFailure.permissionDenied,
      );
    }
    final strings = await localizations();
    for (final spec in specs) {
      final localized = spec.copyWith(
        body: spec.body.isEmpty
            ? strings.work_reminder_body_default
            : spec.body,
      );
      await _plugin.zonedSchedule(
        spec.id,
        spec.title,
        localized.body,
        tz.TZDateTime.from(spec.at, tz.local),
        _workDetails(localized, strings),
        payload: spec.payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
    await _cancelWorkExcept(live);
    if (allSpecs.length > specs.length) {
      throw const WorkReminderSchedulingException(
        WorkReminderFailure.capacityLimited,
      );
    }
  }

  Future<void> scheduleWorkSnooze(WorkTask task) =>
      _withWorkScheduling(() async {
        final data = LocalStore.readWork();
        final current = WorkPlanProjection.taskById(data, task.id);
        if (current == null ||
            !WorkPlanProjection.shouldScheduleTask(data, current)) {
          throw StateError('This task no longer accepts reminders');
        }
        final at = DateTime.now().add(const Duration(minutes: 10)).toUtc();
        await _writeWorkSnoozes({..._workSnoozes(), task.id: at});
        await _rescheduleWork(data);
      });

  Future<void> cancelFor(String habitId) async {
    await _cancelExcept(habitId, const {});
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> _cancelExcept(String habitId, Set<int> keep) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if (n.payload == habitId && !keep.contains(n.id)) {
        await _plugin.cancel(n.id);
      }
    }
  }

  Future<void> _cancelWorkExcept(Map<int, String> keep) async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      if ((ReminderSchedule.isWorkPayload(n.payload) ||
              ReminderSchedule.isWorkNotificationId(n.id)) &&
          keep[n.id] != n.payload) {
        await _plugin.cancel(n.id);
      }
    }
  }

  bool get supportsWorkScheduling =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  Future<bool> _hasWorkPermissions() async {
    try {
      if (!(await Permission.notification.status).isGranted) return false;
      if (Platform.isAndroid) {
        return (await Permission.scheduleExactAlarm.status).isGranted;
      }
      return true;
    } on PlatformException {
      return false;
    }
  }

  Map<String, DateTime> _workSnoozes() {
    final raw = LocalStore.settingMap('workReminderSnoozes');
    final result = <String, DateTime>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! String) {
        throw const FormatException('Invalid saved Work snooze');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null) {
        throw const FormatException('Invalid Work snooze timestamp');
      }
      result[entry.key] = parsed.toUtc();
    }
    return result;
  }

  Future<void> _writeWorkSnoozes(Map<String, DateTime> snoozes) =>
      LocalStore.writeSetting(
        'workReminderSnoozes',
        {
          for (final entry in snoozes.entries)
            entry.key: entry.value.toUtc().toIso8601String(),
        },
        flush: true,
      );

  NotificationDetails _workDetails(
    WorkReminderSpec spec,
    AppLocalizations strings,
  ) => NotificationDetails(
    iOS: const DarwinNotificationDetails(),
    macOS: const DarwinNotificationDetails(),
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: strings.work_reminder_section_title,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(spec.body),
      icon: 'ic_stat_notify',
      actions: [
        AndroidNotificationAction(
          actionWorkSnooze,
          strings.work_reminder_snooze,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    ),
  );

  int _notificationId(String habitId, String reminderId, int slot) =>
      ReminderSchedule.notificationId(habitId, reminderId, slot);
}

class WorkNotificationActions {
  const WorkNotificationActions._();

  static bool handles(String? actionId) =>
      actionId == NotificationService.actionWorkSnooze;

  static Future<void> apply(
    String actionId,
    String taskId, {
    bool initializeStore = false,
  }) async {
    if (!handles(actionId)) return;
    try {
      if (initializeStore) await LocalStore.init();
      final data = LocalStore.readWork();
      final task = WorkPlanProjection.taskById(data, taskId);
      if (task == null) {
        debugPrint('Work reminder snooze ignored: task $taskId is missing.');
        return;
      }
      if (!WorkPlanProjection.shouldScheduleTask(data, task)) {
        debugPrint(
          'Work reminder snooze ignored: task $taskId is no longer open.',
        );
        return;
      }
      await NotificationService().scheduleWorkSnooze(task);
    } on WorkReminderSchedulingException catch (e) {
      debugPrint('Work notification action failed: $e');
    } on StateError catch (e) {
      debugPrint('Work notification action failed: $e');
    } on PlatformException catch (e) {
      debugPrint('Work notification action failed: $e');
    } on FileSystemException catch (e) {
      debugPrint('Work notification action failed: $e');
    } on HiveError catch (e) {
      debugPrint('Work notification action failed: $e');
    } on FormatException catch (e) {
      debugPrint('Work notification action failed: $e');
    }
  }
}

class NotificationActions {
  const NotificationActions._();

  static bool handles(String? actionId) =>
      actionId == NotificationService.actionDone ||
      actionId == NotificationService.actionSnooze ||
      actionId == NotificationService.actionAdd;

  static Future<void> apply(
    String actionId,
    String habitId, [
    String? input,
    int? notificationId,
  ]) async {
    try {
      await LocalStore.init();
      AppClock.cutoffHour = LocalStore.setting('dayCutoff', 0);
      await LocalStore.reloadHabits();
      final habits = LocalStore.readHabits();
      final habit = habits[habitId];
      if (habit == null) return;

      if (actionId == NotificationService.actionSnooze) {
        await NotificationService().snooze(habit);
        return;
      }

      final today = AppClock.now().atMidnight;
      final amount = double.tryParse(input?.trim() ?? '');

      final Map<String, Completion> completions;
      if (actionId == NotificationService.actionAdd) {
        if (amount == null || amount <= 0) return;
        completions = CompletionOps.addProgress(habit, today, amount);
      } else if (habit.isCompletedOn(today)) {
        return;
      } else if (habit.blocksManualCheck(today)) {
        return;
      } else if (NotificationService.takesAmount(habit)) {
        completions = CompletionOps.addProgress(
          habit,
          today,
          habit.incrementAmount,
        );
      } else {
        completions = CompletionOps.toggle(habit, today);
      }
      final updated = habit.copyWith(completions: completions);

      if (actionId == NotificationService.actionAdd && notificationId != null) {
        final done = completions[today.dayKey]?.count ?? 0;
        await NotificationService().confirm(
          updated,
          '${formatAmount(done)} / ${formatAmount(updated.effectiveTarget)}',
          notificationId,
        );
      }

      await LocalStore.writeHabit(updated);
      habits[habitId] = updated;
      await HomeWidgetService.sync(habits, renderIcons: false);
    } catch (e) {
      debugPrint('Notification action failed: $e');
    }
  }
}

@pragma('vm:entry-point')
void notificationActionEntrypoint(NotificationResponse response) {
  final payload = response.payload;
  final actionId = response.actionId;
  if (payload == null || payload.isEmpty) return;
  if (ReminderSchedule.isWorkPayload(payload) &&
      WorkNotificationActions.handles(actionId)) {
    WidgetsFlutterBinding.ensureInitialized();
    WorkNotificationActions.apply(
      actionId!,
      ReminderSchedule.workTaskIdFromPayload(payload),
      initializeStore: true,
    );
    return;
  }
  if (!NotificationActions.handles(actionId)) return;
  WidgetsFlutterBinding.ensureInitialized();
  NotificationActions.apply(actionId!, payload, response.input, response.id);
}
