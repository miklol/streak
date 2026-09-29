import 'package:streak/core/data/record.dart';
import 'package:streak/features/todos/data/todo.dart';

enum WorkProjectStatus { planned, active, onHold, done, cancelled }

class WorkProject extends StoredRecord {
  WorkProject({
    required RecordMeta meta,
    required this.name,
    this.order = 0,
    this.areaId,
    this.status = WorkProjectStatus.planned,
    this.description = '',
    this.outcome = '',
    this.startDate,
    this.dueDate,
    this.priority = TodoPriority.none,
    this.coverPath = '',
    List<String> tags = const [],
    List<String> links = const [],
  }) : tags = List.unmodifiable(tags),
       links = List.unmodifiable(links),
       super(meta) {
    requireText(name, 'name');
    if (order < 0) throw ArgumentError('Project order cannot be negative');
    requireOptionalId(areaId, 'areaId');
    requireDayRange(startDate, dueDate);
  }

  final String name;
  final int order;
  final String? areaId;
  final WorkProjectStatus status;
  final String description;
  final String outcome;
  final String? startDate;
  final String? dueDate;
  final TodoPriority priority;
  final String coverPath;
  final List<String> tags;
  final List<String> links;

  WorkProject copyWith({
    RecordMeta? meta,
    String? name,
    int? order,
    String? areaId,
    bool clearArea = false,
    WorkProjectStatus? status,
    String? description,
    String? outcome,
    String? startDate,
    bool clearStart = false,
    String? dueDate,
    bool clearDue = false,
    TodoPriority? priority,
    String? coverPath,
    List<String>? tags,
    List<String>? links,
  }) => WorkProject(
    meta: meta ?? this.meta,
    name: name ?? this.name,
    order: order ?? this.order,
    areaId: clearArea ? null : (areaId ?? this.areaId),
    status: status ?? this.status,
    description: description ?? this.description,
    outcome: outcome ?? this.outcome,
    startDate: clearStart ? null : (startDate ?? this.startDate),
    dueDate: clearDue ? null : (dueDate ?? this.dueDate),
    priority: priority ?? this.priority,
    coverPath: coverPath ?? this.coverPath,
    tags: tags ?? this.tags,
    links: links ?? this.links,
  );

  @override
  Map<String, dynamic> toMap() => {
    ...meta.toMap(),
    'name': name,
    'order': order,
    'areaId': areaId,
    'status': status.name,
    'description': description,
    'outcome': outcome,
    'startDate': startDate,
    'dueDate': dueDate,
    'priority': priority.name,
    'coverPath': coverPath,
    'tags': tags,
    'links': links,
  };

  factory WorkProject.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return WorkProject(
      meta: RecordMeta.fromMap(map),
      name: read.string('name'),
      order: read.integer('order', fallback: 0),
      areaId: read.optionalString('areaId'),
      status: read.enumValue('status', WorkProjectStatus.values),
      description: read.string('description', fallback: ''),
      outcome: read.string('outcome', fallback: ''),
      startDate: read.optionalString('startDate'),
      dueDate: read.optionalString('dueDate'),
      priority: read.enumValue(
        'priority',
        TodoPriority.values,
        fallback: TodoPriority.none,
      ),
      coverPath: read.string('coverPath', fallback: ''),
      tags: read.strings('tags'),
      links: read.strings('links'),
    );
  }
}
