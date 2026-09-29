import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/pages/goal_details_page.dart';
import 'package:streak/features/goals/pages/goals_page.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/goals/widgets/goal_ui.dart';
import 'package:streak/features/work/data/work_insights.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

class WorkInsightsPage extends StatefulWidget implements FullWidthPage {
  const WorkInsightsPage({super.key, this.areaId});
  final String? areaId;
  @override
  State<WorkInsightsPage> createState() => _WorkInsightsPageState();
}

class _WorkInsightsPageState extends State<WorkInsightsPage> {
  int _days = 7;
  late String? _areaId = widget.areaId;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final focus = context.watch<FocusController>();
    final goals = context.watch<GoalsController>();
    final areaId =
        work.data.areas.any((area) => area.id == _areaId && !area.isDeleted)
        ? _areaId
        : null;
    final now = AppClock.wallNow();
    final until = now.atMidnight.addDays(1);
    final from = until.addDays(-_days);
    final result = WorkInsights.compute(
      data: work.data,
      sessions: focus.sessions,
      from: from,
      until: until,
      now: now,
      areaId: areaId,
    );
    final allocation = result.projectSeconds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final outcomes = goals.goals(scope: GoalScope.work, areaId: areaId);
    final maxDay = result.dailySeconds.values.fold<int>(
      1,
      (a, b) => a > b ? a : b,
    );
    final locale = Localizations.localeOf(context).toString();
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.goals_nav_insights)),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 32),
        children: [
          Text(
            context.l10n.goals_insights_intro,
            style: sheetBodyStyle(context),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final days in [7, 30])
                ChoiceChip(
                  label: Text(context.l10n.goals_insights_days(days)),
                  selected: _days == days,
                  onSelected: (_) => setState(() => _days = days),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            key: ValueKey(areaId),
            initialValue: areaId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.l10n.work_area_selector,
            ),
            items: [
              DropdownMenuItem(value: null, child: Text(context.l10n.all)),
              for (final area in work.data.areas.where(
                (area) => !area.isDeleted,
              ))
                DropdownMenuItem(value: area.id, child: Text(area.name)),
            ],
            onChanged: (value) => setState(() => _areaId = value),
          ),
          const SizedBox(height: 24),
          WorkSection(
            title: context.l10n.work_time_title,
            child: WorkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    formatHoursShort(result.seconds),
                    style: sheetHeadingStyle(context, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.work_time_breakdown(
                      formatHoursShort(result.seconds - result.manualSeconds),
                      formatHoursShort(result.manualSeconds),
                    ),
                    style: sheetBodyStyle(context),
                  ),
                  const SizedBox(height: 16),
                  if (allocation.isEmpty)
                    Text(
                      context.l10n.goals_insights_no_time,
                      style: sheetBodyStyle(context),
                    ),
                  for (final entry in allocation)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.l10n.goals_insights_allocation(
                              entry.key.isEmpty
                                  ? context.l10n.work_standalone_tasks
                                  : result.projectTitles[entry.key]!,
                              formatHoursShort(entry.value),
                            ),
                            style: sheetBodyStyle(context),
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: result.seconds == 0
                                ? 0
                                : entry.value / result.seconds,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          WorkSection(
            title: context.l10n.goals_insights_delivery,
            child: WorkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.goals_insights_completed(
                      result.completedTasks,
                    ),
                    style: sheetHeadingStyle(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.goals_insights_open(
                      result.openTasks,
                      result.overdueTasks,
                      result.blockedTasks,
                    ),
                    style: sheetBodyStyle(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.goals_insights_delivery_hint,
                    style: sheetBodyStyle(context),
                  ),
                ],
              ),
            ),
          ),
          WorkSection(
            title: context.l10n.goals_insights_daily,
            child: WorkCard(
              child: Column(
                children: [
                  for (final day in result.dailySeconds.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              DateFormat.MMMd(
                                locale,
                              ).format(parseDayKey(day.key)),
                              style: sheetBodyStyle(context, size: 13),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: LinearProgressIndicator(
                              value: day.value / maxDay,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Text(
                              formatHoursShort(day.value),
                              textAlign: TextAlign.end,
                              style: sheetBodyStyle(context, size: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          WorkSection(
            title: context.l10n.goals_insights_outcomes,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.goals_insights_outcomes_hint,
                  style: sheetBodyStyle(context),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => AppNavigator.push(
                      GoalsPage(initialScope: GoalScope.work, areaId: areaId),
                    ),
                    child: Text(context.l10n.goals_nav_browse),
                  ),
                ),
                const SizedBox(height: 12),
                if (outcomes.isEmpty)
                  Text(
                    context.l10n.goals_nav_none,
                    style: sheetBodyStyle(context),
                  ),
                for (final goal in outcomes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GoalCard(
                      goal: goal,
                      onOpen: () =>
                          AppNavigator.push(GoalDetailsPage(goalId: goal.id)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
