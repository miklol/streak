import 'package:streak/core/data/record.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/focus/data/focus_target.dart';

enum FocusEntrySource { timer, manual }

const focusSessionSchemaVersion = 2;

class FocusSpan {
  FocusSpan({required DateTime startedAt, required DateTime endedAt})
    : startedAt = startedAt.toUtc(),
      endedAt = endedAt.toUtc() {
    if (this.endedAt.isBefore(this.startedAt)) {
      throw ArgumentError('Focus span cannot end before it starts');
    }
  }

  final DateTime startedAt;
  final DateTime endedAt;

  int get seconds => endedAt.difference(startedAt).inSeconds;

  Map<String, dynamic> toMap() => {
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
  };

  factory FocusSpan.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return FocusSpan(
      startedAt: read.timestamp('startedAt'),
      endedAt: read.timestamp('endedAt'),
    );
  }
}

List<FocusSpan> focusSessionIntervals(FocusSession session) {
  if (session.spans.isNotEmpty) return session.spans;
  final end = session.effectiveEndedAt;
  if (!end.isAfter(session.startedAt)) return const [];
  return [FocusSpan(startedAt: session.startedAt, endedAt: end)];
}

bool focusIntervalOverlapsSessions({
  required DateTime startedAt,
  required DateTime endedAt,
  required Iterable<FocusSession> sessions,
  String? ignoreId,
}) {
  final start = startedAt.toUtc();
  final end = endedAt.toUtc();
  if (!end.isAfter(start)) {
    throw ArgumentError('Focus interval must be positive');
  }
  bool overlaps(DateTime otherStart, DateTime otherEnd) =>
      start.isBefore(otherEnd) && end.isAfter(otherStart);
  for (final session in sessions) {
    if (session.isDeleted) continue;
    if (session.id == ignoreId) continue;
    for (final span in focusSessionIntervals(session)) {
      if (overlaps(span.startedAt, span.endedAt)) return true;
    }
  }
  return false;
}

class FocusSession {
  FocusSession({
    required this.id,
    required this.habitId,
    required this.targetMinutes,
    required this.seconds,
    required this.completed,
    required DateTime startedAt,
    FocusTarget? target,
    DateTime? endedAt,
    this.note = '',
    this.source = FocusEntrySource.timer,
    this.revision = 1,
    DateTime? deletedAt,
    List<FocusSpan> spans = const [],
  }) : startedAt = startedAt.toUtc(),
       endedAt = endedAt?.toUtc(),
       deletedAt = deletedAt?.toUtc(),
       _target = target,
       spans = List.unmodifiable(spans) {
    requireText(id, 'focus session id');
    if (targetMinutes < 0 || seconds < 0 || revision < 1) {
      throw ArgumentError('Invalid focus session timing');
    }
    final typed = this.target;
    if (habitId.isNotEmpty && typed.kind != FocusTargetKind.habit) {
      throw ArgumentError('Habit id conflicts with focus target');
    }
    if (typed.kind == FocusTargetKind.habit &&
        habitId.isNotEmpty &&
        typed.id != habitId) {
      throw ArgumentError('Focus target habit does not match habit id');
    }
    if (typed.kind == FocusTargetKind.free && habitId.isNotEmpty) {
      throw ArgumentError('Free focus cannot have a habit id');
    }
    _validateSpans(typed);
  }

  final String id;
  final String habitId;
  final int targetMinutes;
  final int seconds;
  final bool completed;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String note;
  final FocusEntrySource source;
  final int revision;
  final DateTime? deletedAt;
  final List<FocusSpan> spans;
  final FocusTarget? _target;

  FocusTarget get target =>
      _target ??
      (habitId.isEmpty ? FocusTarget.free() : FocusTarget.habit(habitId));

  int get minutes => seconds ~/ 60;

  bool get isWork => target.kind == FocusTargetKind.workTask;
  bool get isDeleted => deletedAt != null;

  DateTime get effectiveEndedAt =>
      endedAt ?? startedAt.add(Duration(seconds: seconds));

  void _validateSpans(FocusTarget typed) {
    final end = endedAt;
    if (end != null && end.isBefore(startedAt)) {
      throw ArgumentError('Focus session cannot end before it starts');
    }
    final sorted = spans.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].startedAt.isBefore(startedAt)) {
        throw ArgumentError('Focus span precedes session start');
      }
      if (i > 0 && sorted[i].startedAt.isBefore(sorted[i - 1].endedAt)) {
        throw ArgumentError('Focus spans cannot overlap');
      }
      if (endedAt != null && sorted[i].endedAt.isAfter(endedAt!)) {
        throw ArgumentError('Focus span exceeds session end');
      }
    }
    if (typed.kind != FocusTargetKind.workTask) return;
    if (spans.isEmpty || endedAt == null) {
      throw ArgumentError('Work focus sessions need spans and an end time');
    }
    final spanSeconds = spans.fold(0, (sum, span) => sum + span.seconds);
    if (spanSeconds != seconds || seconds <= 0) {
      throw ArgumentError('Work focus seconds must match active spans');
    }
  }

  int secondsOnDay(DateTime day, {int cutoffHour = 0}) {
    if (!isWork) return startedAt.toLocal().dayKey == day.dayKey ? seconds : 0;
    final start = DateTime(day.year, day.month, day.day, cutoffHour);
    final end = DateTime(day.year, day.month, day.day + 1, cutoffHour);
    return secondsInPeriod(start, end);
  }

  int secondsInPeriod(DateTime start, DateTime end) {
    if (!isWork) {
      final local = startedAt.toLocal();
      return !local.isBefore(start) && local.isBefore(end) ? seconds : 0;
    }
    var total = 0;
    for (final span in spans) {
      final spanStart = span.startedAt.toLocal();
      final spanEnd = span.endedAt.toLocal();
      final overlapStart = spanStart.isAfter(start) ? spanStart : start;
      final overlapEnd = spanEnd.isBefore(end) ? spanEnd : end;
      if (overlapEnd.isAfter(overlapStart)) {
        total += overlapEnd.difference(overlapStart).inSeconds;
      }
    }
    return total;
  }

  FocusSession copyWith({
    String? id,
    String? habitId,
    int? targetMinutes,
    int? seconds,
    bool? completed,
    DateTime? startedAt,
    FocusTarget? target,
    DateTime? endedAt,
    bool clearEndedAt = false,
    String? note,
    FocusEntrySource? source,
    int? revision,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    List<FocusSpan>? spans,
  }) => FocusSession(
    id: id ?? this.id,
    habitId: habitId ?? this.habitId,
    targetMinutes: targetMinutes ?? this.targetMinutes,
    seconds: seconds ?? this.seconds,
    completed: completed ?? this.completed,
    startedAt: startedAt ?? this.startedAt,
    target: target ?? _target,
    endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
    note: note ?? this.note,
    source: source ?? this.source,
    revision: revision ?? this.revision,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    spans: spans ?? this.spans,
  );

  Map<String, dynamic> toMap() => {
    'version': focusSessionSchemaVersion,
    'id': id,
    'habitId': habitId,
    'targetMinutes': targetMinutes,
    'seconds': seconds,
    'completed': completed,
    'startedAt': startedAt.toIso8601String(),
    'target': target.toMap(),
    'endedAt': endedAt?.toIso8601String(),
    'note': note,
    'source': source.name,
    'revision': revision,
    'deletedAt': deletedAt?.toIso8601String(),
    'spans': spans.map((span) => span.toMap()).toList(),
  };

  factory FocusSession.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    final version = map['version'];
    if (version != null &&
        (version is! int ||
            version < 1 ||
            version > focusSessionSchemaVersion)) {
      throw FormatException('Unsupported focus session version: $version');
    }
    final typed =
        (version ?? 0) >= focusSessionSchemaVersion ||
        map.containsKey('target') ||
        map.containsKey('spans') ||
        map.containsKey('source') ||
        map.containsKey('endedAt') ||
        map.containsKey('deletedAt');
    if (typed) {
      for (final key in const [
        'id',
        'habitId',
        'targetMinutes',
        'seconds',
        'completed',
        'startedAt',
        'target',
      ]) {
        if (!map.containsKey(key)) {
          throw FormatException('Missing focus session field: $key');
        }
      }
    }
    final startedAt = typed
        ? read.timestamp('startedAt')
        : DateTime.tryParse((map['startedAt'] ?? '') as String) ??
              DateTime.now();
    final target = typed
        ? FocusTarget.fromMap(RecordReader.object(map['target']))
        : FocusTarget.fromSessionMap(map);
    return FocusSession(
      id: read.string('id'),
      habitId: read.string('habitId', fallback: ''),
      targetMinutes: typed
          ? read.integer('targetMinutes')
          : read.integer('targetMinutes', fallback: 0),
      seconds: typed
          ? read.integer('seconds')
          : read.integer('seconds', fallback: 0),
      completed: read.boolean('completed'),
      startedAt: startedAt,
      target: target,
      endedAt: read.optionalTimestamp('endedAt'),
      note: read.string('note', fallback: ''),
      source: read.enumValue(
        'source',
        FocusEntrySource.values,
        fallback: FocusEntrySource.timer,
      ),
      revision: read.integer('revision', fallback: 1),
      deletedAt: read.optionalTimestamp('deletedAt'),
      spans: [
        for (final item in read.list('spans'))
          FocusSpan.fromMap(RecordReader.object(item)),
      ],
    );
  }
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
}

String formatHoursShort(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0 && m == 0) return '${seconds}s';
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
