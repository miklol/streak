import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/extensions/inset_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/app_empty_state.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/pages/goal_details_page.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/goals/widgets/goal_form.dart';
import 'package:streak/features/goals/widgets/goal_ui.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

class GoalsPage extends StatefulWidget implements FullWidthPage {
  const GoalsPage({
    super.key,
    this.initialScope = GoalScope.personal,
    this.areaId,
    this.projectId,
  });

  final GoalScope initialScope;
  final String? areaId;
  final String? projectId;

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final _search = TextEditingController();
  late GoalScope _scope = widget.initialScope;
  GoalStatus? _status;
  bool _archived = false;
  late String? _areaId = widget.areaId;
  late String? _projectId = widget.projectId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openGoal(Goal goal) {
    AppNavigator.clearPane();
    if (isWideLayout(context)) {
      AppNavigator.paneItem.value = 'goal:${goal.id}';
    }
    AppNavigator.push(GoalDetailsPage(goalId: goal.id), fade: true);
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _status = null;
      _archived = false;
      if (widget.areaId == null) _areaId = null;
      if (widget.projectId == null) _projectId = null;
    });
  }

  bool get _hasFilters =>
      _search.text.trim().isNotEmpty ||
      _status != null ||
      _archived ||
      (_scope == GoalScope.work &&
          ((_areaId != null && _areaId != widget.areaId) ||
              (_projectId != null && _projectId != widget.projectId)));

  void _createGoal() => showGoalForm(
    context,
    scope: _scope,
    areaId: _scope == GoalScope.work ? _areaId : null,
    projectId: _scope == GoalScope.work ? _projectId : null,
  );

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final goalsController = context.watch<GoalsController>();
    final work = context.watch<WorkController>();
    if (_areaId != null &&
        (work.areaById(_areaId!) == null ||
            work.areaById(_areaId!)!.isDeleted)) {
      _areaId = null;
    }
    if (_projectId != null &&
        (work.projectById(_projectId!) == null ||
            work.projectById(_projectId!)!.isDeleted)) {
      _projectId = null;
    }
    final goals = goalsController.goals(
      scope: _scope,
      archived: _archived,
      status: _status,
      query: _search.text,
      areaId: _scope == GoalScope.work ? _areaId : null,
      projectId: _scope == GoalScope.work ? _projectId : null,
    )..sort(_goalSort);
    final allInScope = goalsController.goals(
      scope: _scope,
      archived: _archived,
      areaId: _scope == GoalScope.work ? _areaId : null,
      projectId: _scope == GoalScope.work ? _projectId : null,
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: settings.isMinimalStyle || settings.isExpressStyle
            ? 52
            : null,
        title: settings.isMinimalStyle || settings.isExpressStyle
            ? null
            : Text(context.l10n.goals_nav_title),
        actions: [
          IconButton(
            tooltip: context.l10n.refresh_now,
            onPressed: goalsController.reload,
            icon: const Icon(LucideIcons.refreshCcw, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _archived || goals.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _createGoal,
              icon: const Icon(LucideIcons.plus),
              label: Text(context.l10n.goal_add),
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
              title: context.l10n.goals_nav_title,
              subtitle: _archived
                  ? context.l10n.goal_archived
                  : (_scope == GoalScope.personal
                        ? context.l10n.goal_scope_personal
                        : context.l10n.goal_scope_work),
            )
          else
            Text(
              _scope == GoalScope.personal
                  ? context.l10n.goal_scope_personal
                  : context.l10n.goal_scope_work,
              style: sheetBodyStyle(context),
            ),
          const SizedBox(height: 16),
          WorkSection(
            title: context.l10n.goal_filters,
            child: WorkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GoalScopeSelector(
                    scope: _scope,
                    onChanged: (scope) => setState(() => _scope = scope),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: context.l10n.goals_nav_search,
                      prefixIcon: const Icon(LucideIcons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: Text(context.l10n.goal_active_only),
                        avatar: const Icon(LucideIcons.target, size: 16),
                        selected: !_archived,
                        onSelected: (selected) =>
                            setState(() => _archived = !selected),
                      ),
                      FilterChip(
                        label: Text(context.l10n.goal_archived),
                        avatar: const Icon(LucideIcons.archive, size: 16),
                        selected: _archived,
                        onSelected: (selected) =>
                            setState(() => _archived = selected),
                      ),
                      DropdownButton<GoalStatus?>(
                        value: _status,
                        isExpanded: true,
                        hint: Text(context.l10n.goal_any_status),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(context.l10n.goal_any_status),
                          ),
                          for (final value in GoalStatus.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(goalStatusLabel(context, value)),
                            ),
                        ],
                        onChanged: (value) => setState(() => _status = value),
                      ),
                      if (_hasFilters)
                        TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(LucideIcons.x, size: 18),
                          label: Text(context.l10n.goal_clear_filters),
                        ),
                    ],
                  ),
                  if (_scope == GoalScope.work) ...[
                    const SizedBox(height: 12),
                    _HubWorkFilters(
                      areaId: _areaId,
                      projectId: _projectId,
                      fixedAreaId: widget.areaId,
                      fixedProjectId: widget.projectId,
                      onAreaChanged: (value) => setState(() {
                        _areaId = value;
                        final project = _projectId == null
                            ? null
                            : work.projectById(_projectId!);
                        if (project != null &&
                            _areaId != null &&
                            project.areaId != _areaId) {
                          _projectId = null;
                        }
                      }),
                      onProjectChanged: (value) => setState(() {
                        _projectId = value;
                        final project = value == null
                            ? null
                            : work.projectById(value);
                        if (project != null) _areaId = project.areaId;
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (goals.isEmpty)
            AppEmptyState(
              icon: LucideIcons.target,
              title: allInScope.isEmpty && !_hasFilters
                  ? context.l10n.goal_empty_title
                  : context.l10n.goal_no_matches_title,
              message: allInScope.isEmpty && !_hasFilters
                  ? context.l10n.goal_empty_message
                  : context.l10n.goal_no_matches_message,
              action: Column(
                children: [
                  if (!_archived)
                    FilledButton.icon(
                      onPressed: _createGoal,
                      icon: const Icon(LucideIcons.plus, size: 18),
                      label: Text(context.l10n.goal_add),
                    ),
                  if (_hasFilters)
                    TextButton(
                      onPressed: _clearFilters,
                      child: Text(context.l10n.goal_clear_filters),
                    ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < goals.length; index++) ...[
                  GoalCard(
                    goal: goals[index],
                    onOpen: () => _openGoal(goals[index]),
                  ),
                  if (index < goals.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

int _goalSort(Goal a, Goal b) {
  final pinned = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
  if (pinned != 0) return pinned;
  final order = a.order.compareTo(b.order);
  if (order != 0) return order;
  final updated = b.meta.updatedAt.compareTo(a.meta.updatedAt);
  if (updated != 0) return updated;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

class _HubWorkFilters extends StatelessWidget {
  const _HubWorkFilters({
    required this.areaId,
    required this.projectId,
    required this.fixedAreaId,
    required this.fixedProjectId,
    required this.onAreaChanged,
    required this.onProjectChanged,
  });

  final String? areaId;
  final String? projectId;
  final String? fixedAreaId;
  final String? fixedProjectId;
  final ValueChanged<String?> onAreaChanged;
  final ValueChanged<String?> onProjectChanged;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final areas = work.data.areas.where((area) => !area.isDeleted).toList();
    final projects = work.data.projects
        .where(
          (project) =>
              !project.isDeleted &&
              (areaId == null || project.areaId == areaId),
        )
        .toList();
    final fields = [
      DropdownButtonFormField<String?>(
        key: ValueKey('goal-area-$areaId'),
        initialValue: areaId,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.l10n.work_area),
        items: [
          DropdownMenuItem(
            value: null,
            child: Text(context.l10n.all),
          ),
          for (final area in areas)
            DropdownMenuItem(value: area.id, child: Text(area.name)),
        ],
        onChanged: fixedAreaId == null ? onAreaChanged : null,
      ),
      DropdownButtonFormField<String?>(
        key: ValueKey('goal-project-$projectId-$areaId'),
        initialValue: projects.any((project) => project.id == projectId)
            ? projectId
            : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.l10n.work_project),
        items: [
          DropdownMenuItem(
            value: null,
            child: Text(context.l10n.all),
          ),
          for (final project in projects)
            DropdownMenuItem(value: project.id, child: Text(project.name)),
        ],
        onChanged: fixedProjectId == null ? onProjectChanged : null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              fields.first,
              const SizedBox(height: 12),
              fields.last,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: fields.first),
            const SizedBox(width: 10),
            Expanded(child: fields.last),
          ],
        );
      },
    );
  }
}
