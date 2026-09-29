import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/services/focus_service.dart';
import 'package:streak/services/notification_service.dart';
import 'package:uuid/uuid.dart';

class FocusTask {
  FocusTask({required this.id, this.title = '', this.done = false});

  final String id;
  String title;
  bool done;
}

class FocusController extends ChangeNotifier {
  FocusController() {
    _sessions = LocalStore.readFocusSessions();
    _restore();
  }

  final ValueNotifier<int> completedTick = ValueNotifier(0);
  final _uuid = const Uuid();
  bool _celebrated = false;
  bool _advancing = false;
  bool _stopping = false;
  Future<void> _phaseTransition = Future.value();
  Future<void> _ready = Future.value();
  Object? _lastPersistenceError;
  Map<String, dynamic>? _pendingActive;
  int _syncGeneration = 0;
  bool _disposed = false;

  Future<void> get ready => _ready;
  Object? get lastPersistenceError => _lastPersistenceError;

  void _restore() {
    final map = LocalStore.settingMap('focusActive');
    if (map.isEmpty) return;
    _habitId = (map['habitId'] ?? '') as String;
    _targetMinutes = ((map['target'] ?? 25) as num).toInt();
    _focusMinutes = ((map['focus'] ?? _targetMinutes) as num).toInt();
    _breakMinutes = ((map['break'] ?? 0) as num).toInt();
    _isBreak = (map['isBreak'] ?? false) as bool;
    _round = ((map['round'] ?? 1) as num).toInt();
    _accumulated = ((map['acc'] ?? 0) as num).toInt();
    _sessionId = (map['sessionId'] ?? '') as String;
    _phaseId = (map['phaseId'] ?? '') as String;
    final repairedIdentity = _sessionId.isEmpty || _phaseId.isEmpty;
    if (_sessionId.isEmpty) _sessionId = _uuid.v4();
    if (_phaseId.isEmpty) _phaseId = _uuid.v4();
    _target = _targetFromActiveMap(map);
    _phaseStartedAt =
        _readTime(map['phaseStartedAt']) ??
        (_readTime(map['since']) ?? DateTime.now().toUtc()).subtract(
          Duration(seconds: _accumulated),
        );
    _spans
      ..clear()
      ..addAll(_readSpans(map['spans']));
    _spanStartedAt = _readTime(map['spanStartedAt']);
    final since = (map['since'] ?? '') as String;
    _since = since.isEmpty ? null : DateTime.tryParse(since)?.toUtc();
    _open = (map['open'] ?? false) as bool;
    if (!_open) return;
    if (_since == null &&
        _accumulated <= 0 &&
        _spans.isEmpty &&
        _target.kind != FocusTargetKind.workTask) {
      _open = false;
      _queueActivePersist();
      return;
    }
    if (_target.kind == FocusTargetKind.workTask &&
        !_isBreak &&
        _since != null &&
        _spanStartedAt == null) {
      _spanStartedAt = _since;
    }
    if (isRunning) _startTicker();
    if (repairedIdentity) _queueActivePersist();
    _sync();
  }

  static DateTime? _readTime(Object? value) =>
      value is String && value.isNotEmpty
      ? DateTime.tryParse(value)?.toUtc()
      : null;

  static List<FocusSpan> _readSpans(Object? value) {
    if (value is! List) return const [];
    final spans = <FocusSpan>[];
    for (final item in value) {
      spans.add(FocusSpan.fromMap(Map<String, dynamic>.from(item as Map)));
    }
    return spans;
  }

  FocusTarget _targetFromActiveMap(Map<String, dynamic> map) {
    if (map.containsKey('focusTarget')) {
      return FocusTarget.fromMap(
        Map<String, dynamic>.from(map['focusTarget'] as Map),
      );
    }
    return _habitId.isEmpty ? FocusTarget.free() : FocusTarget.habit(_habitId);
  }

  Map<String, dynamic> _activeMap({bool? open}) => {
    'habitId': _habitId,
    'target': _targetMinutes,
    'focus': _focusMinutes,
    'break': _breakMinutes,
    'isBreak': _isBreak,
    'round': _round,
    'acc': _accumulated,
    'since': _since?.toIso8601String() ?? '',
    'open': open ?? _open,
    'sessionId': _sessionId,
    'phaseId': _phaseId,
    'focusTarget': _target.toMap(),
    'phaseStartedAt': _phaseStartedAt.toIso8601String(),
    'spanStartedAt': _spanStartedAt?.toIso8601String() ?? '',
    'spans': _spans.map((span) => span.toMap()).toList(),
  };

  Map<String, dynamic> _activeMapFor({
    required bool isBreak,
    required int round,
    required int targetMinutes,
    required int accumulated,
    required DateTime since,
    required String phaseId,
    required DateTime phaseStartedAt,
    required DateTime? spanStartedAt,
    required List<FocusSpan> spans,
  }) => {
    'habitId': _habitId,
    'target': targetMinutes,
    'focus': _focusMinutes,
    'break': _breakMinutes,
    'isBreak': isBreak,
    'round': round,
    'acc': accumulated,
    'since': since.toIso8601String(),
    'open': true,
    'sessionId': _sessionId,
    'phaseId': phaseId,
    'focusTarget': _target.toMap(),
    'phaseStartedAt': phaseStartedAt.toIso8601String(),
    'spanStartedAt': spanStartedAt?.toIso8601String() ?? '',
    'spans': spans.map((span) => span.toMap()).toList(),
  };

  Map<String, dynamic> _inactiveMap() => {
    'habitId': '',
    'target': _focusMinutes,
    'focus': _focusMinutes,
    'break': 0,
    'isBreak': false,
    'round': 1,
    'acc': 0,
    'since': '',
    'open': false,
    'sessionId': _sessionId,
    'phaseId': _phaseId,
    'focusTarget': FocusTarget.free().toMap(),
    'phaseStartedAt': DateTime.now().toUtc().toIso8601String(),
    'spanStartedAt': '',
    'spans': const [],
  };

  void _queueActivePersist() {
    final active = _activeMap();
    _pendingActive = active;
    try {
      final write = LocalStore.writeFocusActive(active);
      _ready = write;
      unawaited(
        write.then<void>(
          (_) {
            if (identical(_pendingActive, active)) {
              _pendingActive = null;
              _lastPersistenceError = null;
            }
          },
          onError: (Object error, StackTrace stack) {
            _lastPersistenceError = error;
            debugPrint('Focus active persistence failed: $error');
            if (!_disposed) notifyListeners();
          },
        ),
      );
    } catch (error, stack) {
      final failed = Completer<void>();
      _ready = failed.future;
      unawaited(
        failed.future.catchError((Object error, StackTrace stack) {
          _lastPersistenceError = error;
          debugPrint('Focus active persistence failed: $error');
          if (!_disposed) notifyListeners();
        }),
      );
      failed.completeError(error, stack);
    }
  }

  Future<void> retryPersistence() async {
    if (_stopping || _advancing) throw StateError('Focus is already saving');
    _stopTicker();
    await LocalStore.recoverFocusTransition();
    final active = _pendingActive;
    if (active != null) await LocalStore.writeFocusActive(active);
    _pendingActive = null;
    _lastPersistenceError = null;
    _ready = Future.value();
    _phaseTransition = Future.value();
    _celebrated = false;
    _sessions = LocalStore.readFocusSessions();
    _restore();
    notifyListeners();
  }

  late List<FocusSession> _sessions;
  final List<FocusTask> _tasks = [];
  final List<FocusSpan> _spans = [];

  String _habitId = '';
  FocusTarget _target = FocusTarget.free();
  String _sessionId = '';
  String _phaseId = '';
  int _targetMinutes = 25;
  int _focusMinutes = 25;
  int _breakMinutes = 0;
  bool _isBreak = false;
  int _round = 1;
  bool _open = false;
  int _accumulated = 0;
  DateTime? _since;
  DateTime _phaseStartedAt = DateTime.now().toUtc();
  DateTime? _spanStartedAt;
  Timer? _ticker;

  List<FocusSession> get sessions => List.unmodifiable(_sessions);

  void reload() {
    _sessions = LocalStore.readFocusSessions();
    if (_open && _pendingActive == null && !_stopping && !_advancing &&
        LocalStore.settingMap('focusActive')['open'] != true) {
      _stopTicker();
      _clearActiveState();
      _sync();
    }
    notifyListeners();
  }

  Future<void> removeSessions(Set<String> ids) async {
    if (ids.isEmpty) return;
    if (_open && ids.contains(_phaseId)) {
      throw StateError('Cannot delete the active focus session');
    }
    await LocalStore.removeFocusSessions(ids);
    _sessions = _sessions.where((s) => !ids.contains(s.id)).toList();
    notifyListeners();
  }

  Future<FocusSession> addSession({
    required String habitId,
    required DateTime startedAt,
    required int minutes,
  }) async {
    final session = FocusSession(
      id: _uuid.v4(),
      habitId: habitId,
      target: habitId.isEmpty ? FocusTarget.free() : FocusTarget.habit(habitId),
      targetMinutes: minutes,
      seconds: minutes * 60,
      completed: true,
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(minutes: minutes)),
      source: FocusEntrySource.manual,
    );
    _sessions.add(session);
    await LocalStore.writeFocusSession(session);
    notifyListeners();
    return session;
  }

  List<FocusTask> get tasks => List.unmodifiable(_tasks);
  int get pendingTasks => _tasks.where((t) => !t.done).length;

  String get habitId => _habitId;
  FocusTarget get target => _target;
  String get sessionId => _sessionId;
  String get phaseId => _phaseId;
  bool get isBreak => _isBreak;
  int get round => _round;
  bool get isPomodoro => _breakMinutes > 0;
  int get targetMinutes => _targetMinutes;
  int get focusMinutes => _focusMinutes;
  int get breakMinutes => _breakMinutes;
  int get targetSeconds => _targetMinutes * 60;

  bool get isActive => _open;
  bool get isRunning => _since != null;

  int elapsedAt(DateTime at) {
    final instant = at.toUtc();
    final live = _since == null ? 0 : instant.difference(_since!).inSeconds;
    final total = _accumulated + live.clamp(0, 1 << 31).toInt();
    return isFlow ? total : total.clamp(0, targetSeconds);
  }

  int get elapsedSeconds => elapsedAt(DateTime.now());

  bool get isFlow => _targetMinutes <= 0;

  int get remainingSeconds =>
      isFlow ? 0 : (targetSeconds - elapsedSeconds).clamp(0, targetSeconds);

  int get displaySeconds => isFlow ? elapsedSeconds : remainingSeconds;

  double get progress => isFlow
      ? (elapsedSeconds % 60) / 60
      : (elapsedSeconds / targetSeconds).clamp(0.0, 1.0);

  bool get reachedTarget => !isFlow && elapsedSeconds >= targetSeconds;

  DateTime get _phaseEnd => _since == null
      ? (_target.kind == FocusTargetKind.workTask && _spans.isNotEmpty
            ? _spans.last.endedAt
            : DateTime.now().toUtc())
      : _since!.add(Duration(seconds: targetSeconds - _accumulated));

  void start({
    required String habitId,
    required int targetMinutes,
    int breakMinutes = 0,
    FocusTarget? target,
  }) {
    if (_open) throw StateError('A focus session is already active');
    if (targetMinutes < 0 || breakMinutes < 0) {
      throw ArgumentError('Focus durations cannot be negative');
    }
    final typed =
        target ??
        (habitId.isEmpty ? FocusTarget.free() : FocusTarget.habit(habitId));
    if (typed.kind == FocusTargetKind.workTask && habitId.isNotEmpty) {
      throw ArgumentError('Work focus cannot also target a habit');
    }
    if (typed.kind == FocusTargetKind.habit &&
        habitId.isNotEmpty &&
        typed.id != habitId) {
      throw ArgumentError('Focus habit mismatch');
    }
    final now = DateTime.now().toUtc();
    _sessionId = _uuid.v4();
    _phaseId = _uuid.v4();
    _habitId = typed.kind == FocusTargetKind.habit ? typed.id : habitId;
    _target = typed;
    _targetMinutes = targetMinutes;
    _focusMinutes = targetMinutes;
    _breakMinutes = targetMinutes <= 0 ? 0 : breakMinutes;
    _isBreak = false;
    _round = 1;
    _open = true;
    _accumulated = 0;
    _tasks.clear();
    _spans.clear();
    _since = now;
    _phaseStartedAt = now;
    _spanStartedAt = typed.kind == FocusTargetKind.workTask ? now : null;
    _celebrated = false;
    _lastPersistenceError = null;
    _startTicker();
    _queueActivePersist();
    _sync();
    notifyListeners();
  }

  void pause({DateTime? at}) {
    if (_advancing || _stopping) return;
    if (_since == null) return;
    final instant = _boundedActionTime(at ?? DateTime.now());
    final spanEnd = _spanEndFor(instant);
    _accumulated = elapsedAt(instant);
    _closeActiveSpan(spanEnd);
    _since = null;
    _stopTicker();
    _queueActivePersist();
    _sync();
    notifyListeners();
  }

  void resume({DateTime? at}) {
    if (_advancing || _stopping) return;
    if (_since != null || !_open) return;
    var instant = (at ?? DateTime.now()).toUtc();
    if (_spans.isNotEmpty && instant.isBefore(_spans.last.endedAt)) {
      instant = _spans.last.endedAt;
    }
    _since = instant;
    if (_target.kind == FocusTargetKind.workTask && !_isBreak) {
      _spanStartedAt = instant;
    }
    _startTicker();
    _queueActivePersist();
    _sync();
    notifyListeners();
  }

  void reset() {
    if (_advancing || _stopping) return;
    final now = DateTime.now().toUtc();
    _accumulated = 0;
    _spans.clear();
    _spanStartedAt =
        isRunning && _target.kind == FocusTargetKind.workTask && !_isBreak
        ? now
        : null;
    _phaseStartedAt = now;
    _since = isRunning ? now : null;
    _celebrated = false;
    if (isRunning) _startTicker();
    _queueActivePersist();
    _sync();
    notifyListeners();
  }

  Future<void> cancelActive() async {
    if (!_open) return;
    try {
      await _phaseTransition;
    } catch (_) {
      // Keep the current in-memory phase available for cancellation.
    }
    if (!_open) return;
    _stopping = true;
    _stopTicker();
    try {
      await LocalStore.commitFocusTransition(active: _inactiveMap());
      _clearActiveState();
      _sync();
      notifyListeners();
    } finally {
      _stopping = false;
    }
  }

  void addTask() {
    _tasks.add(FocusTask(id: DateTime.now().microsecondsSinceEpoch.toString()));
    notifyListeners();
  }

  void setTaskTitle(String id, String title) {
    for (final task in _tasks) {
      if (task.id == id) task.title = title;
    }
  }

  void toggleTask(String id) {
    for (final task in _tasks) {
      if (task.id == id) task.done = !task.done;
    }
    notifyListeners();
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  Future<FocusSession?> apply(FocusAction action) async {
    if (!_open) return null;
    if (_stopping) {
      throw StateError('Focus is already saving; retry the action');
    }
    if (_advancing || action.kind == FocusAction.stop) {
      try {
        await _phaseTransition;
      } catch (_) {
        // A failed transition keeps the old phase active and actionable.
      }
    }
    if (!_matchesAction(action)) return null;
    switch (action.kind) {
      case FocusAction.pause:
        pause(at: action.at);
      case FocusAction.resume:
        resume(at: action.at);
      case FocusAction.stop:
        return stop(completed: reachedTarget || isFlow, at: action.at);
    }
    return null;
  }

  bool _matchesAction(FocusAction action) {
    if (_target.kind == FocusTargetKind.workTask &&
        (action.sessionId.isEmpty || action.phaseId.isEmpty)) {
      return false;
    }
    if (action.at.toUtc().isBefore(_phaseStartedAt)) return false;
    if (action.sessionId.isNotEmpty && action.sessionId != _sessionId) {
      return false;
    }
    if (action.phaseId.isNotEmpty && action.phaseId != _phaseId) return false;
    return true;
  }

  Future<FocusSession?> stop({required bool completed, DateTime? at}) async {
    try {
      await _phaseTransition;
    } catch (_) {
      // The old phase is still in memory when a phase transition fails.
    }
    if (!_open || _stopping) return null;
    _stopping = true;
    final endedAt = _boundedActionTime(at ?? DateTime.now());
    final wasRunning = isRunning;
    _stopTicker();
    try {
      final session = _sessionForCurrentPhase(
        endedAt: endedAt,
        completed: completed,
      );
      await LocalStore.commitFocusTransition(
        session: session,
        active: _inactiveMap(),
      );
      if (session != null && !_sessions.any((item) => item.id == session.id)) {
        _sessions.add(session);
      }
      _clearActiveState();
      _sync();
      notifyListeners();
      return session;
    } catch (e) {
      _lastPersistenceError = e;
      if (wasRunning) _startTicker();
      _sync();
      notifyListeners();
      rethrow;
    } finally {
      _stopping = false;
    }
  }

  FocusSession? _sessionForCurrentPhase({
    required DateTime endedAt,
    required bool completed,
  }) {
    if (_isBreak) return null;
    final work = _target.kind == FocusTargetKind.workTask;
    final cappedEnd = work && !isFlow && endedAt.isAfter(_phaseEnd)
        ? _phaseEnd
        : endedAt;
    final seconds = elapsedAt(cappedEnd);
    if (seconds < (work ? 1 : 30)) return null;
    final spans = work ? _currentSpans(cappedEnd) : const <FocusSpan>[];
    final started = work && spans.isNotEmpty
        ? spans.first.startedAt
        : endedAt.subtract(Duration(seconds: seconds));
    return FocusSession(
      id: _phaseId,
      habitId: work ? '' : _habitId,
      target: _target,
      targetMinutes: _focusMinutes,
      seconds: work
          ? spans.fold(0, (sum, span) => sum + span.seconds)
          : seconds,
      completed: completed,
      startedAt: started,
      endedAt: work ? cappedEnd : endedAt,
      source: FocusEntrySource.timer,
      spans: spans,
    );
  }

  void _clearActiveState() {
    _ready = Future.value();
    _phaseTransition = Future.value();
    _pendingActive = null;
    _lastPersistenceError = null;
    _accumulated = 0;
    _since = null;
    _habitId = '';
    _target = FocusTarget.free();
    _tasks.clear();
    _spans.clear();
    _spanStartedAt = null;
    _celebrated = false;
    _isBreak = false;
    _breakMinutes = 0;
    _round = 1;
    _open = false;
  }

  void _closeActiveSpan(DateTime endedAt) {
    final start = _spanStartedAt;
    if (_target.kind != FocusTargetKind.workTask || _isBreak || start == null) {
      _spanStartedAt = null;
      return;
    }
    if (endedAt.isAfter(start)) {
      _spans.add(FocusSpan(startedAt: start, endedAt: endedAt));
    }
    _spanStartedAt = null;
  }

  DateTime _boundedActionTime(DateTime at) {
    final instant = at.toUtc();
    final since = _since;
    if (since != null && instant.isBefore(since)) return since;
    if (_spans.isNotEmpty && instant.isBefore(_spans.last.endedAt)) {
      return _spans.last.endedAt;
    }
    if (instant.isBefore(_phaseStartedAt)) return _phaseStartedAt;
    return instant;
  }

  DateTime _spanEndFor(DateTime endedAt) {
    if (_target.kind != FocusTargetKind.workTask ||
        _isBreak ||
        isFlow ||
        _since == null) {
      return endedAt;
    }
    final phaseEnd = _since!.add(
      Duration(seconds: targetSeconds - _accumulated),
    );
    return endedAt.isAfter(phaseEnd) ? phaseEnd : endedAt;
  }

  List<FocusSpan> _currentSpans(DateTime endedAt) {
    final result = [..._spans];
    final start = _spanStartedAt;
    if (_target.kind == FocusTargetKind.workTask &&
        !_isBreak &&
        start != null &&
        endedAt.isAfter(start)) {
      result.add(FocusSpan(startedAt: start, endedAt: endedAt));
    }
    result.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return result;
  }

  Future<void> _advancePhase() async {
    if (_advancing || _stopping || !_open) return;
    _advancing = true;
    final operation = _commitAdvancePhase();
    _phaseTransition = operation;
    try {
      await operation;
    } finally {
      _advancing = false;
    }
  }

  Future<void> _commitAdvancePhase() async {
    final endedAt = _phaseEnd;
    try {
      final oldIsBreak = _isBreak;
      final finishedFocus = !oldIsBreak
          ? _sessionForCurrentPhase(endedAt: endedAt, completed: true)
          : null;
      final nextIsBreak = !oldIsBreak;
      final nextRound = oldIsBreak ? _round + 1 : _round;
      final nextTargetMinutes = nextIsBreak ? _breakMinutes : _focusMinutes;
      final nextSince = DateTime.now().toUtc();
      final nextPhaseId = _uuid.v4();
      final nextSpanStartedAt =
          !nextIsBreak && _target.kind == FocusTargetKind.workTask
          ? nextSince
          : null;
      final nextActive = _activeMapFor(
        isBreak: nextIsBreak,
        round: nextRound,
        targetMinutes: nextTargetMinutes,
        accumulated: 0,
        since: nextSince,
        phaseId: nextPhaseId,
        phaseStartedAt: nextSince,
        spanStartedAt: nextSpanStartedAt,
        spans: const [],
      );
      await LocalStore.commitFocusTransition(
        session: finishedFocus,
        active: nextActive,
      );
      _isBreak = nextIsBreak;
      _round = nextRound;
      _targetMinutes = nextTargetMinutes;
      _accumulated = 0;
      _spans.clear();
      _spanStartedAt = nextSpanStartedAt;
      _since = nextSince;
      _phaseStartedAt = nextSince;
      _phaseId = nextPhaseId;
      _celebrated = false;
      _pendingActive = null;
      _lastPersistenceError = null;
      _ready = Future.value();
      if (finishedFocus != null &&
          !_sessions.any((item) => item.id == finishedFocus.id)) {
        _sessions.add(finishedFocus);
      }
      _sync();
      notifyListeners();
    } catch (e) {
      _lastPersistenceError = e;
      debugPrint('Focus phase transition failed: $e');
      _sync();
      notifyListeners();
      rethrow;
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_celebrated && reachedTarget) {
        _celebrated = true;
        completedTick.value++;
        if (isPomodoro) {
          unawaited(_advancePhase().catchError((_) {}));
        } else {
          _stopTicker();
          _sync();
        }
      }
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  int get _anchorMs {
    final since = _since;
    if (since == null) return 0;
    final began = since.millisecondsSinceEpoch - _accumulated * 1000;
    return isFlow ? began : began + targetSeconds * 1000 + 999;
  }

  Future<void> _sync() async {
    final generation = ++_syncGeneration;
    try {
      if (!_open) {
        await FocusService.hide();
        await NotificationService().cancelFocusEnd();
        return;
      }
      final strings = await NotificationService().localizations();
      if (generation != _syncGeneration || !_open || _disposed) return;
      final habit = _habitId.isEmpty ? null : LocalStore.readHabits()[_habitId];
      final done = reachedTarget && !isPomodoro;
      if (isRunning && !isFlow && !done) {
        await NotificationService().scheduleFocusEnd(
          title: strings.focus_done_title,
          body: strings.focus_notif_body,
          after: Duration(seconds: remainingSeconds),
        );
      } else {
        await NotificationService().cancelFocusEnd();
      }
      if (generation != _syncGeneration || !_open || _disposed) return;
      final label = done
          ? strings.focus_target_reached
          : _isBreak
          ? strings.focus_break
          : !isRunning
          ? strings.focus_paused
          : isFlow
          ? strings.focus_flowtime
          : strings.focus_notif_running;
      final phase = done
          ? 'done'
          : _isBreak
          ? 'break'
          : isRunning
          ? 'running'
          : 'paused';
      await FocusService.show(
        habitId: _habitId,
        sessionId: _sessionId,
        phaseId: _phaseId,
        targetKind: _target.kind.name,
        targetId: _target.id,
        title: _target.kind == FocusTargetKind.workTask
            ? _target.title
            : habit?.name ?? strings.focus,
        state: isPomodoro ? '$label  ·  ${strings.focus_round(_round)}' : label,
        phase: phase,
        running: isRunning && !done,
        done: done,
        countDown: !isFlow,
        seconds: displaySeconds,
        anchor: _anchorMs,
        channelName: strings.focus_notif_channel,
        pauseLabel: strings.focus_pause,
        resumeLabel: strings.focus_resume,
        stopLabel: strings.focus_end,
      );
    } catch (e) {
      debugPrint('Focus notification sync failed: $e');
    }
  }

  int get totalSeconds =>
      _sessions.fold(0, (sum, session) => sum + session.seconds);

  int get sessionCount => _sessions.length;

  int secondsForHabit(String habitId) => _sessions
      .where(
        (s) => s.target.kind == FocusTargetKind.habit && s.target.id == habitId,
      )
      .fold(0, (sum, session) => sum + session.seconds);

  int secondsForDay(DateTime day) => _sessions.fold(
    0,
    (sum, session) =>
        sum + session.secondsOnDay(day, cutoffHour: AppClock.cutoffHour),
  );

  int secondsForHabitSince(String habitId, DateTime from) => _sessions
      .where(
        (s) =>
            s.target.kind == FocusTargetKind.habit &&
            s.target.id == habitId &&
            !s.startedAt.toLocal().atMidnight.isBefore(from),
      )
      .fold(0, (sum, session) => sum + session.seconds);

  List<FocusSession> sessionsForHabitOnDay(String habitId, DateTime day) =>
      _sessions
          .where(
            (s) =>
                s.target.kind == FocusTargetKind.habit &&
                s.target.id == habitId &&
                s.startedAt.toLocal().dayKey == day.dayKey,
          )
          .toList();

  int secondsForHabitOnDay(String habitId, DateTime day) =>
      sessionsForHabitOnDay(
        habitId,
        day,
      ).fold(0, (sum, session) => sum + session.seconds);

  Future<FocusSession> saveWorkTime({
    required FocusTarget target,
    required DateTime startedAt,
    required DateTime endedAt,
    String note = '',
    FocusSession? existing,
  }) async {
    final effectiveTarget = existing?.target ?? target;
    if (effectiveTarget.kind != FocusTargetKind.workTask) {
      throw ArgumentError('Manual Work time needs a Work task target');
    }
    final start = startedAt.toUtc();
    final end = endedAt.toUtc();
    final seconds = end.difference(start).inSeconds;
    if (seconds <= 0) throw ArgumentError('Work time must be positive');
    if (end.isAfter(DateTime.now().toUtc())) {
      throw ArgumentError('Work time cannot end in the future');
    }
    final activeSpans = _activeOverlapSpans();
    final session = await LocalStore.writeFocusSessionChecked((current) {
      if (existing == null) {
        _validateNewManualWorkTarget(effectiveTarget, LocalStore.readWork());
      }
      if (existing != null) {
        final matches = current
            .where((item) => item.id == existing.id && !item.isDeleted)
            .toList();
        if (matches.isEmpty) throw StateError('Focus session is missing');
        if (matches.single.revision != existing.revision) {
          throw StateError('Focus session changed; reload before editing');
        }

        if (matches.single.target.kind != FocusTargetKind.workTask) {
          throw ArgumentError('Only Work focus records can be corrected here');
        }
      }
      if (focusIntervalOverlapsSessions(
        startedAt: start,
        endedAt: end,
        sessions: current,
        ignoreId: existing?.id,
      )) {
        throw StateError('Work time overlaps an existing focus session');
      }
      for (final span in activeSpans) {
        if (start.isBefore(span.endedAt) && end.isAfter(span.startedAt)) {
          throw StateError('Work time overlaps the active focus session');
        }
      }
      return FocusSession(
        id: existing?.id ?? _uuid.v4(),
        habitId: '',
        target: effectiveTarget,
        targetMinutes: (seconds / 60).ceil(),
        seconds: seconds,
        completed: true,
        startedAt: start,
        endedAt: end,
        note: note.trim(),
        source: FocusEntrySource.manual,
        revision: (existing?.revision ?? 0) + 1,
        spans: [FocusSpan(startedAt: start, endedAt: end)],
      );
    });
    _upsertSession(session);
    notifyListeners();
    return session;
  }

  void _validateNewManualWorkTarget(FocusTarget target, WorkData work) {
    WorkTask? task;
    for (final item in work.tasks) {
      if (item.id == target.id) task = item;
    }
    if (task == null || task.isDeleted || task.isArchived) {
      throw StateError('Work task changed; reload before adding time');
    }
    if (task.status == WorkTaskStatus.cancelled) {
      throw StateError('Work task is closed');
    }
    final currentTarget = FocusTarget.fromWork(work, task.id);
    if (!_sameTargetSnapshot(currentTarget, target)) {
      throw StateError('Work task context changed; reload before adding time');
    }

    WorkTask? parent;
    for (final item in work.tasks) {
      if (item.id == task.parentTaskId) parent = item;
    }
    if (parent != null &&
        (parent.isDeleted ||
            parent.isArchived ||
            parent.status == WorkTaskStatus.cancelled)) {
      throw StateError('Work task parent is unavailable');
    }

    WorkProject? project;
    for (final item in work.projects) {
      if (item.id == task.projectId) project = item;
    }
    if (project != null &&
        (project.isDeleted ||
            project.isArchived ||
            project.status == WorkProjectStatus.cancelled)) {
      throw StateError('Work project is unavailable');
    }
    final areaId = project?.areaId ?? task.areaId;
    for (final area in work.areas) {
      if (area.id == areaId && (area.isDeleted || area.isArchived)) {
        throw StateError('Work area is unavailable');
      }
    }
  }

  bool _sameTargetSnapshot(FocusTarget a, FocusTarget b) {
    final aMap = a.toMap();
    final bMap = b.toMap();
    if (aMap.length != bMap.length) return false;
    for (final entry in aMap.entries) {
      if (bMap[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> updateWorkNote(FocusSession session, String note) async {
    final updated = await LocalStore.writeFocusSessionChecked((current) {
      final matches = current
          .where((item) => item.id == session.id && !item.isDeleted)
          .toList();
      if (matches.isEmpty) throw StateError('Focus session is missing');
      if (matches.single.revision != session.revision) {
        throw StateError('Focus session changed; reload before editing');
      }
      if (matches.single.target.kind != FocusTargetKind.workTask) {
        throw ArgumentError('Only Work focus records have Work notes');
      }
      return matches.single.copyWith(
        note: note.trim(),
        revision: matches.single.revision + 1,
      );
    });
    _upsertSession(updated);
    notifyListeners();
  }

  void _upsertSession(FocusSession session) {
    _sessions = [
      for (final item in _sessions)
        if (item.id == session.id) session else item,
      if (!_sessions.any((item) => item.id == session.id)) session,
    ];
  }

  List<FocusSpan> _activeOverlapSpans() {
    if (!_open) return const [];
    if (_open) {
      final now = DateTime.now().toUtc();
      final end = !isFlow && now.isAfter(_phaseEnd) ? _phaseEnd : now;
      if (!end.isAfter(_phaseStartedAt)) return const [];
      return _target.kind == FocusTargetKind.workTask
          ? _currentSpans(end)
          : [
              FocusSpan(
                startedAt: _phaseStartedAt,
                endedAt: end,
              ),
            ];
    }
    return const [];
  }

  Future<void> removeForHabit(String habitId) async {
    _sessions.removeWhere(
      (s) => s.target.kind == FocusTargetKind.habit && s.target.id == habitId,
    );
    await LocalStore.removeFocusFor(habitId);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    super.dispose();
  }
}
