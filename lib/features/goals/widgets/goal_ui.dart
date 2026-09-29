import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show HiveError;
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/progress_result.dart';
import 'package:streak/features/goals/state/goals_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

String goalStatusLabel(BuildContext context, GoalStatus status) =>
    switch (status) {
      GoalStatus.notStarted => context.l10n.goal_status_not_started,
      GoalStatus.active => context.l10n.goal_status_active,
      GoalStatus.paused => context.l10n.goal_status_paused,
      GoalStatus.achieved => context.l10n.goal_status_achieved,
      GoalStatus.cancelled => context.l10n.goal_status_cancelled,
    };

String goalSourceLabel(BuildContext context, GoalSource source) =>
    switch (source) {
      GoalSource.manual => context.l10n.goal_source_manual,
      GoalSource.habits => context.l10n.goal_source_habits,
      GoalSource.work => context.l10n.goal_source_work,
    };

String goalMeasurementLabel(
  BuildContext context,
  GoalMeasurement measurement,
) => switch (measurement) {
  GoalMeasurement.completion => context.l10n.goal_measurement_completion,
  GoalMeasurement.percentage => context.l10n.goal_measurement_percentage,
  GoalMeasurement.number => context.l10n.goal_measurement_number,
  GoalMeasurement.currency => context.l10n.goal_measurement_currency,
};

String goalProgressIssueLabel(BuildContext context, GoalProgressIssue issue) =>
    switch (issue) {
      GoalProgressIssue.needsHabit => context.l10n.goal_needs_habit,
      GoalProgressIssue.needsWork => context.l10n.goal_needs_work,
      GoalProgressIssue.missingHabit => context.l10n.goal_missing_habit,
      GoalProgressIssue.sourceChanged => context.l10n.goal_source_changed,
      GoalProgressIssue.incompatible => context.l10n.goal_incompatible,
      GoalProgressIssue.noWorkItems => context.l10n.goal_no_work_items,
      GoalProgressIssue.invalidData => context.l10n.goal_invalid_data,
    };

String goalValueLabel(BuildContext context, Goal goal, double value) {
  return goalMeasurementValueLabel(
    context,
    measurement: goal.measurement,
    value: value,
    unit: goal.measurement == GoalMeasurement.currency
        ? goal.currency
        : goal.unit,
    target: goal.target,
  );
}

String goalMeasurementValueLabel(
  BuildContext context, {
  required GoalMeasurement measurement,
  required double value,
  String unit = '',
  double target = 1,
}) {
  final locale = Localizations.localeOf(context).toString();
  final numeric = goalNumberLabel(context, value);
  return switch (measurement) {
    GoalMeasurement.completion =>
      value >= target
          ? context.l10n.goal_completion_done
          : context.l10n.goal_completion_pending,
    GoalMeasurement.percentage => context.l10n.goal_value_percent(numeric),
    GoalMeasurement.number => switch (unit.trim()) {
      '' => numeric,
      'days' when value == value.roundToDouble() && value.abs() < 1e12 =>
        context.l10n.count_days(value.toInt()),
      'minutes' => '$numeric ${context.l10n.unit_min_short}',
      'hours' => '$numeric ${context.l10n.unit_hour_short}',
      _ => '$numeric ${unit.trim()}',
    },
    GoalMeasurement.currency => NumberFormat.simpleCurrency(
      locale: locale,
      name: unit,
    ).format(value),
  };
}

String goalProgressSummary(BuildContext context, Goal goal, double value) {
  if (goal.measurement == GoalMeasurement.completion) {
    return goalValueLabel(context, goal, value);
  }
  if (goal.target < goal.baseline || goal.baseline != 0) {
    return context.l10n.goal_current_target(
      goalValueLabel(context, goal, value),
      goalValueLabel(context, goal, goal.target),
    );
  }
  return context.l10n.goal_progress_value(
    goalValueLabel(context, goal, value),
    goalValueLabel(context, goal, goal.target),
  );
}

String goalErrorMessage(BuildContext context, Object error) {
  if (error is GoalOperationException) {
    return switch (error.code) {
      GoalFailure.missing => context.l10n.goal_error_missing,
      GoalFailure.stale => context.l10n.goal_error_stale,
      GoalFailure.archived => context.l10n.goal_error_archived,
      GoalFailure.invalidMeasurement =>
        context.l10n.goal_error_invalid_measurement,
      GoalFailure.invalidLink => context.l10n.goal_error_invalid_link,
      GoalFailure.sourceChanged => context.l10n.goal_error_source_changed,
      GoalFailure.incomplete => context.l10n.goal_error_incomplete,
      GoalFailure.invalidNote => context.l10n.goal_error_invalid_note,
    };
  }
  if (error is ArgumentError ||
      error is StateError ||
      error is FileSystemException ||
      error is HiveError ||
      error is PlatformException) {
    return context.l10n.goal_action_failed;
  }
  return context.l10n.goal_action_failed;
}

Future<bool> runGoalAction(
  BuildContext context,
  Future<void> Function() action, {
  ValueChanged<Object>? onError,
}) async {
  void report(Object error) {
    debugPrint('Goal action failed: $error');
    if (onError != null) {
      onError(error);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            goalErrorMessage(context, error),
          ),
        ),
      );
    }
  }

  try {
    await action();
    return true;
  } on GoalOperationException catch (error) {
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

class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    this.onOpen,
  });

  final Goal goal;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    final result = goals.progressFor(goal.id);
    final progress = result.progress;
    final issue = result.issue;
    final statusColor = _statusColor(context, goal.status);
    final fraction = progress?.fraction.clamp(0.0, 1.0);
    final valueText = progress == null
        ? (issue == null
              ? context.l10n.goal_progress_empty
              : goalProgressIssueLabel(context, issue))
        : goalProgressSummary(context, goal, progress.value);
    final percentText = progress == null
        ? context.l10n.goal_progress_unavailable
        : context.l10n.goal_progress_percent((progress.fraction * 100).round());

    return Semantics(
      button: onOpen != null,
      label: goal.title,
      child: WorkCard(
        key: ValueKey('goal-card-${goal.id}'),
        onTap: onOpen,
        borderColor: issue == null
            ? null
            : context.tokens.warning.withValues(alpha: 0.55),
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
                        goal.title,
                        style: sheetHeadingStyle(context, size: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _cardSubtitle(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sheetBodyStyle(context, size: 13.5),
                      ),
                    ],
                  ),
                ),
                if (onOpen != null) ...[
                  const SizedBox(width: 12),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: context.tokens.muted,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GoalBadge(
                  child: WorkBadge(
                    icon: _statusIcon(goal.status),
                    label: goalStatusLabel(context, goal.status),
                    color: statusColor,
                  ),
                ),
                GoalBadge(
                  child: WorkBadge(
                    icon: _sourceIcon(goal.source),
                    label: goalSourceLabel(context, goal.source),
                    color: context.colors.primary,
                  ),
                ),
                if (goal.pinned && goal.scope == GoalScope.personal)
                  GoalBadge(
                    child: WorkBadge(
                      icon: LucideIcons.pin,
                      label: context.l10n.goal_pinned,
                      color: context.tokens.info,
                    ),
                  ),
                if (goal.isArchived)
                  GoalBadge(
                    child: WorkBadge(
                      icon: LucideIcons.archive,
                      label: context.l10n.goal_archived,
                      color: context.tokens.muted,
                    ),
                  ),
                if (issue != null)
                  GoalBadge(
                    child: WorkBadge(
                      icon: LucideIcons.triangleAlert,
                      label: context.l10n.goal_progress,
                      color: context.tokens.warning,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: fraction ?? 0,
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            DefaultTextStyle.merge(
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(percentText, style: sheetBodyStyle(context, size: 13)),
                  const SizedBox(height: 4),
                  Text(
                    valueText,
                    style: sheetBodyStyle(
                      context,
                      size: 13,
                      color: issue == null ? null : context.tokens.warning,
                    ),
                  ),
                  if (goal.endDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      workDateLabel(context, goal.endDate),
                      style: sheetBodyStyle(context, size: 13),
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

  String _cardSubtitle(BuildContext context) {
    final parts = <String>[
      goalMeasurementLabel(context, goal.measurement),
      if (goal.category.trim().isNotEmpty) goal.category.trim(),
    ];
    return parts.join(' • ');
  }
}

class GoalBadge extends StatelessWidget {
  const GoalBadge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: child,
    );
  }
}

class GoalScopeSelector extends StatelessWidget {
  const GoalScopeSelector({super.key, required this.scope, this.onChanged});
  final GoalScope scope;
  final ValueChanged<GoalScope>? onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.l10n.goal_scope_personal,
      context.l10n.goal_scope_work,
    ];
    final textStyle =
        SegmentedButtonTheme.of(context).style?.textStyle?.resolve({}) ??
        Theme.of(context).textTheme.labelLarge;
    final labelWidth = labels.fold<double>(
      0,
      (width, label) =>
          width +
          TextPainter.computeWidth(
            text: TextSpan(text: label, style: textStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => SegmentedButton<GoalScope>(
        direction: constraints.maxWidth < labelWidth + 136
            ? Axis.vertical
            : Axis.horizontal,
        segments: [
          ButtonSegment(
            value: GoalScope.personal,
            icon: const Icon(LucideIcons.user, size: 18),
            label: Text(labels[0]),
          ),
          ButtonSegment(
            value: GoalScope.work,
            icon: const Icon(LucideIcons.briefcase, size: 18),
            label: Text(labels[1]),
          ),
        ],
        selected: {scope},
        onSelectionChanged: onChanged == null
            ? null
            : (values) => onChanged!(values.single),
      ),
    );
  }
}

IconData _statusIcon(GoalStatus status) => switch (status) {
  GoalStatus.notStarted => LucideIcons.circle,
  GoalStatus.active => LucideIcons.play,
  GoalStatus.paused => LucideIcons.pause,
  GoalStatus.achieved => LucideIcons.circleCheck,
  GoalStatus.cancelled => LucideIcons.circleSlash,
};

IconData _sourceIcon(GoalSource source) => switch (source) {
  GoalSource.manual => LucideIcons.penLine,
  GoalSource.habits => LucideIcons.repeat2,
  GoalSource.work => LucideIcons.briefcase,
};

Color _statusColor(BuildContext context, GoalStatus status) => switch (status) {
  GoalStatus.notStarted => context.colors.primary,
  GoalStatus.active => context.tokens.info,
  GoalStatus.paused => context.tokens.warning,
  GoalStatus.achieved => context.tokens.success,
  GoalStatus.cancelled => context.tokens.muted,
};

String goalNumberLabel(BuildContext context, double value) {
  final format =
      NumberFormat.decimalPattern(Localizations.localeOf(context).toString())
        ..minimumFractionDigits = 0
        ..maximumFractionDigits = 2;
  return format.format(value);
}
