import 'package:streak/core/data/record.dart';

enum WorkEntityKind { area, project, task, goal }

enum WorkEntryKind { note, progress, statusChange, scopeChange }

class WorkEntry extends StoredRecord {
  WorkEntry({
    required RecordMeta meta,
    required this.entityKind,
    required this.entityId,
    this.kind = WorkEntryKind.note,
    this.text = '',
    String? date,
    this.previousValue,
    this.value,
    this.previousStatus,
    this.status,
    this.measurementUnit = '',
    this.measurementKind = '',
    this.measurementSource = '',
    this.measurementBaseline,
    this.measurementTarget,
    List<String> photos = const [],
  }) : date = date ?? meta.createdDay,
       photos = List.unmodifiable(photos),
       super(meta) {
    requireText(entityId, 'entityId');
    requireDay(this.date, 'date');
    if ((previousValue != null && !previousValue!.isFinite) ||
        (value != null && !value!.isFinite) ||
        (measurementBaseline != null && !measurementBaseline!.isFinite) ||
        (measurementTarget != null && !measurementTarget!.isFinite)) {
      throw ArgumentError('Progress history requires finite values');
    }
    if (kind == WorkEntryKind.progress && value == null) {
      throw ArgumentError('A progress entry needs its recorded value');
    }
    if (kind == WorkEntryKind.statusChange) {
      requireText(status ?? '', 'status');
    }
  }

  final WorkEntityKind entityKind;
  final String entityId;
  final WorkEntryKind kind;
  final String text;
  final String date;
  final double? previousValue;
  final double? value;
  final String? previousStatus;
  final String? status;
  final String measurementUnit;
  final String measurementKind;
  final String measurementSource;
  final double? measurementBaseline;
  final double? measurementTarget;
  final List<String> photos;

  WorkEntry copyWith({
    RecordMeta? meta,
    String? text,
    List<String>? photos,
  }) => WorkEntry(
    meta: meta ?? this.meta,
    entityKind: entityKind,
    entityId: entityId,
    kind: kind,
    text: text ?? this.text,
    date: date,
    previousValue: previousValue,
    value: value,
    previousStatus: previousStatus,
    status: status,
    measurementUnit: measurementUnit,
    measurementKind: measurementKind,
    measurementSource: measurementSource,
    measurementBaseline: measurementBaseline,
    measurementTarget: measurementTarget,
    photos: photos ?? this.photos,
  );

  @override
  Map<String, dynamic> toMap() => {
    ...meta.toMap(),
    'entityKind': entityKind.name,
    'entityId': entityId,
    'kind': kind.name,
    'text': text,
    'date': date,
    'previousValue': previousValue,
    'value': value,
    'previousStatus': previousStatus,
    'status': status,
    'measurementUnit': measurementUnit,
    'measurementKind': measurementKind,
    'measurementSource': measurementSource,
    'measurementBaseline': measurementBaseline,
    'measurementTarget': measurementTarget,
    'photos': photos,
  };

  factory WorkEntry.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return WorkEntry(
      meta: RecordMeta.fromMap(map),
      entityKind: read.enumValue('entityKind', WorkEntityKind.values),
      entityId: read.string('entityId'),
      kind: read.enumValue('kind', WorkEntryKind.values),
      text: read.string('text', fallback: ''),
      date: read.string('date'),
      previousValue: map['previousValue'] == null
          ? null
          : read.number('previousValue'),
      value: map['value'] == null ? null : read.number('value'),
      previousStatus: read.optionalString('previousStatus'),
      status: read.optionalString('status'),
      measurementUnit: read.string('measurementUnit', fallback: ''),
      measurementKind: read.string('measurementKind', fallback: ''),
      measurementSource: read.string('measurementSource', fallback: ''),
      measurementBaseline: map['measurementBaseline'] == null
          ? null
          : read.number('measurementBaseline'),
      measurementTarget: map['measurementTarget'] == null
          ? null
          : read.number('measurementTarget'),
      photos: read.strings('photos'),
    );
  }
}

class WorkPlanBlock extends StoredRecord {
  WorkPlanBlock({
    required RecordMeta meta,
    required this.taskId,
    required DateTime startsAt,
    required this.minutes,
    this.timeZone = '',
    this.note = '',
  }) : startsAt = startsAt.toUtc(),
       super(meta) {
    requireText(taskId, 'taskId');
    if (minutes <= 0) throw ArgumentError('A work block needs positive time');
  }

  final String taskId;
  final DateTime startsAt;
  final int minutes;
  final String timeZone;
  final String note;

  DateTime get endsAt => startsAt.add(Duration(minutes: minutes));

  WorkPlanBlock copyWith({
    RecordMeta? meta,
    String? taskId,
    DateTime? startsAt,
    int? minutes,
    String? timeZone,
    String? note,
  }) => WorkPlanBlock(
    meta: meta ?? this.meta,
    taskId: taskId ?? this.taskId,
    startsAt: startsAt ?? this.startsAt,
    minutes: minutes ?? this.minutes,
    timeZone: timeZone ?? this.timeZone,
    note: note ?? this.note,
  );

  @override
  Map<String, dynamic> toMap() => {
    ...meta.toMap(),
    'taskId': taskId,
    'startsAt': startsAt.toIso8601String(),
    'minutes': minutes,
    'timeZone': timeZone,
    'note': note,
  };

  factory WorkPlanBlock.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return WorkPlanBlock(
      meta: RecordMeta.fromMap(map),
      taskId: read.string('taskId'),
      startsAt: read.timestamp('startsAt'),
      minutes: read.integer('minutes'),
      timeZone: read.string('timeZone', fallback: ''),
      note: read.string('note', fallback: ''),
    );
  }
}
