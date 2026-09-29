import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/app_confirm_dialog.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/goals/widgets/goal_ui.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

Future<Goal?> showGoalForm(
  BuildContext context, {
  Goal? goal,
  GoalScope scope = GoalScope.personal,
  String? areaId,
  String? projectId,
  String? habitId,
  String? taskId,
}) {
  final child = _GoalForm(
    goal: goal,
    scope: goal?.scope ?? scope,
    areaId: goal?.areaId ?? areaId,
    projectId: goal?.projectId ?? projectId,
    habitId: habitId,
    taskId: taskId,
  );
  if (isWideLayout(context)) {
    return AppNavigator.push<Goal?>(child, fade: true);
  }
  return showModalBottomSheet<Goal>(
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

class _GoalForm extends StatefulWidget {
  const _GoalForm({
    this.goal,
    required this.scope,
    this.areaId,
    this.projectId,
    this.habitId,
    this.taskId,
  });

  final Goal? goal;
  final GoalScope scope;
  final String? areaId;
  final String? projectId;
  final String? habitId;
  final String? taskId;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  final _baselineFocus = FocusNode();
  final _currentFocus = FocusNode();
  final _targetFocus = FocusNode();
  final _unitFocus = FocusNode();
  final _currencyFocus = FocusNode();

  late final TextEditingController _title = TextEditingController(
    text: widget.goal?.title ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.goal?.description ?? '',
  );
  late final TextEditingController _why = TextEditingController(
    text: widget.goal?.why ?? '',
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.goal?.category ?? '',
  );
  late final TextEditingController _baseline = TextEditingController(
    text: _initialNumber(widget.goal?.baseline ?? 0),
  );
  late final TextEditingController _current = TextEditingController(
    text: _initialNumber(widget.goal?.current ?? 0),
  );
  late final TextEditingController _target = TextEditingController(
    text: _initialNumber(widget.goal?.target ?? 1),
  );
  late final TextEditingController _unit = TextEditingController(
    text: widget.goal?.unit ?? _defaultUnit(),
  );
  late final TextEditingController _currency = TextEditingController(
    text: widget.goal?.currency ?? '',
  );

  late GoalScope _scope = widget.scope;
  late final GoalStatus _status = widget.goal?.status ?? GoalStatus.notStarted;
  late GoalSource _source = widget.goal?.source ?? GoalSource.manual;
  late GoalMeasurement _measurement =
      widget.goal?.measurement ?? GoalMeasurement.completion;
  late String? _areaId = widget.areaId;
  late String? _projectId = widget.projectId;
  late String? _startDate = widget.goal?.startDate;
  late String? _endDate = widget.goal?.endDate;
  late Set<String> _projectIds = {...?widget.goal?.projectIds};
  late Set<String> _taskIds = {
    ...?widget.goal?.taskIds,
    if (widget.taskId != null) widget.taskId!,
  };
  bool _saving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    if (_source == GoalSource.work) _applyWorkDefaults(clearSelection: false);
    if (_source == GoalSource.habits &&
        _measurement == GoalMeasurement.completion) {
      _measurement = GoalMeasurement.number;
      _unit.text = 'days';
      _target.text = '30';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _why.dispose();
    _category.dispose();
    _baseline.dispose();
    _current.dispose();
    _target.dispose();
    _unit.dispose();
    _currency.dispose();
    _titleFocus.dispose();
    _baselineFocus.dispose();
    _currentFocus.dispose();
    _targetFocus.dispose();
    _unitFocus.dispose();
    _currencyFocus.dispose();
    super.dispose();
  }

  String _defaultUnit() => widget.goal?.measurement == GoalMeasurement.number
      ? widget.goal!.unit
      : '';

  Future<void> _changeScope(GoalScope value) async {
    if (value == _scope) return;
    final clearsWork =
        value == GoalScope.personal &&
        (_areaId != null ||
            _projectId != null ||
            _projectIds.isNotEmpty ||
            _taskIds.isNotEmpty ||
            _source == GoalSource.work);
    if (clearsWork) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: context.l10n.goal_scope,
        message: context.l10n.goal_switch_personal_body,
        confirmLabel: context.l10n.goal_switch_personal,
        icon: LucideIcons.user,
        danger: false,
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _scope = value;
      if (_scope == GoalScope.personal) {
        if (_source == GoalSource.work) _source = GoalSource.manual;
        _areaId = null;
        _projectId = null;
        _projectIds.clear();
        _taskIds.clear();
      }
      _formError = null;
    });
  }

  void _changeSource(GoalSource value) {
    setState(() {
      _source = value;
      if (_source == GoalSource.work) {
        _scope = GoalScope.work;
        _applyWorkDefaults(clearSelection: false);
      } else if (_source == GoalSource.habits) {
        if (_measurement == GoalMeasurement.completion) {
          _measurement = GoalMeasurement.number;
          _baseline.text = '0';
          _current.text = '0';
          _target.text = '30';
          _unit.text = 'days';
          _currency.clear();
        }
      }
      _formError = null;
    });
  }

  void _changeMeasurement(GoalMeasurement value) {
    setState(() {
      _measurement = value;
      if (value == GoalMeasurement.completion) {
        _baseline.text = '0';
        _current.text = _status == GoalStatus.achieved ? '1' : '0';
        _target.text = '1';
        _unit.clear();
        _currency.clear();
      } else if (value == GoalMeasurement.percentage) {
        _baseline.text = '0';
        _target.text = '100';
        if ((_parse(_current.text) ?? 0) > 100) _current.text = '0';
        _unit.clear();
        _currency.clear();
      } else if (value == GoalMeasurement.number) {
        if (_unit.text.trim().isEmpty) _unit.text = 'days';
        _currency.clear();
      } else if (value == GoalMeasurement.currency) {
        final code = _currency.text.trim().toUpperCase();
        _currency.text = RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : 'USD';
        _unit.text = _currency.text;
      }
      _formError = null;
    });
  }

  void _applyWorkDefaults({required bool clearSelection}) {
    _measurement = GoalMeasurement.percentage;
    _baseline.text = '0';
    _current.text = '0';
    _target.text = '100';
    _unit.clear();
    _currency.clear();
    if (clearSelection) {
      _projectIds.clear();
      _taskIds.clear();
    } else if (widget.goal == null && _projectIds.isEmpty && _taskIds.isEmpty) {
      if (widget.taskId != null) {
        _taskIds.add(widget.taskId!);
      } else if (widget.projectId != null) {
        _projectIds.add(widget.projectId!);
      }
    }
  }

  Future<void> _pickDate({required bool end}) async {
    final current = end ? _endDate : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null ? AppClock.today() : parseDayKey(current),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (end) {
        _endDate = picked.dayKey;
      } else {
        _startDate = picked.dayKey;
      }
      _formError = null;
    });
  }

  bool _hasWorkScopeConflict(WorkController work) {
    if (_scope != GoalScope.work) return false;
    final contextProject = _projectId == null
        ? null
        : work.projectById(_projectId!);
    if (_areaId != null &&
        contextProject != null &&
        contextProject.areaId != _areaId) {
      return true;
    }
    for (final id in _projectIds) {
      final project = work.projectById(id);
      if (project != null &&
          ((_areaId != null && project.areaId != _areaId) ||
              (_projectId != null && project.id != _projectId))) {
        return true;
      }
    }
    for (final id in _taskIds) {
      final task = work.taskById(id);
      if (task != null &&
          ((_areaId != null && work.areaForTask(task) != _areaId) ||
              (_projectId != null && task.projectId != _projectId))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _selectWorkContributors() async {
    final result = await showDialog<_WorkSelection>(
      context: context,
      builder: (_) => _WorkContributorDialog(
        areaId: _areaId,
        projectId: _projectId,
        projectIds: _projectIds,
        taskIds: _taskIds,
        measured: _source == GoalSource.work,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _projectIds = result.projectIds;
      _taskIds = result.taskIds;
      _formError = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _formError = null;
    });
    final work = context.read<WorkController>();
    if (!_formKey.currentState!.validate()) {
      _focusFirstInvalid();
      return;
    }
    if (_hasWorkScopeConflict(work)) {
      setState(() => _formError = context.l10n.goal_work_scope_conflict);
      return;
    }
    if (_startDate != null &&
        _endDate != null &&
        parseDayKey(_endDate!).isBefore(parseDayKey(_startDate!))) {
      setState(() => _formError = context.l10n.goal_invalid_dates);
      return;
    }
    final existing = widget.goal;
    late final Goal draft;
    try {
      draft = _buildGoal(existing);
    } on ArgumentError catch (error) {
      setState(() => _formError = goalErrorMessage(context, error));
      _focusFirstInvalid();
      return;
    } on StateError catch (error) {
      setState(() => _formError = goalErrorMessage(context, error));
      _focusFirstInvalid();
      return;
    }

    final goals = context.read<GoalsController>();
    final habit = widget.habitId == null
        ? null
        : goals.habits.byId(widget.habitId!);
    if (widget.habitId != null && existing == null && habit == null) {
      setState(() => _formError = context.l10n.glink_missing_habit);
      return;
    }
    final links = habit == null || existing != null
        ? null
        : [
            GoalHabitLink.forHabit(
              meta: WorkController.newMeta(),
              goalId: draft.id,
              habit: habit,
              role: GoalHabitRole.supporting,
            ),
          ];
    setState(() => _saving = true);
    await runGoalAction(
      context,
      () async {
        final saved = await goals.saveGoal(
          draft,
          expectedRevision: existing?.meta.revision,
          links: links,
        );
        if (mounted) Navigator.of(context).pop(saved);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _formError = goalErrorMessage(context, error);
        });
      },
    );
  }

  Goal _buildGoal(Goal? existing) {
    final measurement = _source == GoalSource.work
        ? GoalMeasurement.percentage
        : _measurement;
    final currency = measurement == GoalMeasurement.currency
        ? _currency.text.trim().toUpperCase()
        : '';
    final unit = switch (measurement) {
      GoalMeasurement.completion || GoalMeasurement.percentage => '',
      GoalMeasurement.number => _unit.text.trim(),
      GoalMeasurement.currency => currency,
    };
    final baseline = measurement == GoalMeasurement.completion
        ? 0.0
        : (_source == GoalSource.work ? 0.0 : _parse(_baseline.text)!);
    final current = measurement == GoalMeasurement.completion
        ? (_status == GoalStatus.achieved ? 1.0 : _parse(_current.text) ?? 0.0)
        : (_source == GoalSource.work
              ? (existing?.source == GoalSource.work ? existing!.current : 0.0)
              : _parse(_current.text)!);
    final target = measurement == GoalMeasurement.completion
        ? 1.0
        : (_source == GoalSource.work ? 100.0 : _parse(_target.text)!);
    if (existing == null) {
      return Goal(
        meta: WorkController.newMeta(),
        title: _title.text.trim(),
        scope: _scope,
        status: _status,
        measurement: measurement,
        source: _source,
        areaId: _scope == GoalScope.work ? _areaId : null,
        projectId: _scope == GoalScope.work ? _projectId : null,
        description: _description.text.trim(),
        category: _category.text.trim(),
        why: _why.text.trim(),
        baseline: baseline,
        current: current,
        target: target,
        unit: unit,
        currency: currency,
        startDate: _startDate,
        endDate: _endDate,
        taskIds: _taskIds.toList(),
        projectIds: _projectIds.toList(),
      );
    }
    return existing.copyWith(
      title: _title.text.trim(),
      scope: _scope,
      status: _status,
      measurement: measurement,
      source: _source,
      areaId: _scope == GoalScope.work ? _areaId : null,
      projectId: _scope == GoalScope.work ? _projectId : null,
      clearAreaId: _scope == GoalScope.personal || _areaId == null,
      clearProjectId: _scope == GoalScope.personal || _projectId == null,
      description: _description.text.trim(),
      category: _category.text.trim(),
      why: _why.text.trim(),
      baseline: baseline,
      current: current,
      target: target,
      unit: unit,
      currency: currency,
      startDate: _startDate,
      endDate: _endDate,
      clearStartDate: _startDate == null,
      clearEndDate: _endDate == null,
      taskIds: _taskIds.toList(),
      projectIds: _projectIds.toList(),
    );
  }

  void _focusFirstInvalid() {
    if (_title.text.trim().isEmpty) {
      _titleFocus.requestFocus();
      return;
    }
    if (_source != GoalSource.work &&
        _measurement != GoalMeasurement.completion) {
      if (_parse(_baseline.text) == null) {
        _baselineFocus.requestFocus();
        return;
      }
      if (_parse(_current.text) == null) {
        _currentFocus.requestFocus();
        return;
      }
      if (_parse(_target.text) == null ||
          _parse(_target.text) == _parse(_baseline.text)) {
        _targetFocus.requestFocus();
        return;
      }
      if (_measurement == GoalMeasurement.number && _unit.text.trim().isEmpty) {
        _unitFocus.requestFocus();
        return;
      }
      if (_measurement == GoalMeasurement.currency &&
          !RegExp(
            r'^[A-Z]{3}$',
          ).hasMatch(_currency.text.trim().toUpperCase())) {
        _currencyFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    if (_scope == GoalScope.personal) {
      _areaId = null;
      _projectId = null;
    }
    final title = widget.goal == null
        ? context.l10n.goal_add
        : context.l10n.goal_edit;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(title),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
          children: [
            WorkPageHeader(title: title),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Material(
                  color: context.tokens.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _formError!,
                      style: sheetBodyStyle(
                        context,
                        size: 14,
                        color: context.tokens.danger,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            WorkSection(
              title: context.l10n.work_basics,
              child: WorkCard(
                child: Column(
                  children: [
                    TextFormField(
                      key: const ValueKey('goal-title-field'),
                      controller: _title,
                      focusNode: _titleFocus,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: context.l10n.goal_title,
                        hintText: context.l10n.goal_title_hint,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? context.l10n.goal_title_required
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _description,
                      minLines: 2,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: context.l10n.goal_description,
                        hintText: context.l10n.goal_description_hint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _why,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: context.l10n.goal_why,
                        hintText: context.l10n.goal_why_hint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _category,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: context.l10n.goal_category,
                        hintText: context.l10n.goal_category_hint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            WorkSection(
              title: context.l10n.goal_scope,
              child: WorkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GoalScopeSelector(
                      scope: _scope,
                      onChanged: _saving ? null : _changeScope,
                    ),
                    if (_scope == GoalScope.work) ...[
                      const SizedBox(height: 12),
                      _WorkContextFields(
                        areaId: _areaId,
                        projectId: _projectId,
                        onAreaChanged: (value) => setState(() {
                          _areaId = value;
                          final selectedProject = work.projectById(
                            _projectId ?? '',
                          );
                          if (selectedProject != null &&
                              selectedProject.areaId != value) {
                            _projectId = null;
                          }
                          _formError = null;
                        }),
                        onProjectChanged: (value) => setState(() {
                          _projectId = value;
                          final project = value == null
                              ? null
                              : work.projectById(value);
                          if (project != null) _areaId = project.areaId;
                          _formError = null;
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            WorkSection(
              title: context.l10n.goal_source,
              child: WorkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<GoalSource>(
                      key: const ValueKey('goal-source-field'),
                      initialValue: _source,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.goal_source,
                      ),
                      items: [
                        for (final source in GoalSource.values)
                          DropdownMenuItem(
                            value: source,
                            child: Text(goalSourceLabel(context, source)),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => _changeSource(value!),
                    ),
                    const SizedBox(height: 8),
                    Text(_sourceHint(context), style: sheetBodyStyle(context)),
                  ],
                ),
              ),
            ),
            if (_scope == GoalScope.work ||
                _projectIds.isNotEmpty ||
                _taskIds.isNotEmpty)
              WorkSection(
                title: _source == GoalSource.work
                    ? context.l10n.goal_work_items
                    : context.l10n.goal_related_work,
                child: WorkCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _source == GoalSource.work
                            ? context.l10n.goal_work_items_hint
                            : context.l10n.goal_related_work_hint,
                        style: sheetBodyStyle(context),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _selectWorkContributors,
                        icon: const Icon(LucideIcons.listChecks, size: 18),
                        label: Text(
                          _source == GoalSource.work
                              ? context.l10n.goal_select_work_items
                              : context.l10n.goal_select_related_work,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _workSelectionLabel(context, work),
                        style: sheetBodyStyle(context, size: 13.5),
                      ),
                    ],
                  ),
                ),
              ),
            WorkSection(
              title: context.l10n.goal_measurement,
              child: WorkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_source == GoalSource.work)
                      Text(
                        context.l10n.goal_work_measurement_hint,
                        style: sheetBodyStyle(context),
                      )
                    else ...[
                      DropdownButtonFormField<GoalMeasurement>(
                        key: const ValueKey('goal-measurement-field'),
                        initialValue: _measurement,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.goal_measurement,
                        ),
                        items: [
                          for (final value in GoalMeasurement.values)
                            if (!(_source == GoalSource.habits &&
                                value == GoalMeasurement.completion))
                              DropdownMenuItem(
                                value: value,
                                child: Text(
                                  goalMeasurementLabel(context, value),
                                ),
                              ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => _changeMeasurement(value!),
                      ),
                      const SizedBox(height: 12),
                      if (_measurement == GoalMeasurement.completion)
                        Text(
                          context.l10n.goal_manual_completion_hint,
                          style: sheetBodyStyle(context),
                        )
                      else
                        _NumberFields(
                          measurement: _measurement,
                          baseline: _baseline,
                          current: _current,
                          target: _target,
                          unit: _unit,
                          currency: _currency,
                          baselineFocus: _baselineFocus,
                          currentFocus: _currentFocus,
                          targetFocus: _targetFocus,
                          unitFocus: _unitFocus,
                          currencyFocus: _currencyFocus,
                          showCurrent: _source == GoalSource.manual,
                        ),
                      if (_source == GoalSource.habits) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.goal_habit_unit_hint,
                          style: sheetBodyStyle(context),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            WorkSection(
              title: context.l10n.work_schedule,
              child: WorkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GoalDateButton(
                      label: _startDate == null
                          ? context.l10n.goal_no_start_date
                          : workDateLabel(context, _startDate),
                      tooltip: context.l10n.goal_pick_start_date,
                      onPressed: _saving ? null : () => _pickDate(end: false),
                      onClear: _startDate == null
                          ? null
                          : () => setState(() => _startDate = null),
                    ),
                    const SizedBox(height: 8),
                    _GoalDateButton(
                      label: _endDate == null
                          ? context.l10n.goal_no_end_date
                          : workDateLabel(context, _endDate),
                      tooltip: context.l10n.goal_pick_end_date,
                      onPressed: _saving ? null : () => _pickDate(end: true),
                      onClear: _endDate == null
                          ? null
                          : () => setState(() => _endDate = null),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceHint(BuildContext context) => switch (_source) {
    GoalSource.manual => context.l10n.goal_source_manual_hint,
    GoalSource.habits => context.l10n.goal_source_habits_hint,
    GoalSource.work => context.l10n.goal_source_work_hint,
  };

  String _workSelectionLabel(BuildContext context, WorkController work) {
    final names = <String>[
      for (final id in _projectIds)
        if (work.projectById(id) != null) work.projectById(id)!.name,
      for (final id in _taskIds)
        if (work.taskById(id) != null) work.taskById(id)!.title,
    ];
    return names.isEmpty
        ? context.l10n.goal_work_items_empty
        : names.join(' • ');
  }
}

class _NumberFields extends StatelessWidget {
  const _NumberFields({
    required this.measurement,
    required this.baseline,
    required this.current,
    required this.target,
    required this.unit,
    required this.currency,
    required this.baselineFocus,
    required this.currentFocus,
    required this.targetFocus,
    required this.unitFocus,
    required this.currencyFocus,
    required this.showCurrent,
  });

  final GoalMeasurement measurement;
  final TextEditingController baseline;
  final TextEditingController current;
  final TextEditingController target;
  final TextEditingController unit;
  final TextEditingController currency;
  final FocusNode baselineFocus;
  final FocusNode currentFocus;
  final FocusNode targetFocus;
  final FocusNode unitFocus;
  final FocusNode currencyFocus;
  final bool showCurrent;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              _NumberField(
                controller: baseline,
                focusNode: baselineFocus,
                label: context.l10n.goal_baseline,
                measurement: measurement,
              ),
              if (showCurrent)
                _NumberField(
                  controller: current,
                  focusNode: currentFocus,
                  label: context.l10n.goal_current,
                  measurement: measurement,
                ),
            ];
            if (!showCurrent) return fields.single;
            if (constraints.maxWidth < 420) {
              return Column(
                children: [
                  fields.first,
                  const SizedBox(height: 12),
                  fields.last,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: fields.first),
                const SizedBox(width: 10),
                Expanded(child: fields.last),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _NumberField(
          controller: target,
          focusNode: targetFocus,
          label: context.l10n.goal_target,
          measurement: measurement,
          otherValue: baseline,
        ),
        if (measurement == GoalMeasurement.number) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: unit,
            focusNode: unitFocus,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: context.l10n.goal_unit,
              hintText: context.l10n.goal_unit_hint,
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? context.l10n.goal_invalid_unit
                : null,
          ),
        ],
        if (measurement == GoalMeasurement.currency) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: currency,
            focusNode: currencyFocus,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: InputDecoration(
              labelText: context.l10n.goal_currency,
              hintText: context.l10n.goal_currency_hint,
            ),
            validator: (value) =>
                RegExp(
                  r'^[A-Z]{3}$',
                ).hasMatch((value ?? '').trim().toUpperCase())
                ? null
                : context.l10n.goal_invalid_currency,
          ),
        ],
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.measurement,
    this.otherValue,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final GoalMeasurement measurement;
  final TextEditingController? otherValue;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final parsed = _parse(value ?? '');
        if (parsed == null) return context.l10n.goal_invalid_number;
        if (measurement == GoalMeasurement.percentage &&
            (parsed < 0 || parsed > 100)) {
          return context.l10n.goal_invalid_percentage;
        }
        final other = otherValue == null ? null : _parse(otherValue!.text);
        if (other != null && other == parsed) {
          return context.l10n.goal_invalid_target;
        }
        return null;
      },
    );
  }
}

class _GoalDateButton extends StatelessWidget {
  const _GoalDateButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    required this.onClear,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: tooltip,
            child: OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(LucideIcons.calendarDays, size: 18),
              label: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(label),
              ),
            ),
          ),
        ),
        if (onClear != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: context.l10n.goal_clear_date,
            onPressed: onClear,
            icon: const Icon(LucideIcons.x, size: 18),
          ),
        ],
      ],
    );
  }
}

class _WorkContextFields extends StatelessWidget {
  const _WorkContextFields({
    required this.areaId,
    required this.projectId,
    required this.onAreaChanged,
    required this.onProjectChanged,
  });

  final String? areaId;
  final String? projectId;
  final ValueChanged<String?> onAreaChanged;
  final ValueChanged<String?> onProjectChanged;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final areas = work.data.areas
        .where(
          (area) => area.id == areaId || (!area.isDeleted && !area.isArchived),
        )
        .toList();
    final projects = work.data.projects
        .where(
          (project) =>
              project.id == projectId ||
              (!project.isDeleted &&
                  !work.isProjectArchived(project) &&
                  (areaId == null || project.areaId == areaId)),
        )
        .toList();
    return Column(
      children: [
        DropdownButtonFormField<String?>(
          key: ValueKey('goal-form-area-$areaId'),
          initialValue: areaId,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.l10n.work_area),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(context.l10n.work_scope_unassigned),
            ),
            for (final area in areas)
              DropdownMenuItem(value: area.id, child: Text(area.name)),
          ],
          onChanged: onAreaChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: ValueKey('goal-form-project-$projectId-$areaId'),
          initialValue: projects.any((project) => project.id == projectId)
              ? projectId
              : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.l10n.work_project),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(context.l10n.work_scope_unassigned),
            ),
            for (final project in projects)
              DropdownMenuItem(value: project.id, child: Text(project.name)),
          ],
          onChanged: onProjectChanged,
        ),
      ],
    );
  }
}

class _WorkContributorDialog extends StatefulWidget {
  const _WorkContributorDialog({
    required this.areaId,
    required this.projectId,
    required this.projectIds,
    required this.taskIds,
    required this.measured,
  });

  final String? areaId;
  final String? projectId;
  final Set<String> projectIds;
  final Set<String> taskIds;
  final bool measured;

  @override
  State<_WorkContributorDialog> createState() => _WorkContributorDialogState();
}

class _WorkContributorDialogState extends State<_WorkContributorDialog> {
  late final Set<String> _projectIds = {...widget.projectIds};
  late final Set<String> _taskIds = {...widget.taskIds};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final term = _query.trim().toLowerCase();
    final projects = work.data.projects
        .where(
          (project) =>
              _projectIds.contains(project.id) ||
              (!project.isDeleted &&
                  !work.isProjectArchived(project) &&
                  (widget.areaId == null || project.areaId == widget.areaId) &&
                  (widget.projectId == null || project.id == widget.projectId)),
        )
        .where((project) => project.name.toLowerCase().contains(term))
        .toList();
    final tasks = work.data.tasks
        .where(
          (task) =>
              _taskIds.contains(task.id) ||
              (!task.isDeleted &&
                  !work.isTaskArchived(task) &&
                  task.status != WorkTaskStatus.cancelled &&
                  (widget.areaId == null ||
                      work.areaForTask(task) == widget.areaId) &&
                  (widget.projectId == null ||
                      task.projectId == widget.projectId)),
        )
        .where((task) {
          final text =
              '${task.title}\n${workTaskContextLabel(context, work, task)}';
          return text.toLowerCase().contains(term);
        })
        .toList();
    return AlertDialog(
      title: Text(
        widget.measured
            ? context.l10n.goal_select_work_items
            : context.l10n.goal_select_related_work,
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.goal_search_work,
                prefixIcon: const Icon(LucideIcons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.goal_work_retained,
              style: sheetBodyStyle(context, size: 13),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (projects.isEmpty && tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(context.l10n.goal_no_work_results),
                    ),
                  if (projects.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        context.l10n.goal_work_select_project,
                        style: sheetLabelStyle(context),
                      ),
                    ),
                  for (final project in projects)
                    _ProjectCheckTile(
                      project: project,
                      selected: _projectIds.contains(project.id),
                      disabled:
                          widget.measured &&
                          !_projectIds.contains(project.id) &&
                          _taskIds
                              .map(work.taskById)
                              .whereType<WorkTask>()
                              .any((task) => task.projectId == project.id),
                      onChanged: (selected) => setState(() {
                        if (selected) {
                          _projectIds.add(project.id);
                        } else {
                          _projectIds.remove(project.id);
                        }
                      }),
                    ),
                  if (tasks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        context.l10n.goal_work_select_task,
                        style: sheetLabelStyle(context),
                      ),
                    ),
                  for (final task in tasks)
                    _TaskCheckTile(
                      task: task,
                      selected: _taskIds.contains(task.id),
                      disabled: _disabledReason(context, work, task) != null,
                      reason: _disabledReason(context, work, task),
                      onChanged: (selected) => setState(() {
                        if (selected) {
                          _taskIds.add(task.id);
                        } else {
                          _taskIds.remove(task.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _WorkSelection(projectIds: _projectIds, taskIds: _taskIds),
          ),
          child: Text(context.l10n.done),
        ),
      ],
    );
  }

  String? _disabledReason(
    BuildContext context,
    WorkController work,
    WorkTask task,
  ) {
    if (!widget.measured || _taskIds.contains(task.id)) return null;
    if (task.projectId != null && _projectIds.contains(task.projectId)) {
      return context.l10n.goal_work_duplicate_context;
    }
    if (task.parentTaskId != null && _taskIds.contains(task.parentTaskId)) {
      return context.l10n.goal_work_duplicate_context;
    }
    final selectedChildren = _taskIds
        .map(work.taskById)
        .whereType<WorkTask>()
        .any((selected) => selected.parentTaskId == task.id);
    if (selectedChildren) return context.l10n.goal_work_duplicate_context;
    return null;
  }
}

class _ProjectCheckTile extends StatelessWidget {
  const _ProjectCheckTile({
    required this.project,
    required this.selected,
    required this.disabled,
    required this.onChanged,
  });

  final WorkProject project;
  final bool selected;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: disabled ? null : (value) => onChanged(value == true),
      title: Text(project.name),
      subtitle: disabled
          ? Text(context.l10n.goal_work_duplicate_context)
          : null,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

class _TaskCheckTile extends StatelessWidget {
  const _TaskCheckTile({
    required this.task,
    required this.selected,
    required this.disabled,
    required this.reason,
    required this.onChanged,
  });

  final WorkTask task;
  final bool selected;
  final bool disabled;
  final String? reason;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    return CheckboxListTile(
      value: selected,
      onChanged: disabled ? null : (value) => onChanged(value == true),
      title: Text(task.title),
      subtitle: Text(reason ?? workTaskContextLabel(context, work, task)),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsetsDirectional.only(
        start: task.parentTaskId == null ? 0 : 24,
        end: 0,
      ),
    );
  }
}

class _WorkSelection {
  const _WorkSelection({required this.projectIds, required this.taskIds});
  final Set<String> projectIds;
  final Set<String> taskIds;
}

double? _parse(String value) {
  final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
  return parsed == null || !parsed.isFinite ? null : parsed;
}

String _initialNumber(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();
