import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show HiveError;
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/express/express_surface.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/icons/habit_glyph.dart';
import 'package:streak/core/minimal/minimal_kit.dart';
import 'package:streak/core/utils/cover_storage.dart';
import 'package:streak/core/widgets/app_empty_state.dart';
import 'package:streak/core/widgets/cover_action_button.dart';
import 'package:streak/core/widgets/cover_image.dart';
import 'package:streak/core/widgets/delete_sheet.dart';
import 'package:streak/core/widgets/photo_deck.dart';
import 'package:streak/core/widgets/photo_viewer.dart';
import 'package:streak/core/widgets/section_label.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/todos/widgets/todo_labels.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_progress.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';

enum WorkOverviewFilter { all, today, inbox, overdue, archive }

const List<String> workIconChoices = [
  'briefcase',
  'target',
  'calendarDays',
  'clock',
  'folder',
  'folderOpen',
  'clipboardCheck',
  'rocket',
  'code',
  'chartBar',
  'building',
  'inbox',
  'notebookTabs',
  'mail',
  'phone',
  'handCoins',
];

String workOverviewLabel(BuildContext context, WorkOverviewFilter filter) =>
    switch (filter) {
      WorkOverviewFilter.all => context.l10n.all,
      WorkOverviewFilter.today => context.l10n.today,
      WorkOverviewFilter.inbox => context.l10n.work_inbox,
      WorkOverviewFilter.overdue => context.l10n.work_overdue,
      WorkOverviewFilter.archive => context.l10n.work_archive,
    };

IconData workOverviewIcon(WorkOverviewFilter filter) => switch (filter) {
  WorkOverviewFilter.all => LucideIcons.listFilter,
  WorkOverviewFilter.today => LucideIcons.calendarCheck,
  WorkOverviewFilter.inbox => LucideIcons.inbox,
  WorkOverviewFilter.overdue => LucideIcons.triangleAlert,
  WorkOverviewFilter.archive => LucideIcons.archive,
};

String workAreaTypeLabel(BuildContext context, WorkAreaType type) =>
    switch (type) {
      WorkAreaType.company => context.l10n.work_area_type_company,
      WorkAreaType.client => context.l10n.work_area_type_client,
      WorkAreaType.independent => context.l10n.work_area_type_independent,
    };

IconData workAreaTypeIcon(WorkAreaType type) => switch (type) {
  WorkAreaType.company => LucideIcons.building2,
  WorkAreaType.client => LucideIcons.handshake,
  WorkAreaType.independent => LucideIcons.sparkles,
};

String workProjectStatusLabel(BuildContext context, WorkProjectStatus status) =>
    switch (status) {
      WorkProjectStatus.planned => context.l10n.work_project_status_planned,
      WorkProjectStatus.active => context.l10n.work_project_status_active,
      WorkProjectStatus.onHold => context.l10n.work_project_status_on_hold,
      WorkProjectStatus.done => context.l10n.work_project_status_done,
      WorkProjectStatus.cancelled => context.l10n.work_project_status_cancelled,
    };

IconData workProjectStatusIcon(WorkProjectStatus status) => switch (status) {
  WorkProjectStatus.planned => LucideIcons.flag,
  WorkProjectStatus.active => LucideIcons.play,
  WorkProjectStatus.onHold => LucideIcons.pause,
  WorkProjectStatus.done => LucideIcons.circleCheck,
  WorkProjectStatus.cancelled => LucideIcons.circleSlash,
};

String workTaskStatusLabel(BuildContext context, WorkTaskStatus status) =>
    switch (status) {
      WorkTaskStatus.notStarted => context.l10n.work_task_status_not_started,
      WorkTaskStatus.inProgress => context.l10n.work_task_status_in_progress,
      WorkTaskStatus.blocked => context.l10n.work_task_status_blocked,
      WorkTaskStatus.done => context.l10n.work_task_status_done,
      WorkTaskStatus.cancelled => context.l10n.work_task_status_cancelled,
    };

IconData workTaskStatusIcon(WorkTaskStatus status) => switch (status) {
  WorkTaskStatus.notStarted => LucideIcons.circle,
  WorkTaskStatus.inProgress => LucideIcons.play,
  WorkTaskStatus.blocked => LucideIcons.hand,
  WorkTaskStatus.done => LucideIcons.circleCheck,
  WorkTaskStatus.cancelled => LucideIcons.circleSlash,
};

String workTaskSortLabel(BuildContext context, WorkTaskSort sort) =>
    switch (sort) {
      WorkTaskSort.manual => context.l10n.work_sort_manual,
      WorkTaskSort.dueDate => context.l10n.work_sort_due_date,
      WorkTaskSort.priority => context.l10n.work_sort_priority,
    };

Color workTaskStatusColor(BuildContext context, WorkTaskStatus status) {
  final tokens = context.tokens;
  return switch (status) {
    WorkTaskStatus.notStarted => context.colors.primary,
    WorkTaskStatus.inProgress => tokens.info,
    WorkTaskStatus.blocked => tokens.warning,
    WorkTaskStatus.done => tokens.success,
    WorkTaskStatus.cancelled => tokens.muted,
  };
}

Color workProjectStatusColor(BuildContext context, WorkProjectStatus status) {
  final tokens = context.tokens;
  return switch (status) {
    WorkProjectStatus.planned => context.colors.primary,
    WorkProjectStatus.active => tokens.info,
    WorkProjectStatus.onHold => tokens.warning,
    WorkProjectStatus.done => tokens.success,
    WorkProjectStatus.cancelled => tokens.muted,
  };
}

String workDueLabel(BuildContext context, WorkTask task) {
  if (task.dueDate == null) return context.l10n.work_due_none;
  final date = parseDayKey(task.dueDate!);
  final locale = Localizations.localeOf(context).toString();
  final day = DateFormat.MMMd(locale).format(date);
  if (task.dueMinute == null) {
    return context.l10n.work_due_on(day);
  }
  final time = TimeOfDay(
    hour: task.dueMinute! ~/ 60,
    minute: task.dueMinute! % 60,
  ).format(context);
  return context.l10n.work_due_on_time(day, time);
}

String workDateLabel(BuildContext context, String? dayKey) {
  if (dayKey == null || dayKey.isEmpty) return context.l10n.work_none;
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMMd(locale).format(parseDayKey(dayKey));
}

String workTimestampLabel(BuildContext context, DateTime value) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMd(locale).add_jm().format(value.toLocal());
}

String workEntryDateLabel(BuildContext context, WorkEntry entry) {
  final locale = Localizations.localeOf(context).toString();
  final day = DateFormat.yMMMd(locale).format(parseDayKey(entry.date));
  final time = DateFormat.jm(locale).format(entry.meta.createdAt.toLocal());
  return '$day • $time';
}

String workScopeLabel(
  BuildContext context,
  WorkController controller, {
  String? areaId,
  String? projectId,
  String? parentTaskId,
}) {
  final parent = parentTaskId == null
      ? null
      : controller.taskById(parentTaskId);
  if (parent != null) {
    return context.l10n.work_scope_subtask(parent.title);
  }
  final project = projectId == null ? null : controller.projectById(projectId);
  if (project != null) {
    final area = project.areaId == null
        ? null
        : controller.areaById(project.areaId!);
    if (area != null) {
      return context.l10n.work_scope_project_area(project.name, area.name);
    }
    return context.l10n.work_scope_project(project.name);
  }
  final area = areaId == null ? null : controller.areaById(areaId);
  if (area != null) return context.l10n.work_scope_area(area.name);
  return context.l10n.work_scope_inbox;
}

String workTaskContextLabel(
  BuildContext context,
  WorkController controller,
  WorkTask task,
) {
  final parent = task.parentTaskId == null
      ? null
      : controller.taskById(task.parentTaskId!);
  final project = task.projectId == null
      ? null
      : controller.projectById(task.projectId!);
  final areaId = controller.areaForTask(task);
  final area = areaId == null ? null : controller.areaById(areaId);
  final parts = <String>[
    if (parent != null) context.l10n.work_parent(parent.title),
    if (project != null) project.name,
    if (area != null) area.name,
  ];
  if (parts.isEmpty) return context.l10n.work_scope_inbox;
  return parts.join(' • ');
}

String workProjectContextLabel(
  BuildContext context,
  WorkController controller,
  WorkProject project,
) {
  final area = project.areaId == null
      ? null
      : controller.areaById(project.areaId!);
  if (area == null) return context.l10n.work_scope_unassigned;
  return area.name;
}

double? workTaskFraction(WorkController controller, WorkTask task) {
  return WorkProgress.of(controller.data.tasks, taskIds: [task.id]).fraction;
}

int workTaskLeafCount(WorkController controller, WorkTask task) {
  return WorkProgress.of(controller.data.tasks, taskIds: [task.id]).total;
}

String workProgressLabel(BuildContext context, double? fraction) {
  if (fraction == null) return context.l10n.work_progress_none;
  return context.l10n.work_progress_percent((fraction * 100).round());
}

String workTaskActivityLabel(
  BuildContext context,
  WorkController controller,
  WorkEntry entry,
) {
  switch (entry.kind) {
    case WorkEntryKind.note:
      return context.l10n.notes;
    case WorkEntryKind.progress:
      final from = entry.previousValue == null
          ? null
          : context.l10n.work_progress_percent(entry.previousValue!.round());
      final to = context.l10n.work_progress_percent(entry.value!.round());
      if (from == null) return context.l10n.work_activity_progress_to(to);
      return context.l10n.work_activity_progress_from_to(from, to);
    case WorkEntryKind.statusChange:
      final current = _statusLabelFromName(
        context,
        entry.status ?? '',
        entry.entityKind,
      );
      if (entry.previousStatus == null || entry.previousStatus!.isEmpty) {
        return context.l10n.work_activity_status_to(current);
      }
      final previous = _statusLabelFromName(
        context,
        entry.previousStatus!,
        entry.entityKind,
      );
      return context.l10n.work_activity_status_from_to(previous, current);
    case WorkEntryKind.scopeChange:
      return context.l10n.work_activity_scope_changed;
  }
}

String _statusLabelFromName(
  BuildContext context,
  String value,
  WorkEntityKind kind,
) {
  if (kind == WorkEntityKind.project) {
    return switch (value) {
      'planned' => context.l10n.work_project_status_planned,
      'active' => context.l10n.work_project_status_active,
      'onHold' => context.l10n.work_project_status_on_hold,
      'done' => context.l10n.work_project_status_done,
      'cancelled' => context.l10n.work_project_status_cancelled,
      _ => context.l10n.work_unknown_status,
    };
  }
  return switch (value) {
    'notStarted' => context.l10n.work_task_status_not_started,
    'inProgress' => context.l10n.work_task_status_in_progress,
    'blocked' => context.l10n.work_task_status_blocked,
    'done' => context.l10n.work_task_status_done,
    'cancelled' => context.l10n.work_task_status_cancelled,
    _ => context.l10n.work_unknown_status,
  };
}

String? workErrorMessage(BuildContext context, Object error) {
  if (error is WorkOperationException) {
    return switch (error.code) {
      WorkFailure.missing => context.l10n.work_error_missing,
      WorkFailure.stale => context.l10n.work_error_stale,
      WorkFailure.invalidScope => context.l10n.work_error_invalid_scope,
      WorkFailure.invalidParent => context.l10n.work_error_invalid_parent,
      WorkFailure.linkedGoal => context.l10n.work_error_linked_goal,
      WorkFailure.openSubtasks => context.l10n.work_error_open_subtasks(
        error.count,
      ),
      WorkFailure.closedParent => context.l10n.work_error_closed_parent,
      WorkFailure.archivedParent => context.l10n.work_error_archived_parent,
      WorkFailure.invalidProgress => context.l10n.work_error_invalid_progress,
      WorkFailure.invalidNote => context.l10n.work_error_invalid_note,
    };
  }
  if (error is ArgumentError ||
      error is StateError ||
      error is FileSystemException ||
      error is HiveError ||
      error is PlatformException) {
    return context.l10n.work_action_failed;
  }
  return null;
}

Future<bool> runWorkAction(
  BuildContext context,
  Future<void> Function() action, {
  ValueChanged<Object>? onError,
}) async {
  void report(Object error) {
    debugPrint('Work action failed: $error');
    if (onError != null) {
      onError(error);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            workErrorMessage(context, error) ?? context.l10n.work_action_failed,
          ),
        ),
      );
    }
  }

  try {
    await action();
    return true;
  } on WorkOperationException catch (error) {
    report(error);
  } on ArgumentError catch (error) {
    report(error);
  } on StateError catch (error) {
    report(error);
  } on FileSystemException catch (error) {
    report(error);
  } on HiveError catch (error) {
    report(error);
  } on PlatformException catch (error) {
    report(error);
  }
  return false;
}

Future<String?> showWorkTitleDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required String confirmLabel,
}) => showDialog<String>(
  context: context,
  builder: (_) => _WorkTitleDialog(
    title: title,
    initialValue: initialValue,
    confirmLabel: confirmLabel,
  ),
);

class _WorkTitleDialog extends StatefulWidget {
  const _WorkTitleDialog({
    required this.title,
    required this.initialValue,
    required this.confirmLabel,
  });
  final String title;
  final String initialValue;
  final String confirmLabel;
  @override
  State<_WorkTitleDialog> createState() => _WorkTitleDialogState();
}

class _WorkTitleDialogState extends State<_WorkTitleDialog> {
  late final _text = TextEditingController(text: widget.initialValue);
  final _form = GlobalKey<FormState>();
  final _focus = FocusNode();
  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) {
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.work_title),
        validator: (value) => value == null || value.trim().isEmpty
            ? context.l10n.work_title_required
            : null,
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(onPressed: _save, child: Text(widget.confirmLabel)),
    ],
  );
}

class WorkCard extends StatelessWidget {
  const WorkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
    this.color,
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    if (settings.isMinimalStyle) {
      return _interactive(
        context,
        MinimalCard(
          radius: radius,
          padding: EdgeInsets.zero,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor!, width: 1),
              color: color,
            ),
            padding: padding,
            child: child,
          ),
        ),
      );
    }
    if (settings.isExpressStyle) {
      return _interactive(
        context,
        ExpressCard(
          radius: radius,
          color: color,
          padding: padding,
          child: child,
        ),
      );
    }
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: color ?? context.colors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color:
              borderColor ??
              context.colors.outlineVariant.withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
    return _interactive(context, body);
  }

  Widget _interactive(BuildContext context, Widget body) {
    if (onTap == null) return body;
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        foregroundColor: WidgetStatePropertyAll(context.colors.onSurface),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: context.colors.onSurface, width: 2)
              : BorderSide.none,
        ),
      ),
      child: body,
    );
  }
}

class WorkPageHeader extends StatelessWidget {
  const WorkPageHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    if (settings.isMinimalStyle) {
      return MinimalTitle(title: title, subtitle: subtitle);
    }
    if (settings.isExpressStyle) {
      return ExpressHeadline(title: title, subtitle: subtitle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: context.colors.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: sheetBodyStyle(context, size: 14.5)),
        ],
      ],
    );
  }
}

class WorkBadge extends StatelessWidget {
  const WorkBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final background = Color.alphaBlend(color, context.colors.surface);
    final luminance = background.computeLuminance();
    final foreground = (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
        ? Colors.black
        : Colors.white;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkTitleText extends StatelessWidget {
  const WorkTitleText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 2,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class WorkSection extends StatelessWidget {
  const WorkSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.gap = 12,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(title, trailing: trailing),
          child,
        ],
      ),
    );
  }
}

class WorkQuickAddCard extends StatefulWidget {
  const WorkQuickAddCard({
    super.key,
    required this.areaId,
    required this.projectId,
    required this.parentTaskId,
    required this.emptyHint,
    this.onSaved,
  });

  final String? areaId;
  final String? projectId;
  final String? parentTaskId;
  final String emptyHint;
  final ValueChanged<WorkTask>? onSaved;

  @override
  State<WorkQuickAddCard> createState() => _WorkQuickAddCardState();
}

class _WorkQuickAddCardState extends State<WorkQuickAddCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = context.l10n.work_title_required);
      _focus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final work = context.read<WorkController>();
    await runWorkAction(
      context,
      () async {
        final saved = await work.saveTask(
          WorkTask(
            meta: WorkController.newMeta(),
            title: text,
            areaId: widget.areaId,
            projectId: widget.projectId,
            parentTaskId: widget.parentTaskId,
          ),
        );
        if (!mounted) return;
        setState(() {
          _saving = false;
          _controller.clear();
        });
        widget.onSaved?.call(saved);
        _focus.requestFocus();
      },
      onError: (error) {
        if (!mounted) return;
        final message = workErrorMessage(context, error);
        setState(() {
          _saving = false;
          _error = message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WorkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.work_quick_add,
            style: sheetHeadingStyle(context),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('work-quick-add-field'),
            controller: _controller,
            focusNode: _focus,
            onSubmitted: _saving ? null : (_) => _save(),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.l10n.work_title,
              hintText: widget.emptyHint,
              errorText: _error,
              prefixIcon: const Icon(LucideIcons.plus),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
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
                  : const Icon(LucideIcons.plus, size: 18),
              label: Text(context.l10n.work_add_task),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkTaskList extends StatelessWidget {
  const WorkTaskList({
    super.key,
    required this.tasks,
    required this.onOpen,
    required this.emptyTitle,
    this.emptyMessage,
    this.emptyAction,
    this.showChildren = true,
    this.sort = WorkTaskSort.manual,
    this.allowReorder = false,
  });

  final List<WorkTask> tasks;
  final ValueChanged<WorkTask> onOpen;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;
  final bool showChildren;
  final WorkTaskSort sort;
  final bool allowReorder;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return AppEmptyState(
        icon: LucideIcons.listChecks,
        title: emptyTitle,
        message: emptyMessage,
        compact: true,
        action: emptyAction,
      );
    }
    final work = context.watch<WorkController>();
    final now = AppClock.wallNow();
    return Column(
      children: [
        for (var index = 0; index < tasks.length; index++) ...[
          _WorkTaskTile(
            task: tasks[index],
            now: now,
            showChildren: showChildren,
            sort: sort,
            onOpen: onOpen,
            controller: work,
          ),
          if (allowReorder && sort == WorkTaskSort.manual && tasks.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: context.l10n.work_move_up,
                  onPressed: index == 0
                      ? null
                      : () {
                          final ids = tasks.map((task) => task.id).toList();
                          final previous = ids[index - 1];
                          ids[index - 1] = ids[index];
                          ids[index] = previous;
                          runWorkAction(
                            context,
                            () => work.reorderTasks(
                              ids,
                              expectedRevision: work.data.revision,
                            ),
                          );
                        },
                  icon: const Icon(LucideIcons.arrowUp, size: 18),
                ),
                IconButton(
                  tooltip: context.l10n.work_move_down,
                  onPressed: index == tasks.length - 1
                      ? null
                      : () {
                          final ids = tasks.map((task) => task.id).toList();
                          final next = ids[index + 1];
                          ids[index + 1] = ids[index];
                          ids[index] = next;
                          runWorkAction(
                            context,
                            () => work.reorderTasks(
                              ids,
                              expectedRevision: work.data.revision,
                            ),
                          );
                        },
                  icon: const Icon(LucideIcons.arrowDown, size: 18),
                ),
              ],
            ),
          if (index < tasks.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _WorkTaskTile extends StatelessWidget {
  const _WorkTaskTile({
    required this.task,
    required this.controller,
    required this.onOpen,
    required this.now,
    required this.showChildren,
    required this.sort,
  });

  final WorkTask task;
  final WorkController controller;
  final ValueChanged<WorkTask> onOpen;
  final DateTime now;
  final bool showChildren;
  final WorkTaskSort sort;

  @override
  Widget build(BuildContext context) {
    final archived = controller.isTaskArchived(task);
    final children = showChildren
        ? controller.tasks(
            parentTaskId: task.id,
            archived: archived,
            includeDone: true,
            sort: sort,
          )
        : const <WorkTask>[];
    final fraction = workTaskFraction(controller, task);
    final overdue = !archived && controller.isOverdue(task, now);
    final blocked = task.status == WorkTaskStatus.blocked;
    final badges = <Widget>[
      WorkBadge(
        icon: workTaskStatusIcon(task.status),
        label: workTaskStatusLabel(context, task.status),
        color: workTaskStatusColor(context, task.status),
      ),
      if (task.priority != TodoPriority.none)
        WorkBadge(
          icon: LucideIcons.flag,
          label: todoPriorityLabels(context)[task.priority.index],
          color: todoPriorityColor(context, task.priority),
        ),
      if (overdue)
        WorkBadge(
          icon: LucideIcons.triangleAlert,
          label: context.l10n.work_due_badge,
          color: context.tokens.danger,
        ),
      if (archived)
        WorkBadge(
          icon: LucideIcons.archive,
          label: context.l10n.work_archive,
          color: context.tokens.muted,
        ),
    ];

    return WorkCard(
      key: ValueKey('work-task-${task.id}'),
      onTap: () => onOpen(task),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WorkTitleText(
                      task.title,
                      style: sheetHeadingStyle(context, size: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      workTaskContextLabel(context, controller, task),
                      style: sheetBodyStyle(context, size: 13.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: context.tokens.muted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: badges),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: fraction ?? 0,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: context.colors.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                workProgressLabel(context, fraction),
                style: sheetBodyStyle(context, size: 13),
              ),
              if (task.dueDate != null)
                Text(
                  workDueLabel(context, task),
                  style: sheetBodyStyle(
                    context,
                    size: 13,
                    color: overdue ? context.tokens.danger : null,
                  ),
                ),
              if (task.estimatedMinutes != null)
                Text(
                  context.l10n.work_estimate_minutes(task.estimatedMinutes!),
                  style: sheetBodyStyle(context, size: 13),
                ),
            ],
          ),
          if (task.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              task.description.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: sheetBodyStyle(context, size: 14),
            ),
          ],
          if (blocked && task.blockedReason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              task.blockedReason.trim(),
              style: sheetBodyStyle(
                context,
                size: 14,
                color: context.tokens.warning,
              ),
            ),
          ],
          if (children.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              context.l10n.work_subtasks_count(children.length),
              style: sheetLabelStyle(context),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  _WorkSubtaskRow(task: children[index], onOpen: onOpen),
                  if (index < children.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkSubtaskRow extends StatelessWidget {
  const _WorkSubtaskRow({required this.task, required this.onOpen});

  final WorkTask task;
  final ValueChanged<WorkTask> onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('work-subtask-${task.id}'),
      color: context.colors.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onOpen(task),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(
                workTaskStatusIcon(task.status),
                size: 18,
                color: workTaskStatusColor(context, task.status),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WorkTitleText(
                  task.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.onSurface,
                  ),
                  maxLines: 1,
                ),
              ),
              if (task.progressMode == WorkTaskProgress.manual)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10),
                  child: Text(
                    context.l10n.work_progress_percent(task.progress.round()),
                    style: sheetBodyStyle(context),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: context.tokens.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkEntityHero extends StatelessWidget {
  const WorkEntityHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badges,
    this.description,
    this.coverPath = '',
    this.glyph = 'briefcase',
    this.tint,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final List<Widget> badges;
  final String? description;
  final String coverPath;
  final String glyph;
  final Color? tint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? context.colors.primary;
    final hasCover = CoverImage.exists(coverPath);
    return WorkCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              color: color.withValues(alpha: 0.10),
            ),
            child: AspectRatio(
              aspectRatio: 2.7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasCover) CoverImage(path: coverPath),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: hasCover
                            ? [
                                Colors.black.withValues(alpha: 0.14),
                                Colors.black.withValues(alpha: 0.58),
                              ]
                            : [
                                color.withValues(alpha: 0.18),
                                color.withValues(alpha: 0.05),
                              ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      18,
                      18,
                      18,
                      18,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: hasCover
                              ? Colors.black.withValues(alpha: 0.34)
                              : color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: HabitGlyph(
                          glyph: glyph,
                          size: 28,
                          color: hasCover ? Colors.white : color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WorkTitleText(
                            title,
                            style: sheetTitleStyle(context, size: 22),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: sheetBodyStyle(context, size: 14),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing!,
                    ],
                  ],
                ),
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: badges),
                ],
                if (description != null && description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    description!.trim(),
                    style: sheetBodyStyle(context, size: 14.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WorkMetaList extends StatelessWidget {
  const WorkMetaList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return WorkCard(
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1)
              Divider(
                height: 20,
                color: context.colors.outlineVariant.withValues(alpha: 0.24),
              ),
          ],
        ],
      ),
    );
  }
}

class WorkMetaTile extends StatelessWidget {
  const WorkMetaTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 2),
          child: Icon(icon, size: 18, color: context.tokens.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: sheetLabelStyle(context)),
              const SizedBox(height: 3),
              SelectableText(
                value,
                style: sheetBodyStyle(
                  context,
                  size: 14.5,
                  color: context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class WorkPhotoStrip extends StatelessWidget {
  const WorkPhotoStrip({
    super.key,
    required this.photos,
    required this.accent,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  final List<String> photos;
  final Color accent;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _WorkAddTile(
          icon: LucideIcons.camera,
          label: context.l10n.note_take_photo,
          accent: accent,
          onTap: onCamera,
        ),
        _WorkAddTile(
          icon: LucideIcons.image,
          label: context.l10n.note_pick_photo,
          accent: accent,
          onTap: onGallery,
        ),
        if (photos.isNotEmpty)
          PhotoDeck(
            shots: [for (final path in photos) PhotoShot(path: path)],
            onRemove: (index) => onRemove(photos[index]),
          ),
      ],
    );
  }
}

class _WorkAddTile extends StatelessWidget {
  const _WorkAddTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final express = context.watch<SettingsController>().isExpressStyle;
    final child = Container(
      constraints: const BoxConstraints(minWidth: 92, minHeight: 92),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: express
            ? accent.withValues(alpha: 0.12)
            : context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(express ? 26 : 18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: express ? accent : context.tokens.muted),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sheetBodyStyle(
              context,
              size: 12,
              color: express ? accent : context.tokens.muted,
            ),
          ),
        ],
      ),
    );
    if (express) {
      return ExpressSquish(onTap: onTap, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class WorkCoverField extends StatelessWidget {
  const WorkCoverField({
    super.key,
    required this.coverPath,
    required this.accent,
    required this.onCamera,
    required this.onGallery,
    required this.onClear,
  });

  final String coverPath;
  final Color accent;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasCover = CoverImage.exists(coverPath);
    return WorkCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover)
              CoverImage(path: coverPath)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.18),
                      accent.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.imagePlus,
                    size: 34,
                    color: accent,
                  ),
                ),
              ),
            PositionedDirectional(
              end: 12,
              bottom: 12,
              child: Row(
                children: [
                  CoverActionButton(
                    icon: LucideIcons.camera,
                    label: context.l10n.note_take_photo,
                    onTap: onCamera,
                  ),
                  const SizedBox(width: 8),
                  CoverActionButton(
                    icon: LucideIcons.image,
                    label: context.l10n.note_pick_photo,
                    onTap: onGallery,
                  ),
                  if (hasCover) ...[
                    const SizedBox(width: 8),
                    CoverActionButton(
                      icon: LucideIcons.trash2,
                      label: context.l10n.delete,
                      onTap: onClear,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<WorkEntry?> showWorkNoteEditor(
  BuildContext context, {
  required WorkEntityKind kind,
  required String entityId,
  WorkEntry? existing,
}) {
  return showModalBottomSheet<WorkEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: _WorkNoteEditor(
        kind: kind,
        entityId: entityId,
        existing: existing,
      ),
    ),
  );
}

class _WorkNoteEditor extends StatefulWidget {
  const _WorkNoteEditor({
    required this.kind,
    required this.entityId,
    this.existing,
  });

  final WorkEntityKind kind;
  final String entityId;
  final WorkEntry? existing;

  @override
  State<_WorkNoteEditor> createState() => _WorkNoteEditorState();
}

class _WorkNoteEditorState extends State<_WorkNoteEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.existing?.text ?? '',
  );
  late final List<String> _photos = [...?widget.existing?.photos];
  late String _date = widget.existing?.date ?? AppClock.today().dayKey;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseDayKey(_date),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked.dayKey);
    }
  }

  Future<void> _addPhoto({bool fromCamera = false}) async {
    final path = await CoverStorage.store(
      folder: 'work',
      fromCamera: fromCamera,
    );
    if (path != null && mounted) {
      setState(() => _photos.add(path));
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    await runWorkAction(
      context,
      () async {
        final saved = await context.read<WorkController>().saveNote(
          kind: widget.kind,
          entityId: widget.entityId,
          text: _text.text,
          photos: _photos,
          date: _date,
          existing: widget.existing,
        );
        if (!mounted) return;
        Navigator.of(context).pop(saved);
      },
      onError: (error) {
        if (!mounted) return;
        final message = workErrorMessage(context, error);
        setState(() {
          _saving = false;
          _error = message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
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
                    ? context.l10n.work_add_note
                    : context.l10n.work_edit_note,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('work-note-field'),
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.l10n.notes,
                  hintText: context.l10n.work_note_hint,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.work_note_date,
                style: sheetLabelStyle(context),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickDate,
                icon: const Icon(LucideIcons.calendarDays, size: 18),
                label: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(workDateLabel(context, _date)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.note_photos,
                style: sheetLabelStyle(context),
              ),
              const SizedBox(height: 8),
              WorkPhotoStrip(
                photos: _photos,
                accent: accent,
                onCamera: _saving ? () {} : () => _addPhoto(fromCamera: true),
                onGallery: _saving ? () {} : _addPhoto,
                onRemove: (path) => setState(() => _photos.remove(path)),
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
            ],
          ),
        ),
      ),
    );
  }
}

class WorkEntriesSection extends StatelessWidget {
  const WorkEntriesSection({
    super.key,
    required this.kind,
    required this.entityId,
  });

  final WorkEntityKind kind;
  final String entityId;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final entries = work.entriesFor(kind, entityId);
    final notes = entries
        .where((entry) => entry.kind == WorkEntryKind.note)
        .toList();
    final activity = entries
        .where((entry) => entry.kind != WorkEntryKind.note)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkSection(
          title: context.l10n.notes,
          trailing: TextButton.icon(
            onPressed: () =>
                showWorkNoteEditor(context, kind: kind, entityId: entityId),
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text(context.l10n.work_add_note),
          ),
          child: notes.isEmpty
              ? AppEmptyState(
                  icon: LucideIcons.notebookPen,
                  title: context.l10n.work_notes_empty,
                  message: context.l10n.work_notes_empty_sub,
                  compact: true,
                )
              : Column(
                  children: [
                    for (var index = 0; index < notes.length; index++) ...[
                      _WorkNoteTile(entry: notes[index], kind: kind),
                      if (index < notes.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
        WorkSection(
          title: context.l10n.work_activity,
          child: activity.isEmpty
              ? AppEmptyState(
                  icon: LucideIcons.history,
                  title: context.l10n.work_activity_empty,
                  message: context.l10n.work_activity_empty_sub,
                  compact: true,
                )
              : Column(
                  children: [
                    for (var index = 0; index < activity.length; index++) ...[
                      _WorkActivityTile(entry: activity[index]),
                      if (index < activity.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _WorkNoteTile extends StatelessWidget {
  const _WorkNoteTile({required this.entry, required this.kind});

  final WorkEntry entry;
  final WorkEntityKind kind;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDeleteSheet(context);
    if (!confirmed || !context.mounted) return;
    await runWorkAction(
      context,
      () => context.read<WorkController>().removeNote(entry.id),
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
              IconButton(
                tooltip: context.l10n.edit_note,
                onPressed: () => showWorkNoteEditor(
                  context,
                  kind: kind,
                  entityId: entry.entityId,
                  existing: entry,
                ),
                icon: const Icon(LucideIcons.pencil, size: 18),
              ),
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

class _WorkActivityTile extends StatelessWidget {
  const _WorkActivityTile({required this.entry});

  final WorkEntry entry;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
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
                WorkEntryKind.scopeChange => LucideIcons.moveRight,
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
                Text(
                  workTaskActivityLabel(context, work, entry),
                  style: sheetHeadingStyle(context, size: 14.5),
                ),
                const SizedBox(height: 4),
                Text(
                  workEntryDateLabel(context, entry),
                  style: sheetBodyStyle(context, size: 13),
                ),
                if (entry.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    entry.text.trim(),
                    style: sheetBodyStyle(context, size: 14),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
