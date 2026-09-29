import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/extensions/inset_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/app_confirm_dialog.dart';
import 'package:streak/core/widgets/app_empty_state.dart';
import 'package:streak/core/widgets/photo_deck.dart';
import 'package:streak/core/widgets/photo_viewer.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/focus/state/work_focus_actions.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/data/work_progress.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_destination_sheet.dart';
import 'package:streak/features/work/widgets/work_forms.dart';
import 'package:streak/features/work/widgets/work_ui.dart';
import 'package:streak/features/goals/widgets/related_goals_section.dart';
import 'package:streak/features/work/widgets/work_time_section.dart';
import 'package:streak/features/work/widgets/work_planning_section.dart';
import 'package:streak/features/todos/widgets/todo_labels.dart';

class WorkTaskPage extends StatefulWidget {
  const WorkTaskPage({super.key, required this.taskId});

  final String taskId;

  @override
  State<WorkTaskPage> createState() => _WorkTaskPageState();
}

class _WorkTaskPageState extends State<WorkTaskPage> {
  @override
  void dispose() {
    if (AppNavigator.paneItem.value == 'work-task:${widget.taskId}') {
      AppNavigator.paneItem.value = null;
    }
    super.dispose();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    await runWorkAction(context, action);
  }

  Future<void> _toggleStatus(WorkTask task) async {
    final work = context.read<WorkController>();
    if (task.status == WorkTaskStatus.done ||
        task.status == WorkTaskStatus.cancelled) {
      return _runAction(
        () => work.setTaskStatus(
          task.id,
          task.progress > 0
              ? WorkTaskStatus.inProgress
              : WorkTaskStatus.notStarted,
        ),
      );
    }
    final open = work.openSubtaskCount(task.id);
    if (open > 0) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: context.l10n.work_complete_task,
        message: context.l10n.work_complete_task_confirm(open),
        confirmLabel: context.l10n.work_complete_task,
        icon: LucideIcons.circleCheck,
        danger: false,
      );
      if (confirmed != true || !mounted) return;
      await _runAction(
        () => work.setTaskStatus(
          task.id,
          WorkTaskStatus.done,
          completeSubtasks: true,
        ),
      );
    } else {
      await _runAction(() => work.setTaskStatus(task.id, WorkTaskStatus.done));
    }
  }

  Future<void> _toggleArchive(WorkTask task) async {
    final archived = context.read<WorkController>().isTaskArchived(task);
    await _runAction(
      () => context.read<WorkController>().setArchived(
        WorkEntityKind.task,
        task.id,
        !archived,
      ),
    );
  }

  Future<void> _duplicate(WorkTask task) async {
    final title = await showWorkTitleDialog(
      context,
      title: context.l10n.work_duplicate_task,
      initialValue: context.l10n.work_copy_name(task.title),
      confirmLabel: context.l10n.work_duplicate_task,
    );
    if (title == null || !mounted) return;
    await _runAction(() async {
      final copy = await context.read<WorkController>().duplicateTask(
        task.id,
        title: title,
      );
      if (mounted) _openTask(copy.id);
    });
  }

  Future<void> _move(WorkTask task) async {
    final work = context.read<WorkController>();
    final destination = await showWorkDestinationPicker(
      context,
      areaId: work.areaForTask(task),
      projectId: task.projectId,
    );
    if (destination == null || !mounted) return;
    await _runAction(
      () => work.moveTask(
        task.id,
        areaId: destination.areaId,
        projectId: destination.projectId,
        parentTaskId: null,
      ),
    );
  }

  void _openTask(String taskId) {
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-task:$taskId';
    }
    AppNavigator.push(WorkTaskPage(taskId: taskId), fade: true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WorkController>(
      builder: (context, work, _) {
        final task = work.taskById(widget.taskId);
        if (task == null || task.isDeleted) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => AppNavigator.pop(),
          );
          return const SizedBox.shrink();
        }
        final archived = work.isTaskArchived(task);
        final children =
            work.data.tasks
                .where(
                  (child) => child.parentTaskId == task.id && !child.isDeleted,
                )
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order));
        final rollup = WorkProgress.of(work.data.tasks, taskIds: [task.id]);
        final fraction = workTaskFraction(work, task);
        final areaName = workScopeLabel(
          context,
          work,
          areaId: work.areaForTask(task),
          projectId: task.projectId,
          parentTaskId: task.parentTaskId,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(task.title, overflow: TextOverflow.ellipsis),
            actions: [
              if (!archived)
                IconButton(
                  tooltip: context.l10n.edit,
                  onPressed: () => showWorkTaskForm(context, task: task),
                  icon: const Icon(LucideIcons.pencil, size: 18),
                ),
              if (!archived)
                IconButton(
                  tooltip:
                      task.status == WorkTaskStatus.done ||
                          task.status == WorkTaskStatus.cancelled
                      ? context.l10n.work_reopen
                      : context.l10n.work_complete_task,
                  onPressed: () => _toggleStatus(task),
                  icon: Icon(
                    task.status == WorkTaskStatus.done ||
                            task.status == WorkTaskStatus.cancelled
                        ? LucideIcons.rotateCcw
                        : LucideIcons.circleCheck,
                    size: 18,
                  ),
                ),
              IconButton(
                tooltip: archived ? context.l10n.restore : context.l10n.archive,
                onPressed: () => _toggleArchive(task),
                icon: Icon(
                  archived ? LucideIcons.rotateCcw : LucideIcons.archive,
                  size: 18,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'duplicate':
                      _duplicate(task);
                    case 'move':
                      _move(task);
                  }
                },
                itemBuilder: (_) => [
                  if (!archived)
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Text(context.l10n.work_duplicate_task),
                    ),
                  if (!archived)
                    PopupMenuItem(
                      value: 'move',
                      child: Text(context.l10n.work_move),
                    ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: context.pagePadding(16, 8, 16, 32),
            children: [
              WorkEntityHero(
                title: task.title,
                subtitle: areaName,
                description: task.description,
                glyph: task.parentTaskId == null
                    ? 'clipboardCheck'
                    : 'listChecks',
                badges: [
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
                  if (archived)
                    WorkBadge(
                      icon: LucideIcons.archive,
                      label: context.l10n.work_archive,
                      color: context.tokens.muted,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!archived && context.watch<SettingsController>().focusEnabled) ...[
                FilledButton.icon(
                  key: const ValueKey('work-start-focus'),
                  onPressed: () => openWorkFocus(context, taskId: task.id),
                  icon: const Icon(LucideIcons.timer, size: 18),
                  label: Text(context.l10n.work_focus_start_task),
                ),
                const SizedBox(height: 16),
              ],
              if (!archived &&
                  task.parentTaskId == null &&
                  task.status != WorkTaskStatus.done &&
                  task.status != WorkTaskStatus.cancelled &&
                  task.progressMode != WorkTaskProgress.manual) ...[
                WorkQuickAddCard(
                  areaId: work.areaForTask(task),
                  projectId: task.projectId,
                  parentTaskId: task.id,
                  emptyHint: context.l10n.work_quick_add_hint_subtask(
                    task.title,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              WorkSection(
                title: context.l10n.work_progress,
                child: WorkCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: fraction ?? 0,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        workProgressLabel(context, fraction),
                        style: sheetHeadingStyle(context, size: 15),
                      ),
                      if (children.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          context.l10n.work_progress_summary(
                            rollup.completed,
                            rollup.total,
                          ),
                          style: sheetBodyStyle(context, size: 13.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              WorkSection(
                title: context.l10n.work_details,
                child: WorkMetaList(
                  children: [
                    WorkMetaTile(
                      icon: LucideIcons.briefcase,
                      label: context.l10n.work_context,
                      value: areaName,
                    ),
                    WorkPlanningSection(taskId: task.id),
                    WorkTimeSection(taskId: task.id, readOnly: archived),
                    if (task.completionCriteria.trim().isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.target,
                        label: context.l10n.work_completion_criteria,
                        value: task.completionCriteria.trim(),
                      ),
                    if (task.blockedReason.trim().isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.hand,
                        label: context.l10n.work_blocked_reason,
                        value: task.blockedReason.trim(),
                      ),
                    if (task.startDate != null)
                      WorkMetaTile(
                        icon: LucideIcons.calendarDays,
                        label: context.l10n.work_start_date,
                        value: workDateLabel(context, task.startDate),
                      ),
                    if (task.dueDate != null)
                      WorkMetaTile(
                        icon: LucideIcons.calendarClock,
                        label: context.l10n.work_due_date,
                        value: workDueLabel(context, task),
                      ),
                    if (task.estimatedMinutes != null)
                      WorkMetaTile(
                        icon: LucideIcons.timer,
                        label: context.l10n.work_effort_estimate,
                        value: context.l10n.work_estimate_minutes(
                          task.estimatedMinutes!,
                        ),
                      ),
                    if (task.tags.isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.tags,
                        label: context.l10n.work_tags,
                        value: task.tags.join(', '),
                      ),
                    if (task.links.isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.link,
                        label: context.l10n.work_links,
                        value: task.links.join('\n'),
                      ),
                  ],
                ),
              ),
              if (task.photos.isNotEmpty)
                WorkSection(
                  title: context.l10n.note_photos,
                  child: WorkCard(
                    child: PhotoDeck(
                      shots: [
                        for (final path in task.photos) PhotoShot(path: path),
                      ],
                    ),
                  ),
                ),
              WorkSection(
                title: context.l10n.work_subtasks,
                trailing:
                    !archived &&
                        task.parentTaskId == null &&
                        task.status != WorkTaskStatus.done &&
                        task.status != WorkTaskStatus.cancelled &&
                        task.progressMode != WorkTaskProgress.manual
                    ? TextButton.icon(
                        onPressed: () => showWorkTaskForm(
                          context,
                          areaId: work.areaForTask(task),
                          projectId: task.projectId,
                          parentTaskId: task.id,
                        ),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: Text(context.l10n.work_add_subtask),
                      )
                    : null,
                child: children.isEmpty
                    ? AppEmptyState(
                        icon: LucideIcons.listChecks,
                        title: context.l10n.work_subtasks_empty,
                        message: task.progressMode == WorkTaskProgress.manual
                            ? context.l10n.work_subtasks_manual_parent
                            : context.l10n.work_subtasks_empty_sub,
                        compact: true,
                      )
                    : WorkTaskList(
                        tasks: children,
                        allowReorder: !archived,
                        onOpen: (child) => _openTask(child.id),
                        emptyTitle: context.l10n.work_subtasks_empty,
                        emptyMessage: context.l10n.work_subtasks_empty_sub,
                        showChildren: false,
                      ),
              ),
              WorkEntriesSection(kind: WorkEntityKind.task, entityId: task.id),
              RelatedGoalsSection(taskId: task.id, areaId: work.areaForTask(task), projectId: task.projectId),
            ],
          ),
        );
      },
    );
  }
}
