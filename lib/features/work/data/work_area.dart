import 'package:streak/core/data/record.dart';

enum WorkAreaType { company, client, independent }

class WorkArea extends StoredRecord {
  WorkArea({
    required RecordMeta meta,
    required this.name,
    this.order = 0,
    this.type = WorkAreaType.independent,
    this.description = '',
    this.role = '',
    this.icon = 'briefcase',
    this.color = 0xFF7C5CFF,
    this.coverPath = '',
    List<String> links = const [],
    List<int> workingDays = const [1, 2, 3, 4, 5],
    this.weeklyFocusMinutes = 0,
  }) : links = List.unmodifiable(links),
       workingDays = List.unmodifiable(workingDays),
       super(meta) {
    requireText(name, 'name');
    if (order < 0 ||
        color < 0 ||
        color > 0xFFFFFFFF ||
        weeklyFocusMinutes < 0 ||
        workingDays.any((day) => day < 1 || day > 7) ||
        workingDays.toSet().length != workingDays.length) {
      throw ArgumentError('Invalid work area settings');
    }
  }

  final String name;
  final int order;
  final WorkAreaType type;
  final String description;
  final String role;
  final String icon;
  final int color;
  final String coverPath;
  final List<String> links;
  final List<int> workingDays;
  final int weeklyFocusMinutes;

  WorkArea copyWith({
    RecordMeta? meta,
    String? name,
    int? order,
    WorkAreaType? type,
    String? description,
    String? role,
    String? icon,
    int? color,
    String? coverPath,
    List<String>? links,
    List<int>? workingDays,
    int? weeklyFocusMinutes,
  }) => WorkArea(
    meta: meta ?? this.meta,
    name: name ?? this.name,
    order: order ?? this.order,
    type: type ?? this.type,
    description: description ?? this.description,
    role: role ?? this.role,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    coverPath: coverPath ?? this.coverPath,
    links: links ?? this.links,
    workingDays: workingDays ?? this.workingDays,
    weeklyFocusMinutes: weeklyFocusMinutes ?? this.weeklyFocusMinutes,
  );

  @override
  Map<String, dynamic> toMap() => {
    ...meta.toMap(),
    'name': name,
    'order': order,
    'type': type.name,
    'description': description,
    'role': role,
    'icon': icon,
    'color': color,
    'coverPath': coverPath,
    'links': links,
    'workingDays': workingDays,
    'weeklyFocusMinutes': weeklyFocusMinutes,
  };

  factory WorkArea.fromMap(Map<String, dynamic> map) {
    final read = RecordReader(map);
    return WorkArea(
      meta: RecordMeta.fromMap(map),
      name: read.string('name'),
      order: read.integer('order', fallback: 0),
      type: read.enumValue('type', WorkAreaType.values),
      description: read.string('description', fallback: ''),
      role: read.string('role', fallback: ''),
      icon: read.string('icon', fallback: 'briefcase'),
      color: read.integer('color', fallback: 0xFF7C5CFF),
      coverPath: read.string('coverPath', fallback: ''),
      links: read.strings('links'),
      workingDays: map.containsKey('workingDays')
          ? read.integers('workingDays')
          : const [1, 2, 3, 4, 5],
      weeklyFocusMinutes: read.integer('weeklyFocusMinutes', fallback: 0),
    );
  }
}
