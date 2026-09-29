import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/icons/habit_glyph.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/cover_storage.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/habits/widgets/color_picker.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/todos/widgets/todo_labels.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

Future<WorkArea?> showWorkAreaForm(BuildContext context, {WorkArea? area}) =>
    _showResponsiveForm(
      context,
      child: _WorkAreaForm(area: area),
    );

Future<WorkProject?> showWorkProjectForm(
  BuildContext context, {
  WorkProject? project,
  String? areaId,
}) => _showResponsiveForm(
  context,
  child: _WorkProjectForm(project: project, areaId: areaId),
);

Future<WorkTask?> showWorkTaskForm(
  BuildContext context, {
  WorkTask? task,
  String? areaId,
  String? projectId,
  String? parentTaskId,
}) => _showResponsiveForm(
  context,
  child: _WorkTaskForm(
    task: task,
    areaId: areaId,
    projectId: projectId,
    parentTaskId: parentTaskId,
  ),
);

Future<T?> _showResponsiveForm<T>(
  BuildContext context, {
  required Widget child,
}) {
  if (isWideLayout(context)) {
    return AppNavigator.push<T>(child, fade: true);
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => FractionallySizedBox(
      heightFactor: 0.96,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: sheet.colors.surface,
            borderRadius: BorderRadius.circular(28),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _WorkFormScaffold extends StatelessWidget {
  const _WorkFormScaffold({
    required this.title,
    required this.saving,
    required this.onSave,
    required this.children,
    this.formError,
  });

  final String title;
  final bool saving;
  final VoidCallback onSave;
  final List<Widget> children;
  final String? formError;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final express = settings.isExpressStyle;
    final minimal = settings.isMinimalStyle;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: express ? 60 : (minimal ? 52 : null),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: express || minimal ? null : Text(title),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.onPrimary,
                    ),
                  )
                : const Icon(LucideIcons.save, size: 18),
            label: Text(context.l10n.save),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
        children: [
          WorkPageHeader(title: title),
          if (formError != null) ...[
            const SizedBox(height: 12),
            Material(
              color: context.tokens.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  formError!,
                  style: sheetBodyStyle(
                    context,
                    size: 14,
                    color: context.tokens.danger,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _WorkAreaForm extends StatefulWidget {
  const _WorkAreaForm({this.area});

  final WorkArea? area;

  @override
  State<_WorkAreaForm> createState() => _WorkAreaFormState();
}

class _WorkAreaFormState extends State<_WorkAreaForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  late final TextEditingController _name = TextEditingController(
    text: widget.area?.name ?? '',
  );
  late final TextEditingController _role = TextEditingController(
    text: widget.area?.role ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.area?.description ?? '',
  );
  late final TextEditingController _links = TextEditingController(
    text: _joinLines(widget.area?.links ?? const []),
  );

  late WorkAreaType _type = widget.area?.type ?? WorkAreaType.independent;
  late String _icon = widget.area?.icon ?? workIconChoices.first;
  late Color _color = Color(widget.area?.color ?? 0xFF7C5CFF);
  late String _coverPath = widget.area?.coverPath ?? '';

  bool _saving = false;
  bool _submitted = false;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _description.dispose();
    _links.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _pickCover({bool fromCamera = false}) async {
    final path = await CoverStorage.store(
      folder: 'work',
      fromCamera: fromCamera,
    );
    if (path != null && mounted) setState(() => _coverPath = path);
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _formError = null;
    });
    if (!_formKey.currentState!.validate()) {
      _nameFocus.requestFocus();
      return;
    }
    setState(() => _saving = true);
    final existing = widget.area;
    await runWorkAction(
      context,
      () async {
        final draft = existing == null
            ? WorkArea(
                meta: WorkController.newMeta(),
                name: _name.text.trim(),
                type: _type,
                role: _role.text.trim(),
                description: _description.text.trim(),
                icon: _icon,
                color: _color.toARGB32(),
                coverPath: _coverPath,
                links: _splitValues(_links.text, commaSeparated: false),
              )
            : existing.copyWith(
                name: _name.text.trim(),
                type: _type,
                role: _role.text.trim(),
                description: _description.text.trim(),
                icon: _icon,
                color: _color.toARGB32(),
                coverPath: _coverPath,
                links: _splitValues(_links.text, commaSeparated: false),
              );
        final saved = await context.read<WorkController>().saveArea(
          draft,
          expectedRevision: existing?.meta.revision,
        );
        if (!mounted) return;
        Navigator.of(context).pop(saved);
      },
      onError: (error) {
        if (!mounted) return;
        final message = workErrorMessage(context, error);
        setState(() {
          _saving = false;
          _formError = message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _WorkFormScaffold(
      title: widget.area == null
          ? context.l10n.work_add_area
          : context.l10n.work_edit_area,
      saving: _saving,
      formError: _formError,
      onSave: _save,
      children: [
        Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkSection(
                title: context.l10n.work_basics,
                child: WorkCard(
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('work-area-name-field'),
                        controller: _name,
                        focusNode: _nameFocus,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_area_name,
                          hintText: context.l10n.work_area_name_hint,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? context.l10n.work_name_required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<WorkAreaType>(
                        initialValue: _type,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_area_type,
                        ),
                        items: [
                          for (final value in WorkAreaType.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(workAreaTypeLabel(context, value)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _type = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _role,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_role,
                          hintText: context.l10n.work_role_hint,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _description,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: context.l10n.description,
                          hintText: context.l10n.work_area_description_hint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_style,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WorkCard(
                      child: DropdownButtonFormField<String>(
                        initialValue: _icon,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.icon,
                        ),
                        items: [
                          for (final icon in workIconChoices)
                            DropdownMenuItem(
                              value: icon,
                              child: Row(
                                children: [
                                  HabitGlyph(glyph: icon, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_iconLabel(icon))),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _icon = value);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    WorkCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.color,
                            style: sheetLabelStyle(context),
                          ),
                          const SizedBox(height: 12),
                          ColorPicker(
                            selected: _color,
                            onSelected: (color) =>
                                setState(() => _color = color),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              WorkSection(
                title: context.l10n.work_cover,
                child: WorkCoverField(
                  coverPath: _coverPath,
                  accent: _color,
                  onCamera: _saving
                      ? () {}
                      : () => _pickCover(fromCamera: true),
                  onGallery: _saving ? () {} : _pickCover,
                  onClear: () => setState(() => _coverPath = ''),
                ),
              ),
              WorkSection(
                title: context.l10n.work_links,
                child: WorkCard(
                  child: TextFormField(
                    controller: _links,
                    minLines: 2,
                    maxLines: 5,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: context.l10n.work_links,
                      hintText: context.l10n.work_links_hint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkProjectForm extends StatefulWidget {
  const _WorkProjectForm({this.project, this.areaId});

  final WorkProject? project;
  final String? areaId;

  @override
  State<_WorkProjectForm> createState() => _WorkProjectFormState();
}

class _WorkProjectFormState extends State<_WorkProjectForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  late final TextEditingController _name = TextEditingController(
    text: widget.project?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.project?.description ?? '',
  );
  late final TextEditingController _outcome = TextEditingController(
    text: widget.project?.outcome ?? '',
  );
  late final TextEditingController _tags = TextEditingController(
    text: _joinList(widget.project?.tags ?? const []),
  );
  late final TextEditingController _links = TextEditingController(
    text: _joinLines(widget.project?.links ?? const []),
  );
  late String? _areaId = widget.project?.areaId ?? widget.areaId;
  late WorkProjectStatus _status =
      widget.project?.status ?? WorkProjectStatus.planned;
  late TodoPriority _priority = widget.project?.priority ?? TodoPriority.none;
  late String? _startDate = widget.project?.startDate;
  late String? _dueDate = widget.project?.dueDate;
  late String _coverPath = widget.project?.coverPath ?? '';

  bool _saving = false;
  bool _submitted = false;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _outcome.dispose();
    _tags.dispose();
    _links.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required bool due,
  }) async {
    final current = due ? _dueDate : _startDate;
    final initial = current == null
        ? AppClock.wallNow().atMidnight
        : parseDayKey(current);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year < 2020 ? initial.year : 2020),
      lastDate: DateTime(initial.year > 2100 ? initial.year : 2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final value = picked.dayKey;
      if (due) {
        _dueDate = value;
      } else {
        _startDate = value;
      }
    });
  }

  Future<void> _pickCover({bool fromCamera = false}) async {
    final path = await CoverStorage.store(
      folder: 'work',
      fromCamera: fromCamera,
    );
    if (path != null && mounted) setState(() => _coverPath = path);
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _formError = null;
    });
    if (!_formKey.currentState!.validate()) {
      _nameFocus.requestFocus();
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        parseDayKey(_dueDate!).epochDay < parseDayKey(_startDate!).epochDay) {
      setState(() => _formError = context.l10n.work_error_date_order);
      return;
    }
    setState(() => _saving = true);
    final existing = widget.project;
    await runWorkAction(
      context,
      () async {
        final draft = existing == null
            ? WorkProject(
                meta: WorkController.newMeta(),
                name: _name.text.trim(),
                areaId: _areaId,
                status: _status,
                description: _description.text.trim(),
                outcome: _outcome.text.trim(),
                startDate: _startDate,
                dueDate: _dueDate,
                priority: _priority,
                coverPath: _coverPath,
                tags: _splitValues(_tags.text),
                links: _splitValues(_links.text, commaSeparated: false),
              )
            : existing.copyWith(
                name: _name.text.trim(),
                areaId: _areaId,
                clearArea: _areaId == null,
                status: _status,
                description: _description.text.trim(),
                outcome: _outcome.text.trim(),
                startDate: _startDate,
                clearStart: _startDate == null,
                dueDate: _dueDate,
                clearDue: _dueDate == null,
                priority: _priority,
                coverPath: _coverPath,
                tags: _splitValues(_tags.text),
                links: _splitValues(_links.text, commaSeparated: false),
              );
        final saved = await context.read<WorkController>().saveProject(
          draft,
          expectedRevision: existing?.meta.revision,
        );
        if (!mounted) return;
        Navigator.of(context).pop(saved);
      },
      onError: (error) {
        if (!mounted) return;
        final message = workErrorMessage(context, error);
        setState(() {
          _saving = false;
          _formError = message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final areas = work.areas();
    return _WorkFormScaffold(
      title: widget.project == null
          ? context.l10n.work_add_project
          : context.l10n.work_edit_project,
      saving: _saving,
      formError: _formError,
      onSave: _save,
      children: [
        Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkSection(
                title: context.l10n.work_basics,
                child: WorkCard(
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('work-project-name-field'),
                        controller: _name,
                        focusNode: _nameFocus,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_project_name,
                          hintText: context.l10n.work_project_name_hint,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? context.l10n.work_name_required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: _areaId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_area,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.work_scope_unassigned),
                          ),
                          for (final area in areas)
                            DropdownMenuItem<String?>(
                              value: area.id,
                              child: Text(area.name),
                            ),
                        ],
                        onChanged: (value) => setState(() => _areaId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<WorkProjectStatus>(
                        initialValue: _status,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.status,
                        ),
                        items: [
                          for (final value in WorkProjectStatus.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(
                                workProjectStatusLabel(context, value),
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _status = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TodoPriority>(
                        initialValue: _priority,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.todo_priority,
                        ),
                        items: [
                          for (final value in TodoPriority.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(
                                todoPriorityLabels(context)[value.index],
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _priority = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_details,
                child: WorkCard(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _description,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: context.l10n.description,
                          hintText: context.l10n.work_project_description_hint,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _outcome,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_outcome,
                          hintText: context.l10n.work_project_outcome_hint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_schedule,
                child: WorkCard(
                  child: Column(
                    children: [
                      _DateField(
                        label: context.l10n.work_start_date,
                        value: _startDate,
                        onPick: _saving ? null : () => _pickDate(due: false),
                        onClear: _startDate == null
                            ? null
                            : () => setState(() => _startDate = null),
                      ),
                      const SizedBox(height: 12),
                      _DateField(
                        label: context.l10n.work_due_date,
                        value: _dueDate,
                        onPick: _saving ? null : () => _pickDate(due: true),
                        onClear: _dueDate == null
                            ? null
                            : () => setState(() => _dueDate = null),
                      ),
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_cover,
                child: WorkCoverField(
                  coverPath: _coverPath,
                  accent: context.colors.primary,
                  onCamera: _saving
                      ? () {}
                      : () => _pickCover(fromCamera: true),
                  onGallery: _saving ? () {} : _pickCover,
                  onClear: () => setState(() => _coverPath = ''),
                ),
              ),
              WorkSection(
                title: context.l10n.work_tags,
                child: WorkCard(
                  child: TextFormField(
                    controller: _tags,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: context.l10n.work_tags,
                      hintText: context.l10n.work_tags_hint,
                    ),
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_links,
                child: WorkCard(
                  child: TextFormField(
                    controller: _links,
                    minLines: 2,
                    maxLines: 5,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: context.l10n.work_links,
                      hintText: context.l10n.work_links_hint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkTaskForm extends StatefulWidget {
  const _WorkTaskForm({
    this.task,
    this.areaId,
    this.projectId,
    this.parentTaskId,
  });

  final WorkTask? task;
  final String? areaId;
  final String? projectId;
  final String? parentTaskId;

  @override
  State<_WorkTaskForm> createState() => _WorkTaskFormState();
}

class _WorkTaskFormState extends State<_WorkTaskForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  late final TextEditingController _title = TextEditingController(
    text: widget.task?.title ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.task?.description ?? '',
  );
  late final TextEditingController _criteria = TextEditingController(
    text: widget.task?.completionCriteria ?? '',
  );
  late final TextEditingController _blockedReason = TextEditingController(
    text: widget.task?.blockedReason ?? '',
  );
  late final TextEditingController _estimate = TextEditingController(
    text: widget.task?.estimatedMinutes?.toString() ?? '',
  );
  late final TextEditingController _progress = TextEditingController(
    text: widget.task == null ? '' : _formatProgress(widget.task!.progress),
  );
  late final _focusMinutes = TextEditingController(
    text: '${widget.task?.focusMinutes ?? 25}',
  );
  late final _breakMinutes = TextEditingController(
    text: '${widget.task?.breakMinutes ?? 0}',
  );
  late final TextEditingController _tags = TextEditingController(
    text: _joinList(widget.task?.tags ?? const []),
  );
  late final TextEditingController _links = TextEditingController(
    text: _joinLines(widget.task?.links ?? const []),
  );

  late String? _areaId;
  late String? _projectId;
  late String? _parentTaskId;
  late WorkTaskStatus _status =
      widget.task?.status ?? WorkTaskStatus.notStarted;
  late WorkTaskProgress _progressMode =
      widget.task?.progressMode ?? WorkTaskProgress.completion;
  late TodoPriority _priority = widget.task?.priority ?? TodoPriority.none;
  late String? _startDate = widget.task?.startDate;
  late String? _dueDate = widget.task?.dueDate;
  late int? _dueMinute = widget.task?.dueMinute;
  late final List<String> _photos = [...?widget.task?.photos];

  bool _saving = false;
  bool _submitted = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final work = context.read<WorkController>();
    final existing = widget.task;
    final initialParent = existing?.parentTaskId ?? widget.parentTaskId;
    final parent = initialParent == null ? null : work.taskById(initialParent);
    _areaId = existing == null ? widget.areaId : work.areaForTask(existing);
    _projectId = existing?.projectId ?? widget.projectId;
    _parentTaskId = initialParent;
    if (parent != null) {
      _projectId = parent.projectId;
      _areaId = work.areaForTask(parent);
    } else if (_projectId != null) {
      _areaId ??= work.projectById(_projectId!)?.areaId;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _criteria.dispose();
    _blockedReason.dispose();
    _estimate.dispose();
    _progress.dispose();
    _focusMinutes.dispose();
    _breakMinutes.dispose();
    _tags.dispose();
    _links.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  List<WorkProject> get _projects {
    final work = context.read<WorkController>();
    final currentId = widget.task?.projectId;
    return work
        .projects(areaId: _areaId)
        .where(
          (project) =>
              project.id == currentId ||
              (project.status != WorkProjectStatus.done &&
                  project.status != WorkProjectStatus.cancelled),
        )
        .toList();
  }

  List<WorkTask> get _parents {
    final work = context.read<WorkController>();
    final currentId = widget.task?.parentTaskId;
    return work
        .tasks(
          areaId: _areaId,
          projectId: _projectId,
          rootsOnly: true,
          includeDone: true,
        )
        .where(
          (task) =>
              task.id != widget.task?.id &&
              (task.id == currentId ||
                  (task.progressMode != WorkTaskProgress.manual &&
                      task.status != WorkTaskStatus.done &&
                      task.status != WorkTaskStatus.cancelled)),
        )
        .toList();
  }

  bool get _hasChildren {
    final task = widget.task;
    if (task == null) return false;
    final work = context.read<WorkController>();
    return work.data.tasks.any((child) => child.parentTaskId == task.id);
  }

  Future<void> _pickDate({required bool due}) async {
    final current = due ? _dueDate : _startDate;
    final initial = current == null
        ? AppClock.wallNow().atMidnight
        : parseDayKey(current);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year < 2020 ? initial.year : 2020),
      lastDate: DateTime(initial.year > 2100 ? initial.year : 2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final value = picked.dayKey;
      if (due) {
        _dueDate = value;
      } else {
        _startDate = value;
      }
    });
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueMinute == null
          ? now
          : TimeOfDay(hour: _dueMinute! ~/ 60, minute: _dueMinute! % 60),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dueMinute = picked.hour * 60 + picked.minute;
      _dueDate ??= AppClock.wallNow().dayKey;
    });
  }

  Future<void> _addPhoto({bool fromCamera = false}) async {
    final path = await CoverStorage.store(
      folder: 'work',
      fromCamera: fromCamera,
    );
    if (path != null && mounted) setState(() => _photos.add(path));
  }

  void _onAreaChanged(String? value) {
    setState(() {
      _areaId = value;
      if (_projectId != null &&
          context.read<WorkController>().projectById(_projectId!)?.areaId !=
              value) {
        _projectId = null;
      }
      if (_parentTaskId != null) {
        _parentTaskId = null;
      }
    });
  }

  void _onProjectChanged(String? value) {
    setState(() {
      _projectId = value;
      _parentTaskId = null;
      if (value != null) {
        _areaId = context.read<WorkController>().projectById(value)?.areaId;
      }
    });
  }

  void _onParentChanged(String? value) {
    final work = context.read<WorkController>();
    final parent = value == null ? null : work.taskById(value);
    setState(() {
      _parentTaskId = value;
      if (parent != null) {
        _projectId = parent.projectId;
        _areaId = work.areaForTask(parent);
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _formError = null;
    });
    if (!_formKey.currentState!.validate()) {
      _titleFocus.requestFocus();
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        parseDayKey(_dueDate!).epochDay < parseDayKey(_startDate!).epochDay) {
      setState(() => _formError = context.l10n.work_error_date_order);
      return;
    }
    final manual = _progressMode == WorkTaskProgress.manual;
    final progress = manual
        ? double.tryParse(_progress.text.trim().replaceAll(',', '.'))
        : widget.task?.progress ?? 0;
    if (manual &&
        (progress == null ||
            !progress.isFinite ||
            progress < 0 ||
            progress > 100)) {
      setState(() => _formError = context.l10n.work_error_invalid_progress);
      return;
    }
    if (manual && _status == WorkTaskStatus.done && progress != 100) {
      setState(() => _formError = context.l10n.work_error_manual_done_progress);
      return;
    }
    final estimate = _estimate.text.trim().isEmpty
        ? null
        : int.tryParse(_estimate.text.trim());
    if (_estimate.text.trim().isNotEmpty &&
        (estimate == null || estimate < 0)) {
      setState(() => _formError = context.l10n.work_error_invalid_estimate);
      return;
    }
    final focusMinutes = int.tryParse(_focusMinutes.text.trim());
    final breakMinutes = int.tryParse(_breakMinutes.text.trim());
    if (focusMinutes == null ||
        focusMinutes < 0 ||
        focusMinutes > 600 ||
        breakMinutes == null ||
        breakMinutes < 0 ||
        breakMinutes > 120) {
      setState(() => _formError = context.l10n.work_time_defaults_error);
      return;
    }

    setState(() => _saving = true);
    final existing = widget.task;
    await runWorkAction(
      context,
      () async {
        final draft = existing == null
            ? WorkTask(
                meta: WorkController.newMeta(),
                title: _title.text.trim(),
                areaId: _areaId,
                projectId: _projectId,
                parentTaskId: _parentTaskId,
                status: _status,
                progressMode: _hasChildren
                    ? WorkTaskProgress.completion
                    : _progressMode,
                progress: manual ? progress! : 0,
                description: _description.text.trim(),
                completionCriteria: _criteria.text.trim(),
                blockedReason: _blockedReason.text.trim(),
                priority: _priority,
                startDate: _startDate,
                dueDate: _dueDate,
                dueMinute: _dueMinute,
                timeZone: DateTime.now().timeZoneName,
                estimatedMinutes: estimate,
                focusMinutes: focusMinutes,
                breakMinutes: focusMinutes == 0 ? 0 : breakMinutes,
                tags: _splitValues(_tags.text),
                links: _splitValues(_links.text, commaSeparated: false),
                photos: _photos,
              )
            : existing.copyWith(
                title: _title.text.trim(),
                clearCompletedAt: _status != WorkTaskStatus.done,
                areaId: _areaId,
                clearArea: _areaId == null,
                projectId: _projectId,
                clearProject: _projectId == null,
                parentTaskId: _parentTaskId,
                clearParent: _parentTaskId == null,
                status: _status,
                progressMode: _hasChildren
                    ? WorkTaskProgress.completion
                    : _progressMode,
                progress: manual ? progress! : existing.progress,
                description: _description.text.trim(),
                completionCriteria: _criteria.text.trim(),
                blockedReason: _blockedReason.text.trim(),
                priority: _priority,
                startDate: _startDate,
                clearStart: _startDate == null,
                dueDate: _dueDate,
                clearDue: _dueDate == null,
                dueMinute: _dueMinute,
                clearDueMinute: _dueMinute == null,
                timeZone: existing.timeZone.isEmpty
                    ? DateTime.now().timeZoneName
                    : existing.timeZone,
                estimatedMinutes: estimate,
                focusMinutes: focusMinutes,
                breakMinutes: focusMinutes == 0 ? 0 : breakMinutes,
                clearEstimate: estimate == null,
                tags: _splitValues(_tags.text),
                links: _splitValues(_links.text, commaSeparated: false),
                photos: _photos,
              );
        final saved = await context.read<WorkController>().saveTask(
          draft,
          expectedRevision: existing?.meta.revision,
        );
        if (!mounted) return;
        Navigator.of(context).pop(saved);
      },
      onError: (error) {
        if (!mounted) return;
        final message = workErrorMessage(context, error);
        setState(() {
          _saving = false;
          _formError = message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final areas = context.watch<WorkController>().areas();
    final parentSelected = _parentTaskId != null;
    final disableScope = parentSelected;
    final allowManual = !_hasChildren;
    return _WorkFormScaffold(
      title: widget.task == null
          ? (_parentTaskId == null
                ? context.l10n.work_add_task
                : context.l10n.work_add_subtask)
          : context.l10n.work_edit_task,
      saving: _saving,
      formError: _formError,
      onSave: _save,
      children: [
        Form(
          key: _formKey,
          autovalidateMode: _submitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkSection(
                title: context.l10n.work_basics,
                child: WorkCard(
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('work-task-title-field'),
                        controller: _title,
                        focusNode: _titleFocus,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_title,
                          hintText: context.l10n.work_task_name_hint,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? context.l10n.work_title_required
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: _areaId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_area,
                          helperText: disableScope
                              ? context.l10n.work_scope_inherited_from_parent
                              : null,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.work_scope_inbox),
                          ),
                          for (final area in areas)
                            DropdownMenuItem<String?>(
                              value: area.id,
                              child: Text(area.name),
                            ),
                        ],
                        onChanged: disableScope ? null : _onAreaChanged,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: _projectId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_project,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.work_scope_unassigned),
                          ),
                          for (final project in _projects)
                            DropdownMenuItem<String?>(
                              value: project.id,
                              child: Text(project.name),
                            ),
                        ],
                        onChanged: disableScope ? null : _onProjectChanged,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: _parentTaskId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_parent_task,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.work_no_parent_task),
                          ),
                          for (final task in _parents)
                            DropdownMenuItem<String?>(
                              value: task.id,
                              child: Text(task.title),
                            ),
                        ],
                        onChanged: _onParentChanged,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<WorkTaskStatus>(
                        initialValue: _status,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.status,
                        ),
                        items: [
                          for (final value in WorkTaskStatus.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(workTaskStatusLabel(context, value)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _status = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TodoPriority>(
                        initialValue: _priority,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.todo_priority,
                        ),
                        items: [
                          for (final value in TodoPriority.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(
                                todoPriorityLabels(context)[value.index],
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _priority = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_progress,
                child: WorkCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<WorkTaskProgress>(
                        initialValue: allowManual
                            ? _progressMode
                            : WorkTaskProgress.completion,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_progress_mode,
                          helperText: allowManual
                              ? null
                              : context.l10n.work_progress_from_subtasks,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: WorkTaskProgress.completion,
                            child: Text(
                              context.l10n.work_progress_mode_completion,
                            ),
                          ),
                          DropdownMenuItem(
                            value: WorkTaskProgress.manual,
                            child: Text(context.l10n.work_progress_mode_manual),
                          ),
                        ],
                        onChanged: allowManual
                            ? (value) {
                                if (value != null) {
                                  setState(() => _progressMode = value);
                                }
                              }
                            : null,
                      ),
                      if (allowManual &&
                          _progressMode == WorkTaskProgress.manual) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _progress,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: context.l10n.work_manual_progress,
                            hintText: '0-100',
                            suffixText: '%',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_details,
                child: WorkCard(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _description,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: context.l10n.description,
                          hintText: context.l10n.work_task_description_hint,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _criteria,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_completion_criteria,
                          hintText: context.l10n.work_completion_criteria_hint,
                        ),
                      ),
                      if (_status == WorkTaskStatus.blocked) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _blockedReason,
                          minLines: 2,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: context.l10n.work_blocked_reason,
                            hintText: context.l10n.work_blocked_reason_hint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_schedule,
                child: WorkCard(
                  child: Column(
                    children: [
                      _DateField(
                        label: context.l10n.work_start_date,
                        value: _startDate,
                        onPick: _saving ? null : () => _pickDate(due: false),
                        onClear: _startDate == null
                            ? null
                            : () => setState(() => _startDate = null),
                      ),
                      const SizedBox(height: 12),
                      _DateField(
                        label: context.l10n.work_due_date,
                        value: _dueDate,
                        onPick: _saving ? null : () => _pickDate(due: true),
                        onClear: _dueDate == null
                            ? null
                            : () => setState(() {
                                _dueDate = null;
                                _dueMinute = null;
                              }),
                      ),
                      const SizedBox(height: 12),
                      _TimeField(
                        label: context.l10n.work_due_time,
                        minute: _dueMinute,
                        onPick: _saving ? null : _pickTime,
                        onClear: _dueMinute == null
                            ? null
                            : () => setState(() => _dueMinute = null),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _estimate,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_effort_estimate,
                          hintText: context.l10n.work_effort_estimate_hint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_focus_defaults,
                child: WorkCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.l10n.work_focus_defaults_hint,
                        style: sheetBodyStyle(context),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('work-focus-minutes'),
                        controller: _focusMinutes,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_time_focus_minutes,
                          helperText: context.l10n.work_time_focus_zero,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('work-break-minutes'),
                        controller: _breakMinutes,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_time_break_minutes,
                          helperText: context.l10n.work_time_break_zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.note_photos,
                child: WorkCard(
                  child: WorkPhotoStrip(
                    photos: _photos,
                    accent: context.colors.primary,
                    onCamera: _saving
                        ? () {}
                        : () => _addPhoto(fromCamera: true),
                    onGallery: _saving ? () {} : _addPhoto,
                    onRemove: (path) => setState(() => _photos.remove(path)),
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_tags,
                child: WorkCard(
                  child: TextFormField(
                    controller: _tags,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: context.l10n.work_tags,
                      hintText: context.l10n.work_tags_hint,
                    ),
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_links,
                child: WorkCard(
                  child: TextFormField(
                    controller: _links,
                    minLines: 2,
                    maxLines: 5,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: context.l10n.work_links,
                      hintText: context.l10n.work_links_hint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String? value;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPick,
      icon: const Icon(LucideIcons.calendarDays, size: 18),
      label: Row(
        children: [
          Expanded(
            child: Text(
              value == null
                  ? context.l10n.work_none_selected(label)
                  : '$label: ${workDateLabel(context, value)}',
              textAlign: TextAlign.start,
            ),
          ),
          if (value != null)
            IconButton(
              tooltip: context.l10n.delete,
              onPressed: onClear,
              icon: const Icon(LucideIcons.x, size: 16),
            ),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.minute,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final int? minute;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final text = minute == null
        ? context.l10n.work_none_selected(label)
        : '$label: ${TimeOfDay(hour: minute! ~/ 60, minute: minute! % 60).format(context)}';
    return OutlinedButton.icon(
      onPressed: onPick,
      icon: const Icon(LucideIcons.clock, size: 18),
      label: Row(
        children: [
          Expanded(child: Text(text, textAlign: TextAlign.start)),
          if (minute != null)
            IconButton(
              tooltip: context.l10n.delete,
              onPressed: onClear,
              icon: const Icon(LucideIcons.x, size: 16),
            ),
        ],
      ),
    );
  }
}

String _iconLabel(String value) {
  final result = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (i > 0 && char.toUpperCase() == char && char != char.toLowerCase()) {
      result.write(' ');
    }
    result.write(i == 0 ? char.toUpperCase() : char);
  }
  return result.toString();
}

String _joinList(List<String> values) => values.join(', ');
String _joinLines(List<String> values) => values.join('\n');

List<String> _splitValues(String value, {bool commaSeparated = true}) {
  final parts = value
      .split(commaSeparated ? RegExp(r'[\n,]') : '\n')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty);
  final result = <String>[];
  final seen = <String>{};
  for (final item in parts) {
    if (seen.add(item)) result.add(item);
  }
  return result;
}

String _formatProgress(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();
