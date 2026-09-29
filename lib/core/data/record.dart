import 'package:streak/core/extensions/date_extensions.dart';

class RecordMeta {
  RecordMeta({
    required this.id,
    required this.createdAt,
    String? createdDay,
    DateTime? updatedAt,
    this.revision = 1,
    this.archivedAt,
    this.deletedAt,
  }) : createdDay =
           createdDay ??
           createdAt
               .toLocal()
               .subtract(Duration(hours: AppClock.cutoffHour))
               .dayKey,
       updatedAt = updatedAt ?? createdAt {
    requireText(id, 'id');
    requireDay(this.createdDay, 'createdDay');
    if (revision < 1 || this.updatedAt.isBefore(createdAt)) {
      throw ArgumentError('Invalid record revision or timestamps');
    }
  }

  final String id;
  final DateTime createdAt;
  final String createdDay;
  final DateTime updatedAt;
  final int revision;
  final DateTime? archivedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get isArchived => archivedAt != null;

  RecordMeta revise({required DateTime at, bool? archived, bool? deleted}) {
    if (at.isBefore(updatedAt)) {
      throw ArgumentError('A revision cannot precede the current record');
    }
    return RecordMeta(
      id: id,
      createdAt: createdAt,
      createdDay: createdDay,
      updatedAt: at,
      revision: revision + 1,
      archivedAt: archived == null ? archivedAt : (archived ? at : null),
      deletedAt: deleted == null ? deletedAt : (deleted ? at : null),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'createdDay': createdDay,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'revision': revision,
    'archivedAt': archivedAt?.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory RecordMeta.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return RecordMeta(
      id: read.string('id'),
      createdAt: read.timestamp('createdAt'),
      createdDay: map.containsKey('createdDay')
          ? read.string('createdDay')
          : null,
      updatedAt: read.timestamp('updatedAt'),
      revision: read.integer('revision'),
      archivedAt: read.optionalTimestamp('archivedAt'),
      deletedAt: read.optionalTimestamp('deletedAt'),
    );
  }
}

abstract class StoredRecord {
  const StoredRecord(this.meta);

  final RecordMeta meta;
  String get id => meta.id;
  bool get isDeleted => meta.isDeleted;
  bool get isArchived => meta.isArchived;

  Map<String, dynamic> toMap();
}

class RecordReader {
  const RecordReader(this.map);

  final Map<String, dynamic> map;

  String string(String key, {String? fallback}) {
    final value = map[key];
    if (!map.containsKey(key) && fallback != null) return fallback;
    if (value is! String) throw FormatException('Expected text for $key');
    return value;
  }

  String? optionalString(String key) => map[key] == null ? null : string(key);

  int integer(String key, {int? fallback}) {
    final value = map[key];
    if (!map.containsKey(key) && fallback != null) return fallback;
    if (value is! int) throw FormatException('Expected an integer for $key');
    return value;
  }

  int? optionalInteger(String key) => map[key] == null ? null : integer(key);

  double number(String key, {double? fallback}) {
    final value = map[key];
    if (!map.containsKey(key) && fallback != null) return fallback;
    if (value is! num || !value.isFinite) {
      throw FormatException('Expected a finite number for $key');
    }
    return value.toDouble();
  }

  bool boolean(String key, {bool fallback = false}) {
    final value = map[key];
    if (!map.containsKey(key)) return fallback;
    if (value is! bool) throw FormatException('Expected a boolean for $key');
    return value;
  }

  DateTime timestamp(String key) {
    final result = DateTime.tryParse(string(key));
    if (result == null) throw FormatException('Invalid timestamp for $key');
    return result;
  }

  DateTime? optionalTimestamp(String key) =>
      map[key] == null ? null : timestamp(key);

  T enumValue<T extends Enum>(String key, List<T> values, {T? fallback}) {
    if (!map.containsKey(key) && fallback != null) return fallback;
    final name = string(key);
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('Unknown $key: $name');
  }

  List<dynamic> list(String key) {
    final value = map[key];
    if (!map.containsKey(key)) return const [];
    if (value is! List) throw FormatException('Expected a list for $key');
    return value;
  }

  List<String> strings(String key) => [
    for (final value in list(key))
      if (value is String)
        value
      else
        throw FormatException('Expected text in $key'),
  ];

  List<int> integers(String key) => [
    for (final value in list(key))
      if (value is int)
        value
      else
        throw FormatException('Expected integers in $key'),
  ];

  static Map<String, dynamic> object(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('Expected an object with string keys');
    }
    return Map<String, dynamic>.from(value);
  }
}

void requireText(String value, String field) {
  if (value.trim().isEmpty) throw ArgumentError('$field cannot be empty');
}

void requireOptionalId(String? value, String field) {
  if (value != null) requireText(value, field);
}

void requireDay(String? value, String field) {
  if (value == null) return;
  if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(value) ||
      parseDayKey(value).dayKey != value) {
    throw ArgumentError('Invalid date for $field');
  }
}

void requireDayRange(String? start, String? end) {
  requireDay(start, 'startDate');
  requireDay(end, 'endDate');
  if (start != null &&
      end != null &&
      parseDayKey(end).epochDay < parseDayKey(start).epochDay) {
    throw ArgumentError('End date cannot precede start date');
  }
}
