import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/extensions/inset_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/icons/habit_icons.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/app_empty_state.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/pages/goals_page.dart';
import 'package:streak/features/work/pages/work_insights_page.dart';
import 'package:streak/features/focus/widgets/focus_pill.dart';
import 'package:streak/features/habits/pages/day_timeline_page.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/todos/widgets/todo_labels.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/pages/work_area_page.dart';
import 'package:streak/features/work/pages/work_project_page.dart';
import 'package:streak/features/work/pages/work_task_page.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_forms.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

class WorkPage extends StatefulWidget implements FullWidthPage {
  const WorkPage({super.key});

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage> {
  final _search = TextEditingController();
  WorkOverviewFilter _filter = WorkOverviewFilter.all;
  String? _areaId;
  WorkTaskStatus? _status;
  TodoPriority? _priority;
  WorkTaskSort _sort = WorkTaskSort.manual;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openArea(WorkArea area) {
    AppNavigator.clearPane();
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-area:${area.id}';
    }
    AppNavigator.push(WorkAreaPage(areaId: area.id), fade: true);
  }

  void _openProject(WorkProject project) {
    AppNavigator.clearPane();
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-project:${project.id}';
    }
    AppNavigator.push(WorkProjectPage(projectId: project.id), fade: true);
  }

  void _openTask(WorkTask task) {
    AppNavigator.clearPane();
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'work-task:${task.id}';
    }
    AppNavigator.push(WorkTaskPage(taskId: task.id), fade: true);
  }

  bool get _flatResults =>
      _search.text.trim().isNotEmpty ||
      _status != null ||
      _priority != null ||
      _filter == WorkOverviewFilter.today ||
      _filter == WorkOverviewFilter.overdue;

  void _clearFilters() => setState(() {
    _search.clear();
    _status = null;
    _priority = null;
    _areaId = null;
    _filter = WorkOverviewFilter.all;
    _sort = WorkTaskSort.manual;
  });

  List<WorkTask> _tasks(WorkController work, String? areaId) {
    final query = _search.text.trim();
    final archived = _filter == WorkOverviewFilter.archive;
    final includeDone = archived || _status != null;
    List<WorkTask> tasks = switch (_filter) {
      WorkOverviewFilter.inbox => work.tasks(
        areaId: areaId,
        archived: archived,
        inboxOnly: true,
        includeDone: includeDone,
        query: query,
        status: _status,
        priority: _priority,
        sort: _sort,
        rootsOnly: !_flatResults && !archived,
      ),
      _ => work.tasks(
        areaId: areaId,
        archived: archived,
        includeDone: includeDone,
        query: query,
        status: _status,
        priority: _priority,
        sort: _sort,
        rootsOnly: !_flatResults && !archived,
      ),
    };
    final now = AppClock.wallNow();
    if (_filter == WorkOverviewFilter.today) {
      tasks = tasks.where((task) => work.isForToday(task, now)).toList();
    } else if (_filter == WorkOverviewFilter.overdue) {
      tasks = tasks.where((task) => work.isOverdue(task, now)).toList();
    }
    if (archived && !_flatResults) {
      tasks = tasks
          .where(
            (task) =>
                task.parentTaskId == null ||
                !work.isTaskArchived(work.taskById(task.parentTaskId!)!),
          )
          .toList();
    }
    return tasks;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final work = context.watch<WorkController>();
    final archived = _filter == WorkOverviewFilter.archive;
    final query = _search.text.trim();
    final areaOptions =
        work.data.areas.where((area) => !area.isDeleted).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final areaId = areaOptions.any((area) => area.id == _areaId)
        ? _areaId
        : null;
    final areas = work.areas(archived: archived, query: query);
    final projects = work.projects(
      areaId: areaId,
      archived: archived,
      query: query,
    );
    final tasks = _tasks(work, areaId);
    final showingAll = _filter == WorkOverviewFilter.all;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: settings.isMinimalStyle || settings.isExpressStyle
            ? 52
            : null,
        title: settings.isMinimalStyle || settings.isExpressStyle
            ? null
            : Text(context.l10n.work),
        actions: [
          const FocusPill(compact: true, dense: true),
          IconButton(
            tooltip: context.l10n.day_timeline,
            onPressed: () => AppNavigator.push(const DayTimelinePage(useCalendarToday: true)),
            icon: const Icon(LucideIcons.calendarClock, size: 20),
          ),
          IconButton(
            tooltip: context.l10n.refresh_now,
            onPressed: work.reload,
            icon: const Icon(LucideIcons.refreshCcw, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: context.pagePadding(
          settings.isMinimalStyle ? 22 : 16,
          settings.isExpressStyle ? 4 : 8,
          settings.isMinimalStyle ? 22 : 16,
          settings.isExpressStyle ? 132 : (settings.isMinimalStyle ? 96 : 124),
        ),
        children: [
          if (settings.isMinimalStyle || settings.isExpressStyle)
            WorkPageHeader(
              title: context.l10n.work,
              subtitle: archived
                  ? context.l10n.work_archive_subtitle
                  : context.l10n.work_open_tasks(tasks.length),
            )
          else
            Text(
              archived
                  ? context.l10n.work_archive_subtitle
                  : context.l10n.work_open_tasks(tasks.length),
              style: sheetBodyStyle(context),
            ),
          const SizedBox(height: 16),
          if (!archived) ...[
            WorkQuickAddCard(
              areaId: areaId,
              projectId: null,
              parentTaskId: null,
              emptyHint: areaId == null
                  ? context.l10n.work_quick_add_hint
                  : context.l10n.work_quick_add_hint_area(
                      work.areaById(areaId)?.name ?? context.l10n.work,
                    ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              TextButton.icon(
                onPressed: () => AppNavigator.push(GoalsPage(
                    initialScope: GoalScope.work, areaId: areaId)),
                icon: const Icon(LucideIcons.target, size: 18),
                label: Text(context.l10n.goals_nav_title),
              ),
              TextButton.icon(
                onPressed: () => AppNavigator.push(WorkInsightsPage(areaId: areaId)),
                icon: const Icon(LucideIcons.chartColumn, size: 18),
                label: Text(context.l10n.goals_nav_insights),
              ),
              if (!archived)
                OutlinedButton.icon(
                  onPressed: () => showWorkAreaForm(context),
                  icon: const Icon(LucideIcons.briefcase, size: 18),
                  label: Text(context.l10n.work_add_area),
                ),
              if (!archived)
                OutlinedButton.icon(
                  onPressed: () => showWorkProjectForm(context, areaId: areaId),
                  icon: const Icon(LucideIcons.folder, size: 18),
                  label: Text(context.l10n.work_add_project),
                ),
            ],
          ),
          const SizedBox(height: 18),
          WorkSection(
            title: context.l10n.work_filters,
            child: WorkCard(
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final value in WorkOverviewFilter.values)
                        ChoiceChip(
                          label: Text(workOverviewLabel(context, value)),
                          avatar: Icon(workOverviewIcon(value), size: 16),
                          selected: _filter == value,
                          onSelected: (_) => setState(() {
                            _filter = value;
                            if (value == WorkOverviewFilter.inbox) {
                              _areaId = null;
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('work-search-field'),
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: context.l10n.work_search,
                      hintText: context.l10n.work_search_hint,
                      prefixIcon: const Icon(LucideIcons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.l10n.cancel,
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(LucideIcons.x, size: 18),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    key: const ValueKey('work-advanced-filters'),
                    tilePadding: EdgeInsets.zero,
                    title: Text(context.l10n.work_filters),
                    leading: const Icon(
                      LucideIcons.slidersHorizontal,
                      size: 18,
                    ),
                    children: [
                      DropdownButtonFormField<String?>(
                        key: ValueKey('work-area-filter-$areaId'),
                        initialValue: areaId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_area_selector,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.all),
                          ),
                          for (final area in areaOptions)
                            DropdownMenuItem<String?>(
                              value: area.id,
                              child: Text(area.name),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _areaId = value;
                          if (value != null &&
                              work.areaById(value)?.isArchived == true) {
                            _filter = WorkOverviewFilter.archive;
                          } else if (value != null &&
                              _filter == WorkOverviewFilter.inbox) {
                            _filter = WorkOverviewFilter.all;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<WorkTaskStatus?>(
                        key: ValueKey('work-status-filter-$_status'),
                        initialValue: _status,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.status,
                        ),
                        items: [
                          DropdownMenuItem<WorkTaskStatus?>(
                            value: null,
                            child: Text(context.l10n.work_any_status),
                          ),
                          for (final status in WorkTaskStatus.values)
                            DropdownMenuItem<WorkTaskStatus?>(
                              value: status,
                              child: Text(workTaskStatusLabel(context, status)),
                            ),
                        ],
                        onChanged: (value) => setState(() => _status = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TodoPriority?>(
                        key: ValueKey('work-priority-filter-$_priority'),
                        initialValue: _priority,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.todo_priority,
                        ),
                        items: [
                          DropdownMenuItem<TodoPriority?>(
                            value: null,
                            child: Text(context.l10n.work_any_priority),
                          ),
                          for (final priority in TodoPriority.values)
                            DropdownMenuItem<TodoPriority?>(
                              value: priority,
                              child: Text(
                                todoPriorityLabels(context)[priority.index],
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<WorkTaskSort>(
                        key: ValueKey('work-sort-filter-$_sort'),
                        initialValue: _sort,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.l10n.work_sort,
                        ),
                        items: [
                          for (final sort in WorkTaskSort.values)
                            DropdownMenuItem(
                              value: sort,
                              child: Text(workTaskSortLabel(context, sort)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _sort = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _clearFilters,
                        child: Text(context.l10n.work_clear_filters),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          WorkSection(
            title: context.l10n.work_tasks,
            child: tasks.isEmpty
                ? AppEmptyState(
                    icon: LucideIcons.listChecks,
                    title: _flatResults
                        ? context.l10n.work_search_empty
                        : _emptyTitle(context),
                    message: _flatResults
                        ? context.l10n.work_filter_reset_hint
                        : _emptyBody(context),
                    compact: true,
                    action: _flatResults || areaId != null
                        ? TextButton(
                            onPressed: _clearFilters,
                            child: Text(context.l10n.work_clear_filters),
                          )
                        : null,
                  )
                : WorkTaskList(
                    tasks: tasks,
                    allowReorder:
                        _filter == WorkOverviewFilter.inbox && !_flatResults,
                    sort: _sort,
                    showChildren: !_flatResults,
                    onOpen: _openTask,
                    emptyTitle: '',
                  ),
          ),
          if (showingAll || archived) ...[
            WorkSection(
              title: context.l10n.work_areas,
              trailing: TextButton(
                onPressed: archived ? null : () => showWorkAreaForm(context),
                child: Text(context.l10n.work_add_area),
              ),
              child: areas.isEmpty
                  ? AppEmptyState(
                      icon: LucideIcons.briefcase,
                      title: archived
                          ? context.l10n.work_archive_empty_areas
                          : context.l10n.work_areas_empty,
                      message: archived
                          ? context.l10n.work_archive_empty_areas_sub
                          : context.l10n.work_areas_empty_sub,
                      compact: true,
                    )
                  : Column(
                      children: [
                        for (var index = 0; index < areas.length; index++) ...[
                          _AreaCard(area: areas[index], onOpen: _openArea),
                          if (index < areas.length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    ),
            ),
            WorkSection(
              title: context.l10n.work_projects,
              child: projects.isEmpty
                  ? AppEmptyState(
                      icon: LucideIcons.folder,
                      title: archived
                          ? context.l10n.work_archive_empty_projects
                          : context.l10n.work_projects_empty,
                      message: archived
                          ? context.l10n.work_archive_empty_projects_sub
                          : context.l10n.work_projects_empty_sub,
                      compact: true,
                    )
                  : Column(
                      children: [
                        for (
                          var index = 0;
                          index < projects.length;
                          index++
                        ) ...[
                          _ProjectCard(
                            project: projects[index],
                            onOpen: _openProject,
                          ),
                          if (index < projects.length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  String _emptyTitle(BuildContext context) => switch (_filter) {
    WorkOverviewFilter.all => context.l10n.work_empty_tasks,
    WorkOverviewFilter.today => context.l10n.work_empty_today,
    WorkOverviewFilter.inbox => context.l10n.work_empty_inbox,
    WorkOverviewFilter.overdue => context.l10n.work_empty_overdue,
    WorkOverviewFilter.archive => context.l10n.work_archive_empty_tasks,
  };

  String _emptyBody(BuildContext context) {
    if (_search.text.trim().isNotEmpty) {
      return context.l10n.work_search_empty;
    }
    return switch (_filter) {
      WorkOverviewFilter.all => context.l10n.work_empty_tasks_sub,
      WorkOverviewFilter.today => context.l10n.work_empty_today_sub,
      WorkOverviewFilter.inbox => context.l10n.work_empty_inbox_sub,
      WorkOverviewFilter.overdue => context.l10n.work_empty_overdue_sub,
      WorkOverviewFilter.archive => context.l10n.work_archive_empty_tasks_sub,
    };
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area, required this.onOpen});

  final WorkArea area;
  final ValueChanged<WorkArea> onOpen;

  @override
  Widget build(BuildContext context) {
    return WorkCard(
      key: ValueKey('work-area-${area.id}'),
      onTap: () => onOpen(area),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Color(area.color).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              HabitIcons.resolve(area.icon),
              color: Color(area.color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WorkTitleText(
                  area.name,
                  style: sheetHeadingStyle(context, size: 15.5),
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    workAreaTypeLabel(context, area.type),
                    if (area.role.trim().isNotEmpty) area.role.trim(),
                  ].join(' • '),
                  style: sheetBodyStyle(context, size: 13.5),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, size: 18),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onOpen});

  final WorkProject project;
  final ValueChanged<WorkProject> onOpen;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    return WorkCard(
      key: ValueKey('work-project-${project.id}'),
      onTap: () => onOpen(project),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: WorkTitleText(
                  project.name,
                  style: sheetHeadingStyle(context, size: 15.5),
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 12),
              WorkBadge(
                icon: workProjectStatusIcon(project.status),
                label: workProjectStatusLabel(context, project.status),
                color: workProjectStatusColor(context, project.status),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            workProjectContextLabel(context, work, project),
            style: sheetBodyStyle(context, size: 13.5),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: work.data.projectProgress(project.id).fraction ?? 0,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: context.colors.surfaceContainerHighest,
          ),
          const SizedBox(height: 8),
          Text(
            workProgressLabel(
              context,
              work.data.projectProgress(project.id).fraction,
            ),
            style: sheetBodyStyle(context, size: 13),
          ),
          if (project.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              project.description.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: sheetBodyStyle(context, size: 14),
            ),
          ],
        ],
      ),
    );
  }
}
