import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/widgets/app_confirm_dialog.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/work/data/work_time_summary.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

class WorkTimeSection extends StatefulWidget {
  const WorkTimeSection({
    super.key,
    this.taskId,
    this.projectId,
    this.areaId,
    this.readOnly = false,
  });

  final String? taskId;
  final String? projectId;
  final String? areaId;
  final bool readOnly;

  @override
  State<WorkTimeSection> createState() => _WorkTimeSectionState();
}

class _WorkTimeSectionState extends State<WorkTimeSection> {
  int _shown = 10;
  bool _includeSubtasks = true;

  Future<void> _edit({FocusSession? session}) async {
    final taskId = widget.taskId;
    if (taskId == null && session == null) return;
    final work = context.read<WorkController>();
    await runWorkAction(context, () async {
      final target =
          session?.target ?? FocusTarget.fromWork(work.data, taskId!);
      await showWorkTimeEditor(context, target: target, session: session);
    });
  }

  Future<void> _editNote(FocusSession session) async {
    final note = await _showTimeNote(context, session.note);
    if (note == null || !mounted) return;
    await runWorkAction(
      context,
      () => context.read<FocusController>().updateWorkNote(session, note),
    );
  }

  Future<void> _delete(FocusSession session) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.work_time_delete,
      message: context.l10n.work_time_delete_body,
      confirmLabel: context.l10n.work_time_delete,
      icon: LucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    await runWorkAction(
      context,
      () => context.read<FocusController>().removeSessions({session.id}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusController>();
    final summary = WorkTimeSummary.of(
      focus.sessions,
      taskId: widget.taskId,
      projectId: widget.projectId,
      areaId: widget.areaId,
      includeSubtasks: _includeSubtasks,
    );
    return WorkSection(
      title: context.l10n.work_time_title,
      trailing: widget.taskId != null && !widget.readOnly
          ? TextButton.icon(
              onPressed: _edit,
              icon: const Icon(LucideIcons.plus, size: 18),
              label: Text(context.l10n.work_time_add),
            )
          : null,
      child: WorkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              formatHoursShort(summary.totalSeconds),
              style: sheetHeadingStyle(context, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.work_time_breakdown(
                formatHoursShort(summary.timedSeconds),
                formatHoursShort(summary.manualSeconds),
              ),
              style: sheetBodyStyle(context),
            ),
            if (widget.taskId != null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.work_time_task_breakdown(
                  formatHoursShort(summary.directSeconds),
                  formatHoursShort(summary.childSeconds),
                ),
                style: sheetBodyStyle(context),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.work_time_include_subtasks),
                value: _includeSubtasks,
                onChanged: (value) => setState(() => _includeSubtasks = value),
              ),
            ],
            const SizedBox(height: 12),
            if (summary.sessions.isEmpty)
              Text(context.l10n.work_time_empty, style: sheetBodyStyle(context))
            else ...[
              for (final session in summary.sessions.take(_shown))
                Padding(
                  key: ValueKey('work-time-${session.id}'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        session.source == FocusEntrySource.manual
                            ? LucideIcons.pencil
                            : LucideIcons.timer,
                        size: 18,
                        color: context.tokens.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.work_time_entry(
                                session.target.title,
                                formatHoursShort(session.seconds),
                              ),
                              style: sheetHeadingStyle(context, size: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              workTimestampLabel(context, session.startedAt),
                              style: sheetBodyStyle(context, size: 13),
                            ),
                            Text(
                              session.source == FocusEntrySource.manual
                                  ? context.l10n.work_time_manual
                                  : context.l10n.work_time_focused,
                              style: sheetBodyStyle(context, size: 13),
                            ),
                            if (session.note.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              SelectableText(
                                session.note,
                                style: sheetBodyStyle(context),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!widget.readOnly)
                        PopupMenuButton<String>(
                          tooltip: context.l10n.work_actions_for(
                            session.target.title,
                          ),
                          onSelected: (action) {
                            if (action == 'note') _editNote(session);
                            if (action == 'time') _edit(session: session);
                            if (action == 'delete') _delete(session);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'note',
                              child: Text(context.l10n.work_time_note),
                            ),
                            PopupMenuItem(
                              value: 'time',
                              child: Text(context.l10n.work_time_correct),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(context.l10n.work_time_delete),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              if (summary.sessions.length > _shown)
                TextButton(
                  onPressed: () => setState(() => _shown += 20),
                  child: Text(context.l10n.work_time_more),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<FocusSession?> showWorkTimeEditor(
  BuildContext context, {
  required FocusTarget target,
  FocusSession? session,
}) => showModalBottomSheet<FocusSession>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _WorkTimeEditor(target: target, session: session),
);

class _WorkTimeEditor extends StatefulWidget {
  const _WorkTimeEditor({required this.target, this.session});
  final FocusTarget target;
  final FocusSession? session;
  @override
  State<_WorkTimeEditor> createState() => _WorkTimeEditorState();
}

class _WorkTimeEditorState extends State<_WorkTimeEditor> {
  final _form = GlobalKey<FormState>();
  late DateTime _startedAt =
      widget.session?.startedAt.toLocal() ??
      DateTime.now().subtract(const Duration(minutes: 25));
  late final _minutes = TextEditingController(
    text: widget.session == null
        ? '25'
        : (widget.session!.seconds / 60).toStringAsFixed(2),
  );
  late final _note = TextEditingController(text: widget.session?.note ?? '');
  final _durationFocus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _note.dispose();
    _durationFocus.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _startedAt.isAfter(now) ? now : _startedAt,
      firstDate: DateTime(_startedAt.year < 2000 ? _startedAt.year : 2000),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
    );
    if (time == null || !mounted) return;
    setState(
      () => _startedAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  double? get _duration =>
      double.tryParse(_minutes.text.trim().replaceAll(',', '.'));
  String? _validateDuration(String? _) {
    final value = _duration;
    return value == null ||
            !value.isFinite ||
            value <= 0 ||
            value > 1440 ||
            (value * 60).round() == 0
        ? context.l10n.work_time_duration_error
        : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      _durationFocus.requestFocus();
      return;
    }
    final end = _startedAt.add(Duration(seconds: (_duration! * 60).round()));
    if (end.isAfter(DateTime.now())) {
      setState(() => _error = context.l10n.work_time_future_error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await runWorkAction(
      context,
      () async {
        final saved = await context.read<FocusController>().saveWorkTime(
          target: widget.target,
          startedAt: _startedAt,
          endedAt: end,
          note: _note.text.trim(),
          existing: widget.session,
        );
        if (mounted) Navigator.of(context).pop(saved);
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = context.l10n.work_time_save_error;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetTitle(
                widget.session == null
                    ? context.l10n.work_time_add
                    : context.l10n.work_time_correct,
                subtitle: widget.target.title,
              ),
              const SizedBox(height: 16),
              if (widget.session?.source == FocusEntrySource.timer) ...[
                Text(
                  context.l10n.work_time_correction_hint,
                  style: sheetBodyStyle(context),
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickStart,
                icon: const Icon(LucideIcons.calendarClock, size: 18),
                label: Text(
                  context.l10n.work_time_started(
                    workTimestampLabel(context, _startedAt),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('work-time-minutes'),
                controller: _minutes,
                focusNode: _durationFocus,
                validator: _validateDuration,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.l10n.work_time_minutes,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('work-time-note'),
                controller: _note,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.work_time_note,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: sheetBodyStyle(context)),
                ),
              ],
              const SizedBox(height: 20),
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
            ],
          ),
        ),
      ),
    ),
  );
}

Future<String?> _showTimeNote(BuildContext context, String note) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TimeNoteDialog(note: note),
    );

class _TimeNoteDialog extends StatefulWidget {
  const _TimeNoteDialog({required this.note});
  final String note;
  @override
  State<_TimeNoteDialog> createState() => _TimeNoteDialogState();
}

class _TimeNoteDialogState extends State<_TimeNoteDialog> {
  late final _text = TextEditingController(text: widget.note);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.work_time_note),
    content: TextField(
      controller: _text,
      minLines: 3,
      maxLines: 6,
      autofocus: true,
      decoration: InputDecoration(labelText: context.l10n.notes),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_text.text.trim()),
        child: Text(context.l10n.save),
      ),
    ],
  );
}
