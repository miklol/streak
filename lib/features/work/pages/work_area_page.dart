import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/extensions/inset_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/app_empty_state.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/pages/work_project_page.dart';
import 'package:streak/features/work/pages/work_task_page.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_forms.dart';
import 'package:streak/features/work/widgets/work_ui.dart';
import 'package:streak/features/goals/widgets/related_goals_section.dart';
import 'package:streak/features/work/widgets/work_time_section.dart';

class WorkAreaPage extends StatefulWidget {
  const WorkAreaPage({super.key, required this.areaId});

  final String areaId;

  @override
  State<WorkAreaPage> createState() => _WorkAreaPageState();
}

class _WorkAreaPageState extends State<WorkAreaPage> {
  @override
  void dispose() {
    if (AppNavigator.paneItem.value == 'work-area:${widget.areaId}') {
      AppNavigator.paneItem.value = null;
    }
    super.dispose();
  }

  void _openProject(String projectId) {
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-project:$projectId';
    }
    AppNavigator.push(WorkProjectPage(projectId: projectId), fade: true);
  }

  void _openTask(String taskId) {
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-task:$taskId';
    }
    AppNavigator.push(WorkTaskPage(taskId: taskId), fade: true);
  }

  Future<void> _toggleArchive(WorkArea area) async {
    await runWorkAction(
      context,
      () => context.read<WorkController>().setArchived(
        WorkEntityKind.area,
        area.id,
        !area.isArchived,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WorkController>(
      builder: (context, work, _) {
        final area = work.areaById(widget.areaId);
        if (area == null || area.isDeleted) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => AppNavigator.pop(),
          );
          return const SizedBox.shrink();
        }
        final projects = work.projects(
          areaId: area.id,
          archived: area.isArchived,
        );
        final areaTasks = work.tasks(
          areaId: area.id,
          archived: area.isArchived,
          rootsOnly: true,
          includeDone: true,
        );
        final tasks = areaTasks
            .where((task) => task.projectId == null)
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(area.name, overflow: TextOverflow.ellipsis),
            actions: [
              if (!area.isArchived)
                IconButton(
                  tooltip: context.l10n.edit,
                  onPressed: () => showWorkAreaForm(context, area: area),
                  icon: const Icon(LucideIcons.pencil, size: 18),
                ),
              if (!area.isArchived)
                IconButton(
                  tooltip: context.l10n.work_add_project,
                  onPressed: () =>
                      showWorkProjectForm(context, areaId: area.id),
                  icon: const Icon(LucideIcons.folder, size: 18),
                ),
              IconButton(
                tooltip: area.isArchived
                    ? context.l10n.restore
                    : context.l10n.archive,
                onPressed: () => _toggleArchive(area),
                icon: Icon(
                  area.isArchived ? LucideIcons.rotateCcw : LucideIcons.archive,
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
                title: area.name,
                subtitle: [
                  workAreaTypeLabel(context, area.type),
                  if (area.role.trim().isNotEmpty) area.role.trim(),
                ].join(' • '),
                glyph: area.icon,
                tint: Color(area.color),
                coverPath: area.coverPath,
                description: area.description,
                badges: [
                  WorkBadge(
                    icon: workAreaTypeIcon(area.type),
                    label: workAreaTypeLabel(context, area.type),
                    color: Color(area.color),
                  ),
                  if (area.isArchived)
                    WorkBadge(
                      icon: LucideIcons.archive,
                      label: context.l10n.work_archive,
                      color: context.tokens.muted,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!area.isArchived) ...[
                WorkQuickAddCard(
                  areaId: area.id,
                  projectId: null,
                  parentTaskId: null,
                  emptyHint: context.l10n.work_quick_add_hint_area(area.name),
                ),
                const SizedBox(height: 12),
              ],
              WorkSection(
                title: context.l10n.work_details,
                child: WorkMetaList(
                  children: [
                    WorkMetaTile(
                      icon: LucideIcons.folder,
                      label: context.l10n.work_projects,
                      value: context.l10n.work_count_value(projects.length),
                    ),
                    WorkMetaTile(
                      icon: LucideIcons.listChecks,
                      label: context.l10n.work_tasks,
                      value: context.l10n.work_count_value(areaTasks.length),
                    ),
                    if (area.links.isNotEmpty)
                      WorkMetaTile(
                        icon: LucideIcons.link,
                        label: context.l10n.work_links,
                        value: area.links.join('\n'),
                      ),
                  ],
                ),
              ),
              WorkSection(
                title: context.l10n.work_projects,
                child: projects.isEmpty
                    ? AppEmptyState(
                        icon: LucideIcons.folder,
                        title: context.l10n.work_projects_empty,
                        message: context.l10n.work_projects_empty_sub,
                        compact: true,
                      )
                    : Column(
                        children: [
                          for (
                            var index = 0;
                            index < projects.length;
                            index++
                          ) ...[
                            _ProjectTile(
                              projectId: projects[index].id,
                              onOpen: _openProject,
                            ),
                            if (index < projects.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),
              WorkSection(
                title: context.l10n.work_standalone_tasks,
                trailing: !area.isArchived
                    ? TextButton.icon(
                        onPressed: () =>
                            showWorkTaskForm(context, areaId: area.id),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: Text(context.l10n.work_add_task),
                      )
                    : null,
                child: WorkTaskList(
                  tasks: tasks,
                  allowReorder: !area.isArchived,
                  onOpen: (task) => _openTask(task.id),
                  emptyTitle: context.l10n.work_empty_tasks,
                  emptyMessage: context.l10n.work_empty_tasks_sub,
                ),
              ),
              WorkEntriesSection(kind: WorkEntityKind.area, entityId: area.id),
              RelatedGoalsSection(areaId: area.id),
              WorkTimeSection(areaId: area.id, readOnly: area.isArchived),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.projectId, required this.onOpen});

  final String projectId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final project = work.projectById(projectId)!;
    final progress = work.data.projectProgress(project.id);
    return WorkCard(
      onTap: () => onOpen(project.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: WorkTitleText(
                  project.name,
                  style: sheetHeadingStyle(context, size: 15.5),
                ),
              ),
              WorkBadge(
                icon: workProjectStatusIcon(project.status),
                label: workProjectStatusLabel(context, project.status),
                color: workProjectStatusColor(context, project.status),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress.fraction ?? 0,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 8),
          Text(
            workProgressLabel(context, progress.fraction),
            style: sheetBodyStyle(context, size: 13),
          ),
        ],
      ),
    );
  }
}
