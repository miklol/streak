import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/pages/goal_details_page.dart';
import 'package:streak/features/goals/pages/goals_page.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/goals/widgets/goal_form.dart';
import 'package:streak/features/goals/widgets/goal_habit_links.dart';
import 'package:streak/features/goals/widgets/goal_ui.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

class RelatedGoalsSection extends StatelessWidget {
  const RelatedGoalsSection({
    super.key,
    this.habitId,
    this.areaId,
    this.projectId,
    this.taskId,
  });
  final String? habitId;
  final String? areaId;
  final String? projectId;
  final String? taskId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GoalsController>();
    final List<Goal> goals;
    if (habitId != null) {
      goals = controller.forHabit(habitId!);
    } else {
      goals = controller.forWork(
        areaId: areaId,
        projectId: projectId,
        taskId: taskId,
      );
    }
    return WorkSection(
      title: context.l10n.goals_nav_related,
      child: WorkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (habitId != null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final goalId = await showGoalPicker(context);
                      if (goalId != null && context.mounted) {
                        final existing = controller
                            .linksForGoal(goalId)
                            .where((link) => link.habitId == habitId)
                            .firstOrNull;
                        await showGoalHabitLinkEditor(
                          context,
                          goalId: goalId,
                          habitId: habitId,
                          existing: existing,
                        );
                      }
                    },
                    icon: const Icon(LucideIcons.link, size: 18),
                    label: Text(context.l10n.glink_link_goal),
                  ),
                if (habitId == null && (taskId != null || projectId != null))
                  OutlinedButton.icon(
                    onPressed: () async {
                      final id = await showGoalPicker(
                        context,
                        scope: GoalScope.work,
                        excluded: {for (final goal in goals) goal.id},
                      );
                      if (id == null || !context.mounted) return;
                      final goal = controller.byId(id);
                      if (goal == null) {
                        await runGoalAction(context, () async {
                          throw const GoalOperationException(
                            GoalFailure.missing,
                          );
                        });
                        return;
                      }
                      await showGoalForm(
                        context,
                        goal: goal.copyWith(
                          taskIds: taskId == null
                              ? goal.taskIds
                              : {...goal.taskIds, taskId!}.toList(),
                          projectIds: taskId != null || projectId == null
                              ? goal.projectIds
                              : {...goal.projectIds, projectId!}.toList(),
                        ),
                      );
                    },
                    icon: const Icon(LucideIcons.link, size: 18),
                    label: Text(context.l10n.glink_link_goal),
                  ),
                TextButton.icon(
                  onPressed: () => showGoalForm(
                    context,
                    habitId: habitId,
                    scope: habitId != null
                        ? GoalScope.personal
                        : GoalScope.work,
                    areaId: areaId,
                    projectId: projectId,
                    taskId: taskId,
                  ),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text(context.l10n.goals_nav_create),
                ),
                if (habitId == null)
                  TextButton(
                    onPressed: () => AppNavigator.push(
                      GoalsPage(
                        initialScope: GoalScope.work,
                        areaId: areaId,
                        projectId: projectId,
                      ),
                    ),
                    child: Text(context.l10n.goals_nav_browse),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (goals.isEmpty)
              Text(
                context.l10n.goals_nav_related_empty,
                style: sheetBodyStyle(context),
              ),
            for (final goal in goals) ...[
              const SizedBox(height: 8),
              GoalCard(
                goal: goal,
                onOpen: () =>
                    AppNavigator.push(GoalDetailsPage(goalId: goal.id)),
              ),
              if (habitId != null)
                for (final link
                    in controller
                        .linksForGoal(goal.id)
                        .where((link) => link.habitId == habitId))
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        goalHabitRoleLabel(context, link.role),
                        style: sheetBodyStyle(context),
                      ),
                      if (!goal.isArchived)
                        TextButton(
                          onPressed: () => showGoalHabitLinkEditor(
                            context,
                            goalId: goal.id,
                            habitId: habitId,
                            existing: link,
                          ),
                          child: Text(context.l10n.glink_edit),
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

class PersonalGoalsSummary extends StatelessWidget {
  const PersonalGoalsSummary({super.key});
  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>().pinnedPersonal;
    if (goals.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: WorkSection(
        title: context.l10n.goals_nav_personal,
        child: Column(
          children: [
            for (final goal in goals.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GoalCard(
                  goal: goal,
                  onOpen: () =>
                      AppNavigator.push(GoalDetailsPage(goalId: goal.id)),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => AppNavigator.push(const GoalsPage()),
                child: Text(context.l10n.goals_nav_all),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> showGoalPicker(
  BuildContext context, {
  GoalScope? scope,
  Set<String> excluded = const {},
}) => showDialog<String>(
  context: context,
  builder: (_) => _GoalPicker(scope: scope, excluded: excluded),
);

class _GoalPicker extends StatefulWidget {
  const _GoalPicker({this.scope, this.excluded = const {}});
  final GoalScope? scope;
  final Set<String> excluded;
  @override
  State<_GoalPicker> createState() => _GoalPickerState();
}

class _GoalPickerState extends State<_GoalPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final goals = context
        .watch<GoalsController>()
        .goals(scope: widget.scope, query: _query)
        .where((goal) => !widget.excluded.contains(goal.id))
        .toList();
    return AlertDialog(
      title: Text(context.l10n.glink_link_goal),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.goals_nav_search,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (goals.isEmpty) Text(context.l10n.goals_nav_none),
                  for (final goal in goals)
                    ListTile(
                      title: Text(goal.title),
                      subtitle: Text(
                        goal.scope == GoalScope.personal
                            ? context.l10n.goals_nav_personal
                            : context.l10n.work,
                      ),
                      onTap: () => Navigator.of(context).pop(goal.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }
}

class HabitGoalSelection extends StatelessWidget {
  const HabitGoalSelection({
    super.key,
    required this.selected,
    required this.onChanged,
    this.habitId,
  });
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String? habitId;

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    final contributing = habitId == null
        ? <String>{}
        : {
            for (final link in goals.linksForHabit(habitId!))
              if (link.role == GoalHabitRole.contributor) link.goalId,
          };
    final titles = selected
        .map(
          (id) => goals.byId(id)?.title ?? context.l10n.glink_goal_unavailable,
        )
        .toList();
    return WorkSection(
      title: context.l10n.goals_nav_related,
      child: WorkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.glink_form_hint, style: sheetBodyStyle(context)),
            if (contributing.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.glink_form_measured_hint,
                style: sheetBodyStyle(context),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final values = await showDialog<Set<String>>(
                  context: context,
                  builder: (_) => _SupportingGoalsPicker(
                    selected: selected,
                    fixed: contributing,
                  ),
                );
                if (values != null) onChanged(values);
              },
              icon: const Icon(LucideIcons.link, size: 18),
              label: Text(
                titles.isEmpty
                    ? context.l10n.glink_select_goals
                    : context.l10n.glink_selected_goals(titles.length),
              ),
            ),
            if (titles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(titles.join(', '), style: sheetBodyStyle(context)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupportingGoalsPicker extends StatefulWidget {
  const _SupportingGoalsPicker({required this.selected, required this.fixed});
  final Set<String> selected;
  final Set<String> fixed;
  @override
  State<_SupportingGoalsPicker> createState() => _SupportingGoalsPickerState();
}

class _SupportingGoalsPickerState extends State<_SupportingGoalsPicker> {
  late final _selected = {...widget.selected};
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GoalsController>();
    final goals = [
      ...controller.goals(query: _query),
      ...controller
          .goals(archived: true, query: _query)
          .where((goal) => _selected.contains(goal.id)),
    ];
    final unavailable = _selected
        .where(
          (id) => controller.byId(id) == null || controller.byId(id)!.isDeleted,
        )
        .toList();
    return AlertDialog(
      title: Text(context.l10n.glink_select_goals),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: context.l10n.goals_nav_search,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (goals.isEmpty && unavailable.isEmpty)
                    Text(context.l10n.goals_nav_none),
                  for (final id in unavailable)
                    CheckboxListTile(
                      title: Text(context.l10n.glink_goal_unavailable),
                      value: true,
                      onChanged: widget.fixed.contains(id)
                          ? null
                          : (_) => setState(() => _selected.remove(id)),
                    ),
                  for (final goal in goals)
                    CheckboxListTile(
                      title: Text(goal.title),
                      subtitle: goal.isArchived
                          ? Text(context.l10n.glink_form_archived_hint)
                          : widget.fixed.contains(goal.id)
                          ? Text(context.l10n.glink_form_measured_hint)
                          : null,
                      value: _selected.contains(goal.id),
                      onChanged:
                          goal.isArchived || widget.fixed.contains(goal.id)
                          ? null
                          : (selected) => setState(() {
                              if (selected == true) {
                                _selected.add(goal.id);
                              } else {
                                _selected.remove(goal.id);
                              }
                            }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text(context.l10n.done),
        ),
      ],
    );
  }
}
