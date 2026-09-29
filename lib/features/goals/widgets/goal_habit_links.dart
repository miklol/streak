import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/widgets/app_confirm_dialog.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/focus/pages/focus_page.dart';
import 'package:streak/features/focus/pages/focus_setup_page.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/data/progress_result.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/goals/widgets/goal_ui.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/pages/habit_details_page.dart';
import 'package:streak/features/habits/pages/habit_form_page.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

String goalHabitRoleLabel(BuildContext context, GoalHabitRole role) =>
    role == GoalHabitRole.supporting
    ? context.l10n.glink_supporting
    : context.l10n.glink_contributor;

String goalHabitMetricLabel(BuildContext context, HabitGoalMetric metric) =>
    switch (metric) {
      HabitGoalMetric.completedDays => context.l10n.glink_completed_days,
      HabitGoalMetric.quantity => context.l10n.glink_quantity,
      HabitGoalMetric.duration => context.l10n.glink_duration,
      HabitGoalMetric.consistency => context.l10n.glink_consistency,
    };

class GoalHabitLinksSection extends StatelessWidget {
  const GoalHabitLinksSection({super.key, required this.goalId});
  final String goalId;

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    final goal = goals.byId(goalId);
    if (goal == null || goal.isDeleted) return const SizedBox.shrink();
    final links = goals.linksForGoal(goalId);
    return WorkSection(
      title: context.l10n.glink_habits,
      child: WorkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!goal.isArchived)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        showGoalHabitLinkEditor(context, goalId: goalId),
                    icon: const Icon(LucideIcons.link, size: 18),
                    label: Text(context.l10n.glink_link_habit),
                  ),
                  TextButton.icon(
                    onPressed: () => AppNavigator.push(
                      HabitFormPage(relatedGoalId: goalId),
                      fullscreenDialog: true,
                    ),
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text(context.l10n.glink_create_habit),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (links.isEmpty)
              Text(
                context.l10n.glink_habits_empty,
                style: sheetBodyStyle(context),
              ),
            for (final link in links) ...[
              const SizedBox(height: 8),
              _LinkedHabitRow(link: link, readOnly: goal.isArchived),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkedHabitRow extends StatelessWidget {
  const _LinkedHabitRow({required this.link, required this.readOnly});
  final GoalHabitLink link;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    final habit = goals.habits.byId(link.habitId);
    final goal = goals.byId(link.goalId)!;
    final focus = context.watch<FocusController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextButton(
                onPressed: habit == null
                    ? null
                    : () => AppNavigator.push(
                        HabitDetailsPage(habitId: habit.id),
                      ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(habit?.name ?? context.l10n.glink_missing_habit),
                ),
              ),
            ),
            if (!readOnly)
              PopupMenuButton<String>(
                tooltip: context.l10n.work_actions_for(
                  habit?.name ?? context.l10n.glink_missing_habit,
                ),
                onSelected: (action) {
                  if (action == 'edit') {
                    showGoalHabitLinkEditor(
                      context,
                      goalId: link.goalId,
                      habitId: link.habitId,
                      existing: link,
                    );
                  }
                  if (action == 'unlink') confirmGoalHabitUnlink(context, link);
                },
                itemBuilder: (_) => [
                  if (habit != null)
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(context.l10n.glink_edit),
                    ),
                  PopupMenuItem(
                    value: 'unlink',
                    child: Text(context.l10n.glink_unlink),
                  ),
                ],
              ),
          ],
        ),
        Text(
          goalHabitRoleLabel(context, link.role),
          style: sheetLabelStyle(context),
        ),
        if (link.role == GoalHabitRole.contributor &&
            goal.source != GoalSource.habits)
          Text(
            context.l10n.glink_inactive_contributor,
            style: sheetBodyStyle(context),
          ),
        if (link.role == GoalHabitRole.contributor)
          Text(
            context.l10n.glink_rule(
              goalHabitMetricLabel(context, link.metric),
              workDateLabel(context, link.startDate),
              link.endDate == null
                  ? context.l10n.glink_no_end
                  : workDateLabel(context, link.endDate),
            ),
            style: sheetBodyStyle(context),
          ),
        if (habit?.isArchived == true)
          Text(
            context.l10n.glink_archived_source,
            style: sheetBodyStyle(context),
          ),
        if (habit != null &&
            !habit.isArchived &&
            !readOnly &&
            context.watch<SettingsController>().focusEnabled)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () {
                if (focus.isActive) {
                  if (!AppNavigator.isShowing(FocusPage.routeName)) {
                    AppNavigator.push(
                      const FocusPage(),
                      name: FocusPage.routeName,
                    );
                  }
                } else {
                  AppNavigator.push(FocusSetupPage(habitId: habit.id));
                }
              },
              icon: const Icon(LucideIcons.timer, size: 18),
              label: Text(
                focus.isActive
                    ? context.l10n.work_focus_resume_active
                    : context.l10n.glink_focus_habit,
              ),
            ),
          ),
        if (goal.source == GoalSource.habits &&
            link.role == GoalHabitRole.contributor &&
            goals.previewHabitLink(link).issue != null)
          Text(
            context.l10n.glink_review_source,
            style: sheetBodyStyle(context),
          ),
      ],
    );
  }
}

Future<void> confirmGoalHabitUnlink(
  BuildContext context,
  GoalHabitLink link,
) async {
  final goals = context.read<GoalsController>();
  final goal = goals.byId(link.goalId);
  if (goal == null || goal.isDeleted) {
    await runGoalAction(context, () async {
      throw const GoalOperationException(GoalFailure.missing);
    });
    return;
  }
  final result = goals.previewUnlink(link);
  final effect = result.progress == null
      ? goalProgressIssueLabel(
          context,
          result.issue ?? GoalProgressIssue.invalidData,
        )
      : goalValueLabel(context, goal, result.progress!.value);
  final confirmed = await showAppConfirmDialog(
    context,
    title: context.l10n.glink_unlink,
    message: context.l10n.glink_unlink_body(effect),
    confirmLabel: context.l10n.glink_unlink,
    icon: LucideIcons.unlink,
    danger: false,
  );
  if (confirmed != true || !context.mounted) return;
  await runGoalAction(context, () => goals.unlinkHabit(link));
}

Future<GoalHabitLink?> showGoalHabitLinkEditor(
  BuildContext context, {
  required String goalId,
  String? habitId,
  GoalHabitLink? existing,
}) async {
  final goals = context.read<GoalsController>();
  String? sourceId = habitId ?? existing?.habitId;
  sourceId ??= await showDialog<String>(
    context: context,
    builder: (_) => _HabitPicker(goalId: goalId),
  );
  if (sourceId == null || !context.mounted) return null;
  final habit = goals.habits.byId(sourceId);
  final goal = goals.byId(goalId);
  if (habit == null || goal == null) {
    await runGoalAction(context, () async {
      throw const GoalOperationException(GoalFailure.missing);
    });
    return null;
  }
  return showModalBottomSheet<GoalHabitLink>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .95,
    ),
    builder: (_) =>
        _GoalHabitLinkEditor(goal: goal, habit: habit, existing: existing),
  );
}

class _HabitPicker extends StatefulWidget {
  const _HabitPicker({required this.goalId});
  final String goalId;
  @override
  State<_HabitPicker> createState() => _HabitPickerState();
}

class _HabitPickerState extends State<_HabitPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    final linked = goals
        .linksForGoal(widget.goalId)
        .map((link) => link.habitId)
        .toSet();
    final habits = [...goals.habits.habits, ...goals.habits.archived]
        .where(
          (habit) =>
              !linked.contains(habit.id) &&
              habit.name.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: Text(context.l10n.glink_link_habit),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.glink_search_habits,
                prefixIcon: const Icon(LucideIcons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (habits.isEmpty) Text(context.l10n.glink_no_habits),
                  for (final habit in habits)
                    ListTile(
                      title: Text(habit.name),
                      subtitle: habit.isArchived
                          ? Text(context.l10n.glink_archived_source)
                          : null,
                      onTap: () => Navigator.of(context).pop(habit.id),
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
      ],
    );
  }
}

class _GoalHabitLinkEditor extends StatefulWidget {
  const _GoalHabitLinkEditor({
    required this.goal,
    required this.habit,
    this.existing,
  });
  final Goal goal;
  final Habit habit;
  final GoalHabitLink? existing;
  @override
  State<_GoalHabitLinkEditor> createState() => _GoalHabitLinkEditorState();
}

class _GoalHabitLinkEditorState extends State<_GoalHabitLinkEditor> {
  late GoalHabitRole _role = widget.existing?.role ?? GoalHabitRole.supporting;
  late HabitGoalMetric _metric = widget.existing?.metric ?? _defaultMetric();
  late String _startDate =
      widget.existing?.startDate ?? AppClock.today().dayKey;
  late String? _endDate = widget.existing?.endDate;
  bool _saving = false;
  String? _error;
  late final GoalHabitLink? _original = widget.existing;

  HabitGoalMetric _defaultMetric() {
    if (widget.goal.measurement == GoalMeasurement.percentage) {
      return HabitGoalMetric.consistency;
    }
    if (widget.habit.isTimeAmount &&
        ['minutes', 'hours'].contains(widget.goal.unit)) {
      return HabitGoalMetric.duration;
    }
    if (widget.habit.kind == HabitKind.quantitative &&
        widget.goal.unit == widget.habit.unitLabel) {
      return HabitGoalMetric.quantity;
    }
    return HabitGoalMetric.completedDays;
  }

  String get _unit => switch (_metric) {
    HabitGoalMetric.completedDays => 'days',
    HabitGoalMetric.quantity => widget.habit.unitLabel,
    HabitGoalMetric.duration =>
      widget.goal.unit == 'hours' ? 'hours' : 'minutes',
    HabitGoalMetric.consistency => '%',
  };

  List<HabitGoalMetric> get _metrics => [
    HabitGoalMetric.completedDays,
    if (widget.habit.kind == HabitKind.quantitative &&
        !widget.habit.isTimeAmount &&
        !widget.habit.hasSubsteps)
      HabitGoalMetric.quantity,
    if (widget.habit.isTimeAmount) HabitGoalMetric.duration,
    HabitGoalMetric.consistency,
  ];

  GoalHabitLink _draft(GoalsController goals) => goals.buildHabitLink(
    goalId: widget.goal.id,
    habitId: widget.habit.id,
    role: _role,
    metric: _metric,
    startDate: _role == GoalHabitRole.contributor ? _startDate : null,
    endDate: _role == GoalHabitRole.contributor ? _endDate : null,
    unit: _role == GoalHabitRole.contributor ? _unit : '',
    existing: _original,
  );

  Future<void> _pickDate(bool end) async {
    final initial = end ? (_endDate ?? _startDate) : _startDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: parseDayKey(initial),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (end) {
        _endDate = selected.dayKey;
      } else {
        _startDate = selected.dayKey;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final goals = context.read<GoalsController>();
    if (_role == GoalHabitRole.contributor &&
        widget.goal.source != GoalSource.habits) {
      setState(() => _error = context.l10n.glink_change_source);
      return;
    }
    if (_role == GoalHabitRole.contributor && !_validDateRange) {
      setState(() => _error = context.l10n.goal_invalid_dates);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await runGoalAction(
      context,
      () async {
        final saved = await goals.saveHabitLink(
          _draft(goals),
          expectedRevision: _original?.meta.revision,
        );
        if (mounted) Navigator.of(context).pop(saved);
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = goalErrorMessage(context, error);
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    GoalProgressResult? preview;
    String? previewError;
    try {
      if (_role == GoalHabitRole.contributor && !_validDateRange) {
        previewError = context.l10n.goal_invalid_dates;
      } else {
        preview = goals.previewHabitLink(_draft(goals));
      }
    } on ArgumentError catch (error) {
      previewError = goalErrorMessage(context, error);
    } on StateError catch (error) {
      previewError = goalErrorMessage(context, error);
    } on GoalOperationException catch (error) {
      previewError = goalErrorMessage(context, error);
    }
    final issue = preview?.issue;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetTitle(
                _original == null
                    ? context.l10n.glink_link_habit
                    : context.l10n.glink_edit,
                subtitle: context.l10n.glink_connection(
                  widget.habit.name,
                  widget.goal.title,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<GoalHabitRole>(
                initialValue: _role,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.l10n.glink_role),
                items: [
                  for (final role in GoalHabitRole.values)
                    DropdownMenuItem(
                      value: role,
                      child: Text(goalHabitRoleLabel(context, role)),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _role = value!;
                        _error = null;
                      }),
              ),
              const SizedBox(height: 12),
              Text(
                _role == GoalHabitRole.supporting
                    ? context.l10n.glink_supporting_hint
                    : context.l10n.glink_contributor_hint,
                style: sheetBodyStyle(context),
              ),
              if (_role == GoalHabitRole.contributor) ...[
                const SizedBox(height: 16),
                if (widget.goal.source != GoalSource.habits)
                  Text(
                    context.l10n.glink_change_source,
                    style: sheetBodyStyle(context),
                  ),
                DropdownButtonFormField<HabitGoalMetric>(
                  initialValue: _metrics.contains(_metric) ? _metric : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.glink_measure,
                  ),
                  items: [
                    for (final metric in _metrics)
                      DropdownMenuItem(
                        value: metric,
                        child: Text(goalHabitMetricLabel(context, metric)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _metric = value!;
                          _error = null;
                        }),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.glink_matching_unit(_unit),
                  style: sheetBodyStyle(context),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _pickDate(false),
                  icon: const Icon(LucideIcons.calendar, size: 18),
                  label: Text(
                    context.l10n.glink_count_from(
                      workDateLabel(context, _startDate),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : () => _pickDate(true),
                      child: Text(
                        _endDate == null
                            ? context.l10n.glink_add_end
                            : context.l10n.glink_count_to(
                                workDateLabel(context, _endDate),
                              ),
                      ),
                    ),
                    if (_endDate != null)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _endDate = null),
                        child: Text(context.l10n.glink_clear_end),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.glink_window_hint,
                  style: sheetBodyStyle(context),
                ),
                if (_original != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.glink_refresh_hint,
                    style: sheetBodyStyle(context),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              WorkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.glink_preview,
                      style: sheetHeadingStyle(context),
                    ),
                    const SizedBox(height: 8),
                    if (preview?.progress != null)
                      Text(
                        goalValueLabel(
                          context,
                          widget.goal,
                          preview!.progress!.value,
                        ),
                        style: sheetHeadingStyle(context, size: 22),
                      )
                    else
                      Text(
                        previewError ??
                            goalProgressIssueLabel(
                              context,
                              issue ?? GoalProgressIssue.invalidData,
                            ),
                        style: sheetBodyStyle(context),
                      ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(_error!)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.link, size: 18),
                label: Text(context.l10n.glink_save),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(context.l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _validDateRange =>
      _endDate == null ||
      !parseDayKey(_endDate!).isBefore(parseDayKey(_startDate));
}
