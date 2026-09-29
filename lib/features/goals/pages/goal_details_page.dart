import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/extensions/inset_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/app_empty_state.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/progress_result.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/goals/widgets/goal_form.dart';
import 'package:streak/features/goals/widgets/goal_habit_links.dart';
import 'package:streak/features/goals/widgets/goal_history.dart';
import 'package:streak/features/goals/widgets/goal_ui.dart';
import 'package:streak/features/focus/state/work_focus_actions.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/pages/work_project_page.dart';
import 'package:streak/features/work/pages/work_task_page.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

class GoalDetailsPage extends StatefulWidget {
  const GoalDetailsPage({super.key, required this.goalId});

  final String goalId;

  @override
  State<GoalDetailsPage> createState() => _GoalDetailsPageState();
}

class _GoalDetailsPageState extends State<GoalDetailsPage> {
  @override
  void dispose() {
    if (AppNavigator.paneItem.value == 'goal:${widget.goalId}') {
      AppNavigator.paneItem.value = null;
    }
    super.dispose();
  }

  Future<void> _toggleArchive(Goal goal) async {
    await runGoalAction(
      context,
      () => context.read<GoalsController>().setArchived(goal, !goal.isArchived),
    );
  }

  Future<void> _togglePin(Goal goal) async {
    await runGoalAction(
      context,
      () => context.read<GoalsController>().setPinned(goal, !goal.pinned),
    );
  }

  Future<void> _setStatus(Goal goal, GoalStatus status) async {
    await runGoalAction(
      context,
      () => context.read<GoalsController>().setStatus(goal, status),
    );
  }

  Future<void> _recordProgress(Goal goal) async {
    await _showGoalProgressForm(context, goal);
  }

  void _openProject(WorkProject project) {
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-project:${project.id}';
    }
    AppNavigator.push(WorkProjectPage(projectId: project.id), fade: true);
  }

  void _openTask(WorkTask task) {
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-task:${task.id}';
    }
    AppNavigator.push(WorkTaskPage(taskId: task.id), fade: true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GoalsController>(
      builder: (context, goals, _) {
        final goal = goals.byId(widget.goalId);
        if (goal == null || goal.isDeleted) {
          return Scaffold(
            appBar: AppBar(),
            body: AppEmptyState(
              icon: LucideIcons.target,
              title: context.l10n.goal_deleted_title,
              message: context.l10n.goal_deleted_message,
              action: TextButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(LucideIcons.arrowLeft, size: 18),
                label: Text(
                  MaterialLocalizations.of(context).backButtonTooltip,
                ),
              ),
            ),
          );
        }
        final settings = context.watch<SettingsController>();
        final result = goals.progressFor(goal.id);
        final archived = goal.isArchived;
        final canPin =
            goal.scope == GoalScope.personal &&
            !archived &&
            ((goal.status != GoalStatus.achieved &&
                    goal.status != GoalStatus.cancelled) ||
                goal.pinned);
        final canAchieve =
            !archived &&
            goal.status != GoalStatus.achieved &&
            ((goal.source == GoalSource.manual &&
                    goal.measurement == GoalMeasurement.completion) ||
                (result.progress?.reachedTarget ?? false));
        return Scaffold(
          appBar: AppBar(
            title: Text(goal.title, overflow: TextOverflow.ellipsis),
            actions: [
              if (!archived)
                IconButton(
                  tooltip: context.l10n.edit,
                  onPressed: () => showGoalForm(context, goal: goal),
                  icon: const Icon(LucideIcons.pencil, size: 18),
                ),
              if (canPin)
                IconButton(
                  tooltip: goal.pinned
                      ? context.l10n.goal_unpin
                      : context.l10n.goal_pin,
                  onPressed: () => _togglePin(goal),
                  icon: Icon(
                    goal.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                    size: 18,
                  ),
                ),
              PopupMenuButton<GoalStatus>(
                tooltip: context.l10n.status,
                onSelected: (status) => _setStatus(goal, status),
                itemBuilder: (_) => [
                  for (final status in GoalStatus.values)
                    PopupMenuItem(
                      value: status,
                      enabled: !archived && status != goal.status,
                      child: Text(goalStatusLabel(context, status)),
                    ),
                ],
                icon: const Icon(LucideIcons.flag, size: 18),
              ),
              IconButton(
                tooltip: archived ? context.l10n.restore : context.l10n.archive,
                onPressed: () => _toggleArchive(goal),
                icon: Icon(
                  archived ? LucideIcons.rotateCcw : LucideIcons.archive,
                  size: 18,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: context.pagePadding(
              settings.isMinimalStyle ? 22 : 16,
              settings.isExpressStyle ? 4 : 8,
              settings.isMinimalStyle ? 22 : 16,
              32,
            ),
            children: [
              WorkEntityHero(
                title: goal.title,
                subtitle: _goalSubtitle(context, goal),
                description: goal.description,
                glyph: goal.icon,
                tint: Color(goal.color),
                badges: [
                  GoalBadge(
                    child: WorkBadge(
                      icon: _statusIcon(goal.status),
                      label: goalStatusLabel(context, goal.status),
                      color: _statusColor(context, goal.status),
                    ),
                  ),
                  GoalBadge(
                    child: WorkBadge(
                      icon: _sourceIcon(goal.source),
                      label: goalSourceLabel(context, goal.source),
                      color: context.colors.primary,
                    ),
                  ),
                  if (goal.pinned && goal.scope == GoalScope.personal)
                    GoalBadge(
                      child: WorkBadge(
                        icon: LucideIcons.pin,
                        label: context.l10n.goal_pinned,
                        color: context.tokens.info,
                      ),
                    ),
                  if (archived)
                    GoalBadge(
                      child: WorkBadge(
                        icon: LucideIcons.archive,
                        label: context.l10n.goal_archived,
                        color: context.tokens.muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _GoalProgressSection(
                goal: goal,
                result: result,
                onRecord: !archived && goal.source == GoalSource.manual
                    ? () => _recordProgress(goal)
                    : null,
                onAchieve: canAchieve
                    ? () => _setStatus(goal, GoalStatus.achieved)
                    : null,
              ),
              WorkSection(
                title: context.l10n.goal_details,
                child: WorkMetaList(
                  children: [
                    WorkMetaTile(
                      icon: LucideIcons.flag,
                      label: context.l10n.status,
                      value: goalStatusLabel(context, goal.status),
                    ),
                    WorkMetaTile(
                      icon: LucideIcons.gauge,
                      label: context.l10n.goal_measurement,
                      value: goalMeasurementLabel(context, goal.measurement),
                    ),
                    if (goal.baseline != 0)
                      WorkMetaTile(
                        icon: LucideIcons.gauge,
                        label: context.l10n.goal_baseline,
                        value: goalValueLabel(context, goal, goal.baseline),
                      ),
                    if (goal.category.trim().isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.tag,
                        label: context.l10n.goal_category,
                        value: goal.category.trim(),
                      ),
                    if (goal.why.trim().isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.heart,
                        label: context.l10n.goal_why,
                        value: goal.why.trim(),
                      ),
                    if (goal.startDate != null)
                      WorkMetaTile(
                        icon: LucideIcons.calendarDays,
                        label: context.l10n.goal_start_date,
                        value: workDateLabel(context, goal.startDate),
                      ),
                    if (goal.endDate != null)
                      WorkMetaTile(
                        icon: LucideIcons.calendarCheck,
                        label: context.l10n.goal_end_date,
                        value: workDateLabel(context, goal.endDate),
                      ),
                    WorkMetaTile(
                      icon: goal.scope == GoalScope.personal
                          ? LucideIcons.user
                          : LucideIcons.briefcase,
                      label: context.l10n.goal_scope,
                      value: _goalScopeLabel(context, goal),
                    ),
                  ],
                ),
              ),
              GoalHabitLinksSection(goalId: goal.id),
              _RelatedWorkSection(
                goal: goal,
                onOpenProject: _openProject,
                onOpenTask: _openTask,
              ),
              GoalHistory(goal: goal),
            ],
          ),
        );
      },
    );
  }
}

class _GoalProgressSection extends StatelessWidget {
  const _GoalProgressSection({
    required this.goal,
    required this.result,
    this.onRecord,
    this.onAchieve,
  });

  final Goal goal;
  final GoalProgressResult result;
  final VoidCallback? onRecord;
  final VoidCallback? onAchieve;

  @override
  Widget build(BuildContext context) {
    final progress = result.progress;
    final issue = result.issue;
    final fraction = progress?.fraction.clamp(0.0, 1.0);
    return WorkSection(
      title: context.l10n.goal_progress,
      child: WorkCard(
        borderColor: issue == null
            ? null
            : context.tokens.warning.withValues(alpha: 0.55),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: fraction ?? 0,
              minHeight: 12,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
            const SizedBox(height: 12),
            if (progress != null) ...[
              Text(
                goalValueLabel(context, goal, progress.value),
                style: sheetTitleStyle(context, size: 24),
              ),
              const SizedBox(height: 4),
              Text(
                goalProgressSummary(context, goal, progress.value),
                style: sheetBodyStyle(context),
              ),
            ] else ...[
              Text(
                context.l10n.goal_progress_unavailable,
                style: sheetHeadingStyle(context),
              ),
              const SizedBox(height: 4),
              Text(
                issue == null
                    ? context.l10n.goal_progress_empty
                    : goalProgressIssueLabel(context, issue),
                style: sheetBodyStyle(context),
              ),
            ],
            if (onRecord != null || onAchieve != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onRecord != null)
                    FilledButton.icon(
                      onPressed: onRecord,
                      icon: const Icon(LucideIcons.gauge, size: 18),
                      label: Text(context.l10n.goal_record_progress),
                    ),
                  if (onAchieve != null)
                    OutlinedButton.icon(
                      onPressed: onAchieve,
                      icon: const Icon(LucideIcons.circleCheck, size: 18),
                      label: Text(context.l10n.goal_mark_achieved),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RelatedWorkSection extends StatelessWidget {
  const _RelatedWorkSection({
    required this.goal,
    required this.onOpenProject,
    required this.onOpenTask,
  });

  final Goal goal;
  final ValueChanged<WorkProject> onOpenProject;
  final ValueChanged<WorkTask> onOpenTask;

  @override
  Widget build(BuildContext context) {
    if (goal.projectIds.isEmpty &&
        goal.taskIds.isEmpty &&
        goal.projectId == null) {
      return const SizedBox.shrink();
    }
    final work = context.watch<WorkController>();
    final projects = [
      for (final id in {
        if (goal.projectId != null) goal.projectId!,
        ...goal.projectIds,
      })
        if (work.projectById(id) != null && !work.projectById(id)!.isDeleted)
          work.projectById(id)!,
    ];
    final tasks = [
      for (final id in goal.taskIds)
        if (work.taskById(id) != null && !work.taskById(id)!.isDeleted)
          work.taskById(id)!,
    ];
    return WorkSection(
      title: context.l10n.goal_related_work,
      child: WorkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (projects.isEmpty && tasks.isEmpty)
              Text(
                context.l10n.goal_no_work_items,
                style: sheetBodyStyle(context),
              ),
            for (final project in projects)
              ListTile(
                leading: const Icon(LucideIcons.folder),
                title: Text(project.name),
                subtitle: Text(workProjectContextLabel(context, work, project)),
                onTap: () => onOpenProject(project),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
              ),
            for (final task in tasks)
              ListTile(
                leading: const Icon(LucideIcons.listChecks),
                title: Text(task.title),
                subtitle: Text(workTaskContextLabel(context, work, task)),
                onTap: () => onOpenTask(task),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!goal.isArchived &&
                        context.watch<SettingsController>().focusEnabled &&
                        !work.isTaskArchived(task) &&
                        task.status != WorkTaskStatus.cancelled)
                      IconButton(
                        tooltip: context.l10n.work_focus_start_task,
                        onPressed: () =>
                            openWorkFocus(context, taskId: task.id),
                        icon: const Icon(LucideIcons.timer, size: 18),
                      ),
                    const Icon(LucideIcons.chevronRight, size: 18),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<Goal?> _showGoalProgressForm(
  BuildContext context,
  Goal goal,
) {
  return showModalBottomSheet<Goal>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: _GoalProgressForm(goal: goal),
    ),
  );
}

class _GoalProgressForm extends StatefulWidget {
  const _GoalProgressForm({required this.goal});
  final Goal goal;
  @override
  State<_GoalProgressForm> createState() => _GoalProgressFormState();
}

class _GoalProgressFormState extends State<_GoalProgressForm> {
  final _formKey = GlobalKey<FormState>();
  final _valueFocus = FocusNode();
  late final TextEditingController _value = TextEditingController(
    text: widget.goal.measurement == GoalMeasurement.completion
        ? '1'
        : _initialNumber(widget.goal.current),
  );
  final _note = TextEditingController();
  late String _date = AppClock.today().dayKey;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    _valueFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseDayKey(_date),
      firstDate: DateTime(1900),
      lastDate: AppClock.today(),
    );
    if (picked != null && mounted) setState(() => _date = picked.dayKey);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      _valueFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await runGoalAction(
      context,
      () async {
        final saved = await context.read<GoalsController>().recordProgress(
          widget.goal,
          double.parse(_value.text.trim().replaceAll(',', '.')),
          note: _note.text.trim(),
          date: _date,
        );
        if (mounted) Navigator.of(context).pop(saved);
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = goalErrorMessage(context, error);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 18, 18),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetTitle(
                  context.l10n.goal_record_progress,
                  subtitle: widget.goal.title,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('goal-progress-value-field'),
                  controller: _value,
                  focusNode: _valueFocus,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.goal_record_value,
                    suffixText: switch (widget.goal.measurement) {
                      GoalMeasurement.number => widget.goal.unit,
                      GoalMeasurement.currency => widget.goal.currency,
                      GoalMeasurement.percentage => '%',
                      GoalMeasurement.completion => null,
                    },
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(
                      (value ?? '').trim().replaceAll(',', '.'),
                    );
                    if (parsed == null || !parsed.isFinite) {
                      return context.l10n.goal_invalid_number;
                    }
                    if (widget.goal.measurement == GoalMeasurement.completion &&
                        parsed != 0 &&
                        parsed != 1) {
                      return context.l10n.goal_manual_completion_hint;
                    }
                    if (widget.goal.measurement == GoalMeasurement.percentage &&
                        (parsed < 0 || parsed > 100)) {
                      return context.l10n.goal_invalid_percentage;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: context.l10n.goal_record_note,
                    hintText: context.l10n.goal_note_hint,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(LucideIcons.calendarDays, size: 18),
                  label: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(workDateLabel(context, _date)),
                  ),
                ),
                const SizedBox(height: 18),
                if (_error != null) ...[
                  Semantics(liveRegion: true, child: Text(_error!)),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.save, size: 18),
                  label: Text(context.l10n.save),
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
      ),
    );
  }
}

String _initialNumber(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();

String _goalSubtitle(BuildContext context, Goal goal) {
  final parts = <String>[
    goal.scope == GoalScope.personal
        ? context.l10n.goal_scope_personal
        : context.l10n.goal_scope_work,
    goalSourceLabel(context, goal.source),
  ];
  return parts.join(' • ');
}

String _goalScopeLabel(BuildContext context, Goal goal) {
  if (goal.scope == GoalScope.personal) return context.l10n.goal_scope_personal;
  final work = context.read<WorkController>();
  return workScopeLabel(
    context,
    work,
    areaId: goal.areaId,
    projectId: goal.projectId,
  );
}

IconData _statusIcon(GoalStatus status) => switch (status) {
  GoalStatus.notStarted => LucideIcons.circle,
  GoalStatus.active => LucideIcons.play,
  GoalStatus.paused => LucideIcons.pause,
  GoalStatus.achieved => LucideIcons.circleCheck,
  GoalStatus.cancelled => LucideIcons.circleSlash,
};

IconData _sourceIcon(GoalSource source) => switch (source) {
  GoalSource.manual => LucideIcons.penLine,
  GoalSource.habits => LucideIcons.repeat2,
  GoalSource.work => LucideIcons.briefcase,
};

Color _statusColor(BuildContext context, GoalStatus status) => switch (status) {
  GoalStatus.notStarted => context.colors.primary,
  GoalStatus.active => context.tokens.info,
  GoalStatus.paused => context.tokens.warning,
  GoalStatus.achieved => context.tokens.success,
  GoalStatus.cancelled => context.tokens.muted,
};
