import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/utils/cover_storage.dart';
import 'package:streak/core/widgets/app_empty_state.dart';
import 'package:streak/core/widgets/delete_sheet.dart';
import 'package:streak/core/widgets/photo_deck.dart';
import 'package:streak/core/widgets/photo_viewer.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/goals/widgets/goal_ui.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

class GoalHistory extends StatelessWidget {
  const GoalHistory({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    final entries = goals.entriesFor(goal.id);
    final notes = entries
        .where((entry) => entry.kind == WorkEntryKind.note)
        .toList();
    final history = entries
        .where((entry) => entry.kind != WorkEntryKind.note)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkSection(
          title: context.l10n.notes,
          trailing: goal.isArchived
              ? null
              : TextButton.icon(
                  onPressed: () => showGoalNoteEditor(context, goal),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text(context.l10n.goal_note_add),
                ),
          child: notes.isEmpty
              ? AppEmptyState(
                  icon: LucideIcons.notebookPen,
                  title: context.l10n.goal_notes_empty,
                  message: context.l10n.goal_notes_empty_sub,
                  compact: true,
                )
              : Column(
                  children: [
                    for (var index = 0; index < notes.length; index++) ...[
                      _GoalNoteTile(goal: goal, entry: notes[index]),
                      if (index < notes.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
        WorkSection(
          title: context.l10n.goal_history,
          child: history.isEmpty
              ? AppEmptyState(
                  icon: LucideIcons.history,
                  title: context.l10n.goal_history_empty,
                  message: context.l10n.goal_history_empty_sub,
                  compact: true,
                )
              : Column(
                  children: [
                    for (var index = 0; index < history.length; index++) ...[
                      _GoalHistoryTile(goal: goal, entry: history[index]),
                      if (index < history.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

Future<WorkEntry?> showGoalNoteEditor(
  BuildContext context,
  Goal goal, {
  WorkEntry? existing,
}) {
  return showModalBottomSheet<WorkEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: _GoalNoteEditor(goal: goal, existing: existing),
    ),
  );
}

class _GoalNoteEditor extends StatefulWidget {
  const _GoalNoteEditor({required this.goal, this.existing});

  final Goal goal;
  final WorkEntry? existing;

  @override
  State<_GoalNoteEditor> createState() => _GoalNoteEditorState();
}

class _GoalNoteEditorState extends State<_GoalNoteEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.existing?.text ?? '',
  );
  late final List<String> _photos = [...?widget.existing?.photos];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _addPhoto({bool fromCamera = false}) async {
    final path = await CoverStorage.store(
      folder: 'work',
      fromCamera: fromCamera,
    );
    if (path != null && mounted) setState(() => _photos.add(path));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    await runGoalAction(
      context,
      () async {
        final saved = await context.read<GoalsController>().saveNote(
          widget.goal,
          _text.text,
          existing: widget.existing,
          photos: _photos,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitle(
                widget.existing == null
                    ? context.l10n.goal_note_add
                    : context.l10n.goal_note_edit,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('goal-note-field'),
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.l10n.notes,
                  hintText: context.l10n.goal_note_hint,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.note_photos, style: sheetLabelStyle(context)),
              const SizedBox(height: 8),
              ExcludeFocus(
                excluding: _saving,
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: Opacity(
                    opacity: _saving ? .5 : 1,
                    child: WorkPhotoStrip(
                      photos: _photos,
                      accent: context.colors.primary,
                      onCamera: () => _addPhoto(fromCamera: true),
                      onGallery: _addPhoto,
                      onRemove: (path) => setState(() => _photos.remove(path)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
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
}

class _GoalNoteTile extends StatelessWidget {
  const _GoalNoteTile({required this.goal, required this.entry});

  final Goal goal;
  final WorkEntry entry;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDeleteSheet(context);
    if (!confirmed || !context.mounted) return;
    await runGoalAction(
      context,
      () => context.read<GoalsController>().removeNote(entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WorkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  workEntryDateLabel(context, entry),
                  style: sheetLabelStyle(context),
                ),
              ),
              if (!goal.isArchived)
                IconButton(
                  tooltip: context.l10n.edit_note,
                  onPressed: () =>
                      showGoalNoteEditor(context, goal, existing: entry),
                  icon: const Icon(LucideIcons.pencil, size: 18),
                ),
              if (!goal.isArchived)
                IconButton(
                  tooltip: context.l10n.delete,
                  onPressed: () => _delete(context),
                  icon: const Icon(LucideIcons.trash2, size: 18),
                ),
            ],
          ),
          if (entry.text.trim().isNotEmpty)
            Text(entry.text.trim(), style: sheetBodyStyle(context, size: 14.5)),
          if (entry.photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            PhotoDeck(
              shots: [
                for (final path in entry.photos)
                  PhotoShot(path: path, day: entry.date),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalHistoryTile extends StatelessWidget {
  const _GoalHistoryTile({required this.goal, required this.entry});

  final Goal goal;
  final WorkEntry entry;

  @override
  Widget build(BuildContext context) {
    final title = _entryTitle(context);
    return WorkCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              switch (entry.kind) {
                WorkEntryKind.progress => LucideIcons.gauge,
                WorkEntryKind.statusChange => LucideIcons.refreshCcw,
                WorkEntryKind.scopeChange => LucideIcons.link,
                WorkEntryKind.note => LucideIcons.notebookPen,
              },
              size: 18,
              color: context.colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: sheetHeadingStyle(context, size: 14.5)),
                const SizedBox(height: 4),
                Text(
                  workEntryDateLabel(context, entry),
                  style: sheetBodyStyle(context, size: 13),
                ),
                if (_visibleText.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _visibleText.trim(),
                    style: sheetBodyStyle(context, size: 14),
                  ),
                ],
                if (entry.kind == WorkEntryKind.progress &&
                    _entryMeasurement == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.goal_measurement_unknown,
                    style: sheetBodyStyle(context, size: 13),
                  ),
                ],
                if (_entryJson?['habitTitle'] case final String name
                    when name.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(name, style: sheetBodyStyle(context)),
                ],
                if (entry.kind == WorkEntryKind.scopeChange &&
                    _entryJson?['type'] == 'goal' &&
                    entry.measurementTarget != null &&
                    _entryMeasurement != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.goal_baseline_target(
                      _historyValueLabel(
                        context,
                        entry.measurementBaseline ?? 0,
                      ),
                      _historyValueLabel(context, entry.measurementTarget!),
                    ),
                    style: sheetBodyStyle(context, size: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _entryTitle(BuildContext context) {
    switch (entry.kind) {
      case WorkEntryKind.progress:
        final to = _historyValueLabel(context, entry.value ?? goal.current);
        final previous = entry.previousValue;
        if (previous == null) return context.l10n.goal_progress_to(to);
        return context.l10n.goal_progress_changed(
          _historyValueLabel(context, previous),
          to,
        );
      case WorkEntryKind.statusChange:
        final status = _statusFromName(entry.status);
        if (status == null) {
          return context.l10n.goal_status_to(context.l10n.status);
        }
        final previous = _statusFromName(entry.previousStatus);
        if (previous == null) {
          return context.l10n.goal_status_to(goalStatusLabel(context, status));
        }
        return context.l10n.goal_status_changed(
          goalStatusLabel(context, previous),
          goalStatusLabel(context, status),
        );
      case WorkEntryKind.scopeChange:
        final event = _entryJson;
        if (event?['type'] == 'habitLink') {
          return switch (event?['action']) {
            'add' => context.l10n.goal_link_added,
            'update' => context.l10n.goal_link_updated,
            'remove' => context.l10n.goal_link_removed,
            _ => context.l10n.goal_scope_changed,
          };
        }
        if (event?['type'] == 'goal' && event?['action'] == 'create') {
          return context.l10n.goal_created;
        }
        return context.l10n.goal_scope_changed;
      case WorkEntryKind.note:
        return context.l10n.notes;
    }
  }

  Map<String, dynamic>? get _entryJson {
    if (entry.kind != WorkEntryKind.scopeChange) return null;
    try {
      final value = jsonDecode(entry.text);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  String get _visibleText {
    final type = _entryJson?['type'];
    return type == 'goal' || type == 'habitLink' ? '' : entry.text;
  }

  String _historyValueLabel(BuildContext context, double value) {
    final measurement = _entryMeasurement;
    final unit = entry.measurementUnit.trim();
    if (measurement == null ||
        (unit.isEmpty &&
            (measurement == GoalMeasurement.number ||
                measurement == GoalMeasurement.currency))) {
      return goalNumberLabel(context, value);
    }
    return goalMeasurementValueLabel(
      context,
      measurement: measurement,
      value: value,
      unit: unit,
      target: entry.measurementTarget ?? 1,
    );
  }

  GoalMeasurement? get _entryMeasurement {
    if (entry.measurementKind.trim().isEmpty) return null;
    for (final value in GoalMeasurement.values) {
      if (value.name == entry.measurementKind) return value;
    }
    return null;
  }
}

GoalStatus? _statusFromName(String? value) {
  if (value == null || value.isEmpty) return null;
  for (final status in GoalStatus.values) {
    if (status.name == value) return status;
  }
  return null;
}
