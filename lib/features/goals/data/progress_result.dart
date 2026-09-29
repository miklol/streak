import 'package:streak/features/goals/data/goal_progress.dart';

enum GoalProgressIssue {
  needsHabit,
  needsWork,
  missingHabit,
  sourceChanged,
  incompatible,
  noWorkItems,
  invalidData,
}

class GoalProgressResult {
  const GoalProgressResult({this.progress, this.issue})
    : assert(progress == null || issue == null);

  final GoalProgress? progress;
  final GoalProgressIssue? issue;

  bool get isAvailable => progress != null;
}
