import 'package:streak/core/data/record.dart';
import 'package:streak/features/todos/data/todo.dart';

enum WorkTaskStatus { notStarted, inProgress, blocked, done, cancelled }

enum WorkTaskProgress { completion, manual }

class WorkTask extends StoredRecord {
  WorkTask({
    required RecordMeta meta,
    required this.title,
    this.order = 0,
    this.sourceTodoId,
    this.areaId,
    this.projectId,
    this.parentTaskId,
    this.status = WorkTaskStatus.notStarted,
    this.progressMode = WorkTaskProgress.completion,
    this.progress = 0,
    this.description = '',
    this.completionCriteria = '',
    this.blockedReason = '',
    this.priority = TodoPriority.none,
    this.startDate,
    this.dueDate,
    this.dueMinute,
    this.timeZone = '',
    this.estimatedMinutes,
    this.focusMinutes = 25,
    this.breakMinutes = 0,
    this.completedAt,
    List<String> tags = const [],
    List<String> links = const [],
    List<String> photos = const [],
    List<DateTime> reminders = const [],
  }) : tags = List.unmodifiable(tags),
       links = List.unmodifiable(links),
       photos = List.unmodifiable(photos),
       reminders = List.unmodifiable(reminders.map((at) => at.toUtc())),
       super(meta) {
    requireText(title, 'title');
    if (order < 0) throw ArgumentError('Task order cannot be negative');
    requireOptionalId(sourceTodoId, 'sourceTodoId');
    requireOptionalId(areaId, 'areaId');
    requireOptionalId(projectId, 'projectId');
    requireOptionalId(parentTaskId, 'parentTaskId');
    requireDayRange(startDate, dueDate);
    if (parentTaskId == id) throw ArgumentError('A task cannot parent itself');
    if (!progress.isFinite || progress < 0 || progress > 100) {
      throw ArgumentError('Task progress must be between 0 and 100');
    }
    if (dueMinute != null &&
        (dueDate == null || dueMinute! < 0 || dueMinute! >= 1440)) {
      throw ArgumentError('A due time needs a date and a valid minute');
    }
    if ((estimatedMinutes != null && estimatedMinutes! < 0) ||
        focusMinutes < 0 ||
        breakMinutes < 0) {
      throw ArgumentError('Work durations cannot be negative');
    }
    if (status == WorkTaskStatus.done &&
        progressMode == WorkTaskProgress.manual &&
        progress != 100) {
      throw ArgumentError('Finish manual progress explicitly before closing');
    }
    if (completedAt != null && status != WorkTaskStatus.done) {
      throw ArgumentError('Only a completed task has a completion timestamp');
    }
  }

  final String title;
  final int order;
  final String? sourceTodoId;
  final String? areaId;
  final String? projectId;
  final String? parentTaskId;
  final WorkTaskStatus status;
  final WorkTaskProgress progressMode;
  final double progress;
  final String description;
  final String completionCriteria;
  final String blockedReason;
  final TodoPriority priority;
  final String? startDate;
  final String? dueDate;
  final int? dueMinute;
  final String timeZone;
  final int? estimatedMinutes;
  final int focusMinutes;
  final int breakMinutes;
  final DateTime? completedAt;
  final List<String> tags;
  final List<String> links;
  final List<String> photos;
  final List<DateTime> reminders;

  double get ownFraction => progressMode == WorkTaskProgress.manual
      ? progress / 100
      : (status == WorkTaskStatus.done ? 1 : 0);

  WorkTask copyWith({
    RecordMeta? meta,
    String? title,
    int? order,
    String? sourceTodoId,
    bool clearSourceTodo = false,
    String? areaId,
    bool clearArea = false,
    String? projectId,
    bool clearProject = false,
    String? parentTaskId,
    bool clearParent = false,
    WorkTaskStatus? status,
    WorkTaskProgress? progressMode,
    double? progress,
    String? description,
    String? completionCriteria,
    String? blockedReason,
    TodoPriority? priority,
    String? startDate,
    bool clearStart = false,
    String? dueDate,
    bool clearDue = false,
    int? dueMinute,
    bool clearDueMinute = false,
    String? timeZone,
    int? estimatedMinutes,
    bool clearEstimate = false,
    int? focusMinutes,
    int? breakMinutes,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    List<String>? tags,
    List<String>? links,
    List<String>? photos,
    List<DateTime>? reminders,
  }) => WorkTask(
    meta: meta ?? this.meta,
    title: title ?? this.title,
    order: order ?? this.order,
    sourceTodoId: clearSourceTodo ? null : (sourceTodoId ?? this.sourceTodoId),
    areaId: clearArea ? null : (areaId ?? this.areaId),
    projectId: clearProject ? null : (projectId ?? this.projectId),
    parentTaskId: clearParent ? null : (parentTaskId ?? this.parentTaskId),
    status: status ?? this.status,
    progressMode: progressMode ?? this.progressMode,
    progress: progress ?? this.progress,
    description: description ?? this.description,
    completionCriteria: completionCriteria ?? this.completionCriteria,
    blockedReason: blockedReason ?? this.blockedReason,
    priority: priority ?? this.priority,
    startDate: clearStart ? null : (startDate ?? this.startDate),
    dueDate: clearDue ? null : (dueDate ?? this.dueDate),
    dueMinute: clearDue || clearDueMinute
        ? null
        : (dueMinute ?? this.dueMinute),
    timeZone: timeZone ?? this.timeZone,
    estimatedMinutes: clearEstimate
        ? null
        : (estimatedMinutes ?? this.estimatedMinutes),
    focusMinutes: focusMinutes ?? this.focusMinutes,
    breakMinutes: breakMinutes ?? this.breakMinutes,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    tags: tags ?? this.tags,
    links: links ?? this.links,
    photos: photos ?? this.photos,
    reminders: reminders ?? this.reminders,
  );

  @override
  Map<String, dynamic> toMap() => {
    ...meta.toMap(),
    'title': title,
    'order': order,
    'sourceTodoId': sourceTodoId,
    'areaId': areaId,
    'projectId': projectId,
    'parentTaskId': parentTaskId,
    'status': status.name,
    'progressMode': progressMode.name,
    'progress': progress,
    'description': description,
    'completionCriteria': completionCriteria,
    'blockedReason': blockedReason,
    'priority': priority.name,
    'startDate': startDate,
    'dueDate': dueDate,
    'dueMinute': dueMinute,
    'timeZone': timeZone,
    'estimatedMinutes': estimatedMinutes,
    'focusMinutes': focusMinutes,
    'breakMinutes': breakMinutes,
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'tags': tags,
    'links': links,
    'photos': photos,
    'reminders': reminders.map((at) => at.toIso8601String()).toList(),
  };

  factory WorkTask.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return WorkTask(
      meta: RecordMeta.fromMap(map),
      title: read.string('title'),
      order: read.integer('order', fallback: 0),
      sourceTodoId: read.optionalString('sourceTodoId'),
      areaId: read.optionalString('areaId'),
      projectId: read.optionalString('projectId'),
      parentTaskId: read.optionalString('parentTaskId'),
      status: read.enumValue('status', WorkTaskStatus.values),
      progressMode: read.enumValue('progressMode', WorkTaskProgress.values),
      progress: read.number('progress', fallback: 0),
      description: read.string('description', fallback: ''),
      completionCriteria: read.string('completionCriteria', fallback: ''),
      blockedReason: read.string('blockedReason', fallback: ''),
      priority: read.enumValue(
        'priority',
        TodoPriority.values,
        fallback: TodoPriority.none,
      ),
      startDate: read.optionalString('startDate'),
      dueDate: read.optionalString('dueDate'),
      dueMinute: read.optionalInteger('dueMinute'),
      timeZone: read.string('timeZone', fallback: ''),
      estimatedMinutes: read.optionalInteger('estimatedMinutes'),
      focusMinutes: read.integer('focusMinutes', fallback: 25),
      breakMinutes: read.integer('breakMinutes', fallback: 0),
      completedAt: read.optionalTimestamp('completedAt'),
      tags: read.strings('tags'),
      links: read.strings('links'),
      photos: read.strings('photos'),
      reminders: [
        for (final value in read.strings('reminders'))
          DateTime.tryParse(value) ??
              (throw const FormatException('Invalid reminder timestamp')),
      ],
    );
  }
}
