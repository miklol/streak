import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/widgets/app_confirm_dialog.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/habits/data/day_plan.dart';
import 'package:streak/features/work/data/work_day_plan.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/state/work_planning_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';
import 'package:streak/services/notification_service.dart';
import 'package:streak/services/reminder_schedule.dart';

class WorkPlanningSection extends StatelessWidget {
  const WorkPlanningSection({super.key, required this.taskId});

  final String taskId;

  Future<void> _addBlock(BuildContext context) async {
    await showWorkPlanEditor(context, taskId: taskId);
  }

  Future<void> _editBlock(BuildContext context, WorkPlanBlock block) async {
    await showWorkPlanEditor(context, taskId: taskId, block: block);
  }

  Future<void> _removeBlock(BuildContext context, WorkPlanBlock block) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.work_plan_remove_block,
      message: context.l10n.work_plan_remove_block_body,
      confirmLabel: context.l10n.work_plan_remove_block,
      icon: LucideIcons.trash2,
    );
    if (confirmed != true || !context.mounted) return;
    await runWorkAction(
      context,
      () => context.read<WorkPlanningController>().removeBlock(
        block.id,
        existing: block,
      ),
      onError: (error) => _showPlanningError(context, error),
    );
  }

  Future<void> _addReminder(BuildContext context, WorkTask task) async {
    final instant = await _showReminderEditor(context);
    if (instant == null || !context.mounted) return;
    await _requestReminderPermissionIfSupported();
    if (!context.mounted) return;
    final next = [...task.reminders, instant];
    await runWorkAction(
      context,
      () => context.read<WorkPlanningController>().saveReminders(task, next),
      onError: (error) => _showPlanningError(context, error),
    );
  }

  Future<void> _editReminder(
    BuildContext context,
    WorkTask task,
    DateTime reminder,
  ) async {
    final instant = await _showReminderEditor(context, initial: reminder);
    if (instant == null || !context.mounted) return;
    await _requestReminderPermissionIfSupported();
    if (!context.mounted) return;
    final next = [
      for (final item in task.reminders)
        if (item == reminder) instant else item,
    ];
    await runWorkAction(
      context,
      () => context.read<WorkPlanningController>().saveReminders(task, next),
      onError: (error) => _showPlanningError(context, error),
    );
  }

  Future<void> _removeReminder(
    BuildContext context,
    WorkTask task,
    DateTime reminder,
  ) async {
    final next = [
      for (final item in task.reminders)
        if (item != reminder) item,
    ];
    await runWorkAction(
      context,
      () => context.read<WorkPlanningController>().saveReminders(task, next),
      onError: (error) => _showPlanningError(context, error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final planning = context.watch<WorkPlanningController>();
    final task = work.taskById(taskId);
    if (task == null) return const SizedBox.shrink();
    final readOnly = !planning.canEditTask(task);
    final blocks = planning.blocksForTask(taskId);
    final now = DateTime.now().toUtc();
    final reminders = task.reminders.toList()..sort();
    final upcomingReminderCount = reminders
        .where((instant) => instant.toUtc().isAfter(now))
        .length;

    return WorkSection(
      title: context.l10n.work_plan_section_title,
      child: WorkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReminderStatus(failure: planning.reminderFailure),
            if (!readOnly) ...[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: const ValueKey('work-plan-add-block'),
                  onPressed: () => _addBlock(context),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text(context.l10n.work_plan_add_block),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              context.l10n.work_plan_day_summary_title,
              style: sheetLabelStyle(context),
            ),
            const SizedBox(height: 8),
            if (blocks.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.work_plan_no_blocks,
                    style: sheetHeadingStyle(context, size: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.work_plan_no_blocks_hint,
                    style: sheetBodyStyle(context),
                  ),
                ],
              )
            else
              for (final block in blocks)
                _PlanBlockRow(
                  block: block,
                  readOnly: readOnly,
                  onEdit: () => _editBlock(context, block),
                  onRemove: () => _removeBlock(context, block),
                ),
            const SizedBox(height: 14),
            Divider(
              color: context.colors.outlineVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.work_reminder_section_title,
              style: sheetLabelStyle(context),
            ),
            if (!readOnly) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: const ValueKey('work-reminder-add'),
                  onPressed:
                      upcomingReminderCount >=
                          WorkPlanningController.maxRemindersPerTask
                      ? null
                      : () => _addReminder(context, task),
                  icon: const Icon(LucideIcons.bellPlus, size: 18),
                  label: Text(context.l10n.work_reminder_add),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (reminders.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.work_reminder_none,
                    style: sheetHeadingStyle(context, size: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.work_reminder_none_hint,
                    style: sheetBodyStyle(context),
                  ),
                ],
              )
            else
              for (final reminder in reminders)
                _ReminderRow(
                  reminder: reminder,
                  readOnly: readOnly,
                  onEdit: () => _editReminder(context, task, reminder),
                  onRemove: () => _removeReminder(context, task, reminder),
                ),
          ],
        ),
      ),
    );
  }
}

class WorkDayPlanSummary extends StatelessWidget {
  const WorkDayPlanSummary({super.key, required this.day, this.onOpen});

  final DateTime day;
  final ValueChanged<WorkDayPlanItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final planning = context.watch<WorkPlanningController>();
    final items = planning.itemsForDay(day);
    return WorkSection(
      title: context.l10n.work_plan_day_summary_title,
      child: WorkCard(
        child: items.isEmpty
            ? Text(
                context.l10n.work_plan_day_summary_empty,
                style: sheetBodyStyle(context),
              )
            : Column(
                children: [
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.briefcase),
                      title: Text(item.title),
                      subtitle: Text(_workItemSubtitle(context, item)),
                      onTap: onOpen == null ? null : () => onOpen!(item),
                    ),
                ],
              ),
      ),
    );
  }
}

class _PlanBlockRow extends StatelessWidget {
  const _PlanBlockRow({
    required this.block,
    required this.readOnly,
    required this.onEdit,
    required this.onRemove,
  });

  final WorkPlanBlock block;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.calendarClock,
            size: 18,
            color: context.tokens.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _blockRangeLabel(context, block),
                  style: sheetHeadingStyle(context, size: 14),
                ),
                const SizedBox(height: 2),
                Text(spanLabel(block.minutes), style: sheetBodyStyle(context)),
                if (block.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(block.note.trim(), style: sheetBodyStyle(context)),
                ],
              ],
            ),
          ),
          if (!readOnly) ...[
            IconButton(
              tooltip: context.l10n.work_plan_edit_block,
              icon: const Icon(LucideIcons.pencil, size: 18),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: context.l10n.work_plan_remove_block,
              icon: const Icon(LucideIcons.trash2, size: 18),
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.readOnly,
    required this.onEdit,
    required this.onRemove,
  });

  final DateTime reminder;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(LucideIcons.bell, size: 18, color: context.tokens.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              workTimestampLabel(context, reminder),
              style: sheetHeadingStyle(context, size: 14),
            ),
          ),
          if (!readOnly) ...[
            IconButton(
              tooltip: context.l10n.work_reminder_edit,
              icon: const Icon(LucideIcons.pencil, size: 18),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: context.l10n.work_reminder_remove,
              icon: const Icon(LucideIcons.trash2, size: 18),
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReminderStatus extends StatelessWidget {
  const _ReminderStatus({required this.failure});

  final WorkReminderFailure? failure;

  @override
  Widget build(BuildContext context) {
    if (failure == null) return const SizedBox.shrink();
    final text = _reminderFailureMessage(context, failure!);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.tokens.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.triangleAlert, color: context.tokens.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: sheetBodyStyle(context, size: 13.5)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<WorkPlanBlock?> showWorkPlanEditor(
  BuildContext context, {
  required String taskId,
  WorkPlanBlock? block,
  DateTime? day,
}) {
  return showModalBottomSheet<WorkPlanBlock>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (sheetContext) => _WorkPlanEditorSheet(
      taskId: taskId,
      block: block,
      day: day,
      planning: context.read<WorkPlanningController>(),
    ),
  );
}

class _WorkPlanEditorSheet extends StatefulWidget {
  const _WorkPlanEditorSheet({
    required this.taskId,
    required this.planning,
    this.block,
    this.day,
  });

  final String taskId;
  final WorkPlanningController planning;
  final WorkPlanBlock? block;
  final DateTime? day;

  @override
  State<_WorkPlanEditorSheet> createState() => _WorkPlanEditorSheetState();
}

class _WorkPlanEditorSheetState extends State<_WorkPlanEditorSheet> {
  late final TextEditingController _date;
  late final TextEditingController _time;
  late final TextEditingController _minutes;
  late final TextEditingController _note;
  String? _error;
  bool _saving = false;
  final _dateFocus = FocusNode();
  final _durationFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final initial =
        widget.block?.startsAt.toLocal() ??
        widget.day ??
        DateTime.now().add(const Duration(hours: 1));
    _date = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(initial),
    );
    _time = TextEditingController(
      text:
          '${initial.hour.toString().padLeft(2, '0')}:${initial.minute.toString().padLeft(2, '0')}',
    );
    _minutes = TextEditingController(
      text: (widget.block?.minutes ?? 25).toString(),
    );
    _note = TextEditingController(text: widget.block?.note ?? '');
  }

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    _minutes.dispose();
    _note.dispose();
    _dateFocus.dispose();
    _durationFocus.dispose();
    super.dispose();
  }

  DateTime? _parsedStart() {
    final dateParts = _date.text.trim().split('-');
    final timeParts = _time.text.trim().split(':');
    if (dateParts.length != 3 || timeParts.length != 2) return null;
    final year = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final day = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if ([year, month, day, hour, minute].any((value) => value == null)) {
      return null;
    }
    if (year! < 1970 ||
        year > 9999 ||
        month! < 1 ||
        month > 12 ||
        day! < 1 ||
        day > 31) {
      return null;
    }
    if (hour! < 0 || hour > 23 || minute! < 0 || minute > 59) return null;
    final parsed = DateTime(year, month, day, hour, minute);
    if (parsed.year != year ||
        parsed.month != month ||
        parsed.day != day ||
        parsed.hour != hour ||
        parsed.minute != minute) {
      return null;
    }
    return parsed;
  }

  Future<void> _save() async {
    if (_saving) return;
    final startsAt = _parsedStart();
    final minutes = int.tryParse(_minutes.text.trim());
    if (startsAt == null) {
      setState(() => _error = context.l10n.work_plan_invalid_start);
      _dateFocus.requestFocus();
      return;
    }
    if (minutes == null ||
        minutes <= 0 ||
        minutes > WorkPlanningController.maxBlockMinutes) {
      setState(() => _error = context.l10n.work_plan_invalid_duration);
      _durationFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.planning.saveBlock(
      taskId: widget.taskId,
      startsAt: startsAt,
      minutes: minutes,
      note: _note.text,
      existing: widget.block,
    );
    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final startsAt = _parsedStart();
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    final conflicts =
        startsAt == null ||
            minutes <= 0 ||
            minutes > WorkPlanningController.maxBlockMinutes
        ? const <WorkPlanConflict>[]
        : widget.planning.conflictsForBlock(
            startsAt: startsAt,
            minutes: minutes,
            excludingBlockId: widget.block?.id,
          );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.block == null
                  ? context.l10n.work_plan_add_block
                  : context.l10n.work_plan_edit_block,
              style: sheetTitleStyle(context),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.work_plan_cancel),
                ),
                FilledButton(
                  key: const ValueKey('work-plan-save-block'),
                  onPressed: _saving
                      ? null
                      : () {
                          runWorkAction(
                            context,
                            _save,
                            onError: (error) {
                              if (!mounted) return;
                              setState(() {
                                _saving = false;
                                _error = _planningErrorMessage(context, error);
                              });
                            },
                          );
                        },
                  child: _saving
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(context.l10n.work_plan_save_block),
                            ),
                          ],
                        )
                      : Text(context.l10n.work_plan_save_block),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('work-plan-start-date'),
              focusNode: _dateFocus,
              controller: _date,
              decoration: InputDecoration(
                labelText: context.l10n.work_plan_start_date,
                hintText: 'YYYY-MM-DD',
              ),
              keyboardType: TextInputType.datetime,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('work-plan-start-time'),
              controller: _time,
              decoration: InputDecoration(
                labelText: context.l10n.work_plan_start_time,
                hintText: 'HH:mm',
              ),
              keyboardType: TextInputType.datetime,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('work-plan-duration'),
              focusNode: _durationFocus,
              controller: _minutes,
              decoration: InputDecoration(
                labelText: context.l10n.work_plan_duration_minutes,
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: context.l10n.work_plan_note,
                hintText: context.l10n.work_plan_note_hint,
              ),
              minLines: 1,
              maxLines: 3,
            ),
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ConflictNotice(conflicts: conflicts),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: context.tokens.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConflictNotice extends StatelessWidget {
  const _ConflictNotice({required this.conflicts});

  final List<WorkPlanConflict> conflicts;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.tokens.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.work_plan_conflict_title,
              style: sheetHeadingStyle(context),
            ),
            const SizedBox(height: 6),
            for (final conflict in conflicts.take(3))
              Text(
                '${_conflictLabel(context, conflict)} · ${_instantRangeLabel(context, conflict.startsAt, conflict.endsAt)}',
                style: sheetBodyStyle(context, size: 13),
              ),
          ],
        ),
      ),
    );
  }
}

Future<DateTime?> _showReminderEditor(
  BuildContext context, {
  DateTime? initial,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.9,
  ),
  builder: (sheetContext) => _WorkReminderEditorSheet(initial: initial),
);

class _WorkReminderEditorSheet extends StatefulWidget {
  const _WorkReminderEditorSheet({this.initial});

  final DateTime? initial;

  @override
  State<_WorkReminderEditorSheet> createState() =>
      _WorkReminderEditorSheetState();
}

class _WorkReminderEditorSheetState extends State<_WorkReminderEditorSheet> {
  late final TextEditingController _date;
  late final TextEditingController _time;
  String? _error;
  final _dateFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final at =
        widget.initial?.toLocal() ??
        DateTime.now().add(const Duration(hours: 1));
    _date = TextEditingController(text: DateFormat('yyyy-MM-dd').format(at));
    _time = TextEditingController(
      text:
          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    _dateFocus.dispose();
    super.dispose();
  }

  DateTime? _parse() {
    final dateParts = _date.text.trim().split('-');
    final timeParts = _time.text.trim().split(':');
    if (dateParts.length != 3 || timeParts.length != 2) return null;
    final values = [
      int.tryParse(dateParts[0]),
      int.tryParse(dateParts[1]),
      int.tryParse(dateParts[2]),
      int.tryParse(timeParts[0]),
      int.tryParse(timeParts[1]),
    ];
    if (values.any((value) => value == null)) return null;
    if (values[0]! < 1970 ||
        values[0]! > 9999 ||
        values[1]! < 1 ||
        values[1]! > 12 ||
        values[2]! < 1 ||
        values[2]! > 31) {
      return null;
    }
    if (values[3]! < 0 ||
        values[3]! > 23 ||
        values[4]! < 0 ||
        values[4]! > 59) {
      return null;
    }
    final parsed = DateTime(
      values[0]!,
      values[1]!,
      values[2]!,
      values[3]!,
      values[4]!,
    );
    if (parsed.year != values[0] ||
        parsed.month != values[1] ||
        parsed.day != values[2] ||
        parsed.hour != values[3] ||
        parsed.minute != values[4]) {
      return null;
    }
    return parsed;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null
                  ? context.l10n.work_reminder_add
                  : context.l10n.work_reminder_edit,
              style: sheetTitleStyle(context),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.work_plan_cancel),
                ),
                FilledButton(
                  key: const ValueKey('work-reminder-save'),
                  onPressed: () {
                    final parsed = _parse();
                    if (parsed == null || !parsed.isAfter(DateTime.now())) {
                      setState(
                        () => _error = context.l10n.work_reminder_invalid_time,
                      );
                      _dateFocus.requestFocus();
                      return;
                    }
                    Navigator.of(context).pop(parsed);
                  },
                  child: Text(context.l10n.work_reminder_save),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('work-reminder-date'),
              focusNode: _dateFocus,
              controller: _date,
              decoration: InputDecoration(
                labelText: context.l10n.work_reminder_date,
                hintText: 'YYYY-MM-DD',
              ),
              keyboardType: TextInputType.datetime,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('work-reminder-time'),
              controller: _time,
              decoration: InputDecoration(
                labelText: context.l10n.work_reminder_time,
                hintText: 'HH:mm',
              ),
              keyboardType: TextInputType.datetime,
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: context.tokens.danger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _blockRangeLabel(BuildContext context, WorkPlanBlock block) =>
    _instantRangeLabel(
      context,
      block.startsAt.toLocal(),
      block.endsAt.toLocal(),
    );

String _instantRangeLabel(BuildContext context, DateTime start, DateTime end) {
  final locale = Localizations.localeOf(context).toString();
  final day = DateFormat.MMMd(locale).format(start);
  final startTime = DateFormat.jm(locale).format(start);
  final endTime = DateFormat.jm(locale).format(end);
  final endDay = DateUtils.isSameDay(start, end)
      ? ''
      : ' ${DateFormat.MMMd(locale).format(end)}';
  return '$day, $startTime -$endDay $endTime';
}

String _workItemSubtitle(BuildContext context, WorkDayPlanItem item) {
  final scope = item.contextLabel;
  final time =
      '${minuteLabel(item.startMinute)} - ${minuteLabel(item.endMinute)} · ${spanLabel(item.plannedMinutes)}';
  return scope.isEmpty ? time : '$scope · $time';
}

String _conflictLabel(BuildContext context, WorkPlanConflict conflict) =>
    switch (conflict.kind) {
      WorkPlanConflictKind.habit => context.l10n.work_plan_conflict_habit(
        conflict.title,
      ),
      WorkPlanConflictKind.work => context.l10n.work_plan_conflict_work(
        conflict.title,
      ),
    };

String _reminderFailureMessage(
  BuildContext context,
  WorkReminderFailure failure,
) => switch (failure) {
  WorkReminderFailure.permissionDenied =>
    context.l10n.work_reminder_permission_denied,
  WorkReminderFailure.platformUnsupported =>
    context.l10n.work_reminder_platform_unsupported,
  WorkReminderFailure.schedulingFailed =>
    context.l10n.work_reminder_schedule_failed,
  WorkReminderFailure.capacityLimited =>
    context.l10n.work_reminder_capacity_limited,
};

String _planningErrorMessage(BuildContext context, Object error) {
  final text = error.toString();
  if (text.contains('future reminder')) {
    return context.l10n.work_reminder_invalid_time;
  }
  if (text.contains('10 or fewer')) return context.l10n.work_reminder_limit;
  if (text.contains('duration')) return context.l10n.work_plan_invalid_duration;
  if (text.contains('start time')) return context.l10n.work_plan_invalid_start;
  if (text.contains('changed')) return context.l10n.work_plan_stale;
  if (text.contains('plan this task')) {
    return context.l10n.work_plan_task_unavailable;
  }
  return workErrorMessage(context, error) ?? context.l10n.work_action_failed;
}

void _showPlanningError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_planningErrorMessage(context, error))),
  );
}

Future<void> _requestReminderPermissionIfSupported() async {
  final notifications = NotificationService();
  if (notifications.supportsWorkScheduling) {
    await notifications.requestPermissions();
  }
}
