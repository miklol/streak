import 'package:streak/core/data/record.dart';

enum GoalScope { personal, work }

enum GoalStatus { notStarted, active, paused, achieved, cancelled }

enum GoalMeasurement { completion, percentage, number, currency }

enum GoalSource { manual, habits, work }

class Goal extends StoredRecord {
  Goal({
    required RecordMeta meta,
    required this.title,
    this.scope = GoalScope.personal,
    this.status = GoalStatus.notStarted,
    this.measurement = GoalMeasurement.completion,
    this.source = GoalSource.manual,
    this.areaId,
    this.projectId,
    this.description = '',
    this.category = '',
    this.why = '',
    this.icon = 'target',
    this.color = 0xFF6750A4,
    this.pinned = false,
    this.order = 0,
    this.baseline = 0,
    this.current = 0,
    this.target = 1,
    this.unit = '',
    this.currency = '',
    this.startDate,
    this.endDate,
    List<String> taskIds = const [],
    List<String> projectIds = const [],
    List<String> photos = const [],
  }) : taskIds = List.unmodifiable(taskIds),
       projectIds = List.unmodifiable(projectIds),
       photos = List.unmodifiable(photos),
       super(meta) {
    requireText(title, 'title');
    requireText(icon, 'icon');
    requireOptionalId(areaId, 'areaId');
    requireOptionalId(projectId, 'projectId');
    requireDayRange(startDate, endDate);
    _requireDistinctText(this.taskIds, 'taskIds');
    _requireDistinctText(this.projectIds, 'projectIds');
    _requireDistinctText(this.photos, 'photos');
    if (scope == GoalScope.personal && (areaId != null || projectId != null)) {
      throw ArgumentError('Personal goals cannot own a work area or project');
    }
    if (color < 0 || color > 0xFFFFFFFF) {
      throw ArgumentError('color must be an unsigned ARGB value');
    }
    if (order < 0) throw ArgumentError('Goal order cannot be negative');
    if (!baseline.isFinite ||
        !current.isFinite ||
        !target.isFinite ||
        !(target - baseline).isFinite ||
        !(current - baseline).isFinite ||
        baseline == target) {
      throw ArgumentError('Goal values need a finite, nonzero target span');
    }
    if (unit != unit.trim() || currency != currency.trim()) {
      throw ArgumentError('Units and currency codes cannot have outer spaces');
    }
    if (measurement != GoalMeasurement.currency && currency.isNotEmpty) {
      throw ArgumentError('Only currency goals can specify a currency code');
    }
    switch (measurement) {
      case GoalMeasurement.completion:
        if (baseline != 0 ||
            target != 1 ||
            (current != 0 && current != 1) ||
            unit.isNotEmpty) {
          throw ArgumentError('Completion goals use only zero or one');
        }
      case GoalMeasurement.percentage:
        if ([baseline, current, target].any((v) => v < 0 || v > 100) ||
            (unit.isNotEmpty && unit != '%')) {
          throw ArgumentError('Percentage goals use values from 0 to 100');
        }
      case GoalMeasurement.number:
        requireText(unit, 'unit');
      case GoalMeasurement.currency:
        if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
            (unit.isNotEmpty && unit != currency)) {
          throw ArgumentError('Currency goals need a matching currency code');
        }
    }
    if (source == GoalSource.work &&
        (measurement != GoalMeasurement.percentage ||
            baseline != 0 ||
            target != 100)) {
      throw ArgumentError('Work delivery uses percentage from zero to 100');
    }
    if (source == GoalSource.habits &&
        measurement == GoalMeasurement.completion) {
      throw ArgumentError(
        'Habit outcomes need a number, currency or percentage',
      );
    }
  }

  final String title;
  final GoalScope scope;
  final GoalStatus status;
  final GoalMeasurement measurement;
  final GoalSource source;
  final String? areaId;
  final String? projectId;
  final String description;
  final String category;
  final String why;
  final String icon;
  final int color;
  final bool pinned;
  final int order;
  final double baseline;
  final double current;
  final double target;
  final String unit;
  final String currency;
  final String? startDate;
  final String? endDate;
  final List<String> taskIds;
  final List<String> projectIds;
  final List<String> photos;

  @override
  Map<String, dynamic> toMap() => {
    ...meta.toMap(),
    'title': title,
    'scope': scope.name,
    'status': status.name,
    'measurement': measurement.name,
    'source': source.name,
    'areaId': areaId,
    'projectId': projectId,
    'description': description,
    'category': category,
    'why': why,
    'icon': icon,
    'color': color,
    'pinned': pinned,
    'order': order,
    'baseline': baseline,
    'current': current,
    'target': target,
    'unit': unit,
    'currency': currency,
    'startDate': startDate,
    'endDate': endDate,
    'taskIds': taskIds.toList(),
    'projectIds': projectIds.toList(),
    'photos': photos.toList(),
  };

  factory Goal.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return Goal(
      meta: RecordMeta.fromMap(map),
      title: read.string('title'),
      scope: read.enumValue('scope', GoalScope.values),
      status: read.enumValue('status', GoalStatus.values),
      measurement: read.enumValue('measurement', GoalMeasurement.values),
      source: read.enumValue('source', GoalSource.values),
      areaId: read.optionalString('areaId'),
      projectId: read.optionalString('projectId'),
      description: read.string('description', fallback: ''),
      category: read.string('category', fallback: ''),
      why: read.string('why', fallback: ''),
      icon: read.string('icon', fallback: 'target'),
      color: read.integer('color', fallback: 0xFF6750A4),
      pinned: read.boolean('pinned'),
      order: read.integer('order', fallback: 0),
      baseline: read.number('baseline'),
      current: read.number('current'),
      target: read.number('target'),
      unit: read.string('unit', fallback: ''),
      currency: read.string('currency', fallback: ''),
      startDate: read.optionalString('startDate'),
      endDate: read.optionalString('endDate'),
      taskIds: read.strings('taskIds'),
      projectIds: read.strings('projectIds'),
      photos: read.strings('photos'),
    );
  }

  Goal copyWith({
    RecordMeta? meta,
    String? title,
    GoalScope? scope,
    GoalStatus? status,
    GoalMeasurement? measurement,
    GoalSource? source,
    String? areaId,
    String? projectId,
    bool clearAreaId = false,
    bool clearProjectId = false,
    String? description,
    String? category,
    String? why,
    String? icon,
    int? color,
    bool? pinned,
    int? order,
    double? baseline,
    double? current,
    double? target,
    String? unit,
    String? currency,
    String? startDate,
    String? endDate,
    bool clearStartDate = false,
    bool clearEndDate = false,
    List<String>? taskIds,
    List<String>? projectIds,
    List<String>? photos,
  }) => Goal(
    meta: meta ?? this.meta,
    title: title ?? this.title,
    scope: scope ?? this.scope,
    status: status ?? this.status,
    measurement: measurement ?? this.measurement,
    source: source ?? this.source,
    areaId: clearAreaId ? null : (areaId ?? this.areaId),
    projectId: clearProjectId ? null : (projectId ?? this.projectId),
    description: description ?? this.description,
    category: category ?? this.category,
    why: why ?? this.why,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    pinned: pinned ?? this.pinned,
    order: order ?? this.order,
    baseline: baseline ?? this.baseline,
    current: current ?? this.current,
    target: target ?? this.target,
    unit: unit ?? this.unit,
    currency: currency ?? this.currency,
    startDate: clearStartDate ? null : (startDate ?? this.startDate),
    endDate: clearEndDate ? null : (endDate ?? this.endDate),
    taskIds: taskIds ?? this.taskIds,
    projectIds: projectIds ?? this.projectIds,
    photos: photos ?? this.photos,
  );
}

void _requireDistinctText(List<String> values, String field) {
  for (final value in values) {
    requireText(value, field);
  }
  if (values.toSet().length != values.length) {
    throw ArgumentError('$field cannot contain duplicates');
  }
}
