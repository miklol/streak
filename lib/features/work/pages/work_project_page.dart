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
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/todos/widgets/todo_labels.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/pages/work_task_page.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_forms.dart';
import 'package:streak/features/work/widgets/work_ui.dart';
import 'package:streak/features/goals/widgets/related_goals_section.dart';
import 'package:streak/features/work/widgets/work_time_section.dart';

class WorkProjectPage extends StatefulWidget {
  const WorkProjectPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<WorkProjectPage> createState() => _WorkProjectPageState();
}

class _WorkProjectPageState extends State<WorkProjectPage> {
  @override
  void dispose() {
    if (AppNavigator.paneItem.value == 'work-project:${widget.projectId}') {
      AppNavigator.paneItem.value = null;
    }
    super.dispose();
  }

  void _openTask(String taskId) {
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-task:$taskId';
    }
    AppNavigator.push(WorkTaskPage(taskId: taskId), fade: true);
  }

  Future<void> _toggleArchive(WorkProject project) async {
    final archived = context.read<WorkController>().isProjectArchived(project);
    await runWorkAction(
      context,
      () => context.read<WorkController>().setArchived(
        WorkEntityKind.project,
        project.id,
        !archived,
      ),
    );
  }

  Future<void> _toggleDone(WorkProject project) async {
    final work = context.read<WorkController>();
    if (project.status == WorkProjectStatus.done ||
        project.status == WorkProjectStatus.cancelled) {
      await runWorkAction(
        context,
        () => work.saveProject(
          project.copyWith(status: WorkProjectStatus.active),
          expectedRevision: project.meta.revision,
        ),
      );
      return;
    }
    final open = work.data.tasks
        .where(
          (task) =>
              task.projectId == project.id &&
              !task.isDeleted &&
              task.status != WorkTaskStatus.done &&
              task.status != WorkTaskStatus.cancelled &&
              (task.parentTaskId == null ||
                  work.taskById(task.parentTaskId!)?.status !=
                      WorkTaskStatus.cancelled),
        )
        .length;
    if (open > 0) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: context.l10n.work_complete_project,
        message: context.l10n.work_complete_project_confirm(open),
        confirmLabel: context.l10n.work_complete_project,
        icon: LucideIcons.circleCheck,
        danger: false,
      );
      if (confirmed != true || !mounted) return;
    }
    await runWorkAction(
      context,
      () => work.saveProject(
        project.copyWith(status: WorkProjectStatus.done),
        expectedRevision: project.meta.revision,
        completeTasks: open > 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WorkController>(
      builder: (context, work, _) {
        final project = work.projectById(widget.projectId);
        if (project == null || project.isDeleted) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => AppNavigator.pop(),
          );
          return const SizedBox.shrink();
        }
        final tasks = work.tasks(
          projectId: project.id,
          archived: work.isProjectArchived(project),
          rootsOnly: true,
          includeDone: true,
        );
        final progress = work.data.projectProgress(project.id);
        final areaName = workProjectContextLabel(context, work, project);
        return Scaffold(
          appBar: AppBar(
            title: Text(project.name, overflow: TextOverflow.ellipsis),
            actions: [
              if (!work.isProjectArchived(project))
                IconButton(
                  tooltip: context.l10n.edit,
                  onPressed: () =>
                      showWorkProjectForm(context, project: project),
                  icon: const Icon(LucideIcons.pencil, size: 18),
                ),
              if (!work.isProjectArchived(project))
                IconButton(
                  tooltip:
                      project.status == WorkProjectStatus.done ||
                          project.status == WorkProjectStatus.cancelled
                      ? context.l10n.work_reopen
                      : context.l10n.work_complete_project,
                  onPressed: () => _toggleDone(project),
                  icon: Icon(
                    project.status == WorkProjectStatus.done ||
                            project.status == WorkProjectStatus.cancelled
                        ? LucideIcons.rotateCcw
                        : LucideIcons.circleCheck,
                    size: 18,
                  ),
                ),
              IconButton(
                tooltip: work.isProjectArchived(project)
                    ? context.l10n.restore
                    : context.l10n.archive,
                onPressed: () => _toggleArchive(project),
                icon: Icon(
                  work.isProjectArchived(project)
                      ? LucideIcons.rotateCcw
                      : LucideIcons.archive,
                  size: 18,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: context.pagePadding(16, 8, 16, 32),
            children: [
              WorkEntityHero(
                title: project.name,
                subtitle: areaName,
                description: project.description,
                coverPath: project.coverPath,
                glyph: 'folder',
                badges: [
                  WorkBadge(
                    icon: workProjectStatusIcon(project.status),
                    label: workProjectStatusLabel(context, project.status),
                    color: workProjectStatusColor(context, project.status),
                  ),
                  if (project.priority != TodoPriority.none)
                    WorkBadge(
                      icon: LucideIcons.flag,
                      label: todoPriorityLabels(
                        context,
                      )[project.priority.index],
                      color: todoPriorityColor(context, project.priority),
                    ),
                  if (work.isProjectArchived(project))
                    WorkBadge(
                      icon: LucideIcons.archive,
                      label: context.l10n.work_archive,
                      color: context.tokens.muted,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!work.isProjectArchived(project) &&
                  project.status != WorkProjectStatus.done &&
                  project.status != WorkProjectStatus.cancelled) ...[
                WorkQuickAddCard(
                  areaId: project.areaId,
                  projectId: project.id,
                  parentTaskId: null,
                  emptyHint: context.l10n.work_quick_add_hint_project(
                    project.name,
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
                        value: progress.fraction ?? 0,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        workProgressLabel(context, progress.fraction),
                        style: sheetHeadingStyle(context, size: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.work_progress_summary(
                          progress.completed,
                          progress.total,
                        ),
                        style: sheetBodyStyle(context, size: 13.5),
                      ),
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
                      label: context.l10n.work_area,
                      value: areaName,
                    ),
                    if (project.outcome.trim().isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.target,
                        label: context.l10n.work_outcome,
                        value: project.outcome.trim(),
                      ),
                    if (project.startDate != null)
                      WorkMetaTile(
                        icon: LucideIcons.calendarDays,
                        label: context.l10n.work_start_date,
                        value: workDateLabel(context, project.startDate),
                      ),
                    if (project.dueDate != null)
                      WorkMetaTile(
                        icon: LucideIcons.calendarClock,
                        label: context.l10n.work_due_date,
                        value: workDateLabel(context, project.dueDate),
                      ),
                    if (project.tags.isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.tags,
                        label: context.l10n.work_tags,
                        value: project.tags.join(', '),
                      ),
                    if (project.links.isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.link,
                        label: context.l10n.work_links,
                        value: project.links.join('\n'),
                      ),
                  ],
                ),
              ),
              WorkSection(
                title: context.l10n.work_tasks,
                trailing:
                    !work.isProjectArchived(project) &&
                        project.status != WorkProjectStatus.done &&
                        project.status != WorkProjectStatus.cancelled
                    ? TextButton.icon(
                        onPressed: () => showWorkTaskForm(
                          context,
                          areaId: project.areaId,
                          projectId: project.id,
                        ),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: Text(context.l10n.work_add_task),
                      )
                    : null,
                child: tasks.isEmpty
                    ? AppEmptyState(
                        icon: LucideIcons.listChecks,
                        title: context.l10n.work_empty_tasks,
                        message: context.l10n.work_empty_tasks_sub,
                        compact: true,
                      )
                    : WorkTaskList(
                        tasks: tasks,
                        allowReorder: !work.isProjectArchived(project),
                        onOpen: (task) => _openTask(task.id),
                        emptyTitle: context.l10n.work_empty_tasks,
                        emptyMessage: context.l10n.work_empty_tasks_sub,
                      ),
              ),
              WorkEntriesSection(
                kind: WorkEntityKind.project,
                entityId: project.id,
              ),
              RelatedGoalsSection(areaId: project.areaId, projectId: project.id),
              WorkTimeSection(projectId: project.id, readOnly: work.isProjectArchived(project)),
            ],
          ),
        );
      },
    );
  }
}
