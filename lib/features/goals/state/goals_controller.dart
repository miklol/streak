import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/goals/data/goal_habit_link.dart';
import 'package:streak/features/goals/data/goal_progress.dart';
import 'package:streak/features/goals/data/progress_result.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/work/data/work_data.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_progress.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:uuid/uuid.dart';

enum GoalFailure {
  missing,
  stale,
  archived,
  invalidMeasurement,
  invalidLink,
  sourceChanged,
  incomplete,
  invalidNote,
}

class GoalOperationException implements Exception {
  const GoalOperationException(this.code);

  final GoalFailure code;

  @override
  String toString() => 'Goal operation failed: ${code.name}';
}

class GoalsController extends ChangeNotifier {
  GoalsController(
    this.work,
    this.habits, {
    DateTime Function()? now,
  }) : _now = now ?? AppClock.wallNow {
    work.addListener(_sourceChanged);
    habits.addListener(_sourceChanged);
  }

  final WorkController work;
  final HabitsController habits;
  final DateTime Function() _now;
  bool _disposed = false;

  WorkData get data => work.data;

  @override
  void dispose() {
    if (!_disposed) {
      work.removeListener(_sourceChanged);
      habits.removeListener(_sourceChanged);
      _disposed = true;
    }
    super.dispose();
  }

  void _sourceChanged() {
    if (!_disposed) notifyListeners();
  }

  void reload() => work.reload();

  Goal? byId(String id) => _find(data.goals, id);

  List<Goal> goals({
    GoalScope? scope,
    bool archived = false,
    GoalStatus? status,
    String query = '',
    String? areaId,
    String? projectId,
  }) {
    final term = query.trim().toLowerCase();
    return data.goals.where((goal) {
      if (goal.isDeleted || goal.isArchived != archived) return false;
      if (scope != null && goal.scope != scope) return false;
      if (status != null && goal.status != status) return false;
      if ((areaId != null || projectId != null) &&
          !_relatedToWork(goal, areaId: areaId, projectId: projectId)) {
        return false;
      }
      if (term.isEmpty) return true;
      return '${goal.title}\n${goal.description}\n${goal.category}\n'
              '${goal.why}\n${goal.unit}\n${goal.currency}'
          .toLowerCase()
          .contains(term);
    }).toList()..sort(_goalSort);
  }

  List<Goal> get pinnedPersonal => goals(scope: GoalScope.personal)
      .where(
        (goal) =>
            goal.pinned &&
            goal.status != GoalStatus.achieved &&
            goal.status != GoalStatus.cancelled,
      )
      .toList();

  List<Goal> forHabit(String habitId) {
    final linked = linksForHabit(habitId).map((link) => link.goalId).toSet();
    return data.goals
        .where(
          (goal) => linked.contains(goal.id) && !goal.isDeleted,
        )
        .toList()
      ..sort(_goalSort);
  }

  List<Goal> forWork({String? areaId, String? projectId, String? taskId}) =>
      data.goals
          .where(
            (goal) =>
                !goal.isDeleted &&
                _relatedToWork(
                  goal,
                  areaId: areaId,
                  projectId: projectId,
                  taskId: taskId,
                ),
          )
          .toList()
        ..sort(_goalSort);

  bool _relatedToWork(
    Goal goal, {
    String? areaId,
    String? projectId,
    String? taskId,
  }) {
    if (areaId == null && projectId == null && taskId == null) return false;
    final projects = {
      if (goal.projectId != null) goal.projectId!,
      ...goal.projectIds,
    };
    final tasks = goal.taskIds.map(work.taskById).whereType<WorkTask>();
    if (areaId != null &&
        goal.areaId != areaId &&
        !projects.any((id) => work.projectById(id)?.areaId == areaId) &&
        !tasks.any((task) => work.areaForTask(task) == areaId)) {
      return false;
    }
    if (projectId != null &&
        !projects.contains(projectId) &&
        !tasks.any((task) => task.projectId == projectId)) {
      return false;
    }
    if (taskId != null) {
      final task = work.taskById(taskId);
      if (!goal.taskIds.contains(taskId) &&
          !goal.taskIds.contains(task?.parentTaskId) &&
          !projects.contains(task?.projectId) &&
          !tasks.any((selected) => selected.parentTaskId == taskId)) {
        return false;
      }
    }
    return true;
  }

  List<GoalHabitLink> linksForGoal(String goalId) =>
      data.habitLinks
          .where((link) => link.goalId == goalId && !link.isDeleted)
          .toList()
        ..sort(_linkSort);

  List<GoalHabitLink> linksForHabit(String habitId) =>
      data.habitLinks
          .where((link) => link.habitId == habitId && !link.isDeleted)
          .toList()
        ..sort(_linkSort);

  List<WorkEntry> entriesFor(String goalId) {
    final order = {
      for (var index = 0; index < data.entries.length; index++)
        data.entries[index].id: index,
    };
    return data.entries
        .where(
          (entry) =>
              entry.entityKind == WorkEntityKind.goal &&
              entry.entityId == goalId &&
              !entry.isDeleted,
        )
        .toList()
      ..sort((a, b) {
        final day = parseDayKey(b.date).epochDay.compareTo(
          parseDayKey(a.date).epochDay,
        );
        if (day != 0) return day;
        final time = b.meta.createdAt.compareTo(a.meta.createdAt);
        return time != 0 ? time : order[b.id]!.compareTo(order[a.id]!);
      });
  }

  GoalProgressResult progressFor(String goalId, {DateTime? asOf}) {
    final goal = byId(goalId);
    if (goal == null || goal.isDeleted) {
      return const GoalProgressResult(issue: GoalProgressIssue.invalidData);
    }
    return previewGoal(goal, asOf: asOf);
  }

  GoalProgressResult previewGoal(
    Goal draft, {
    List<GoalHabitLink>? links,
    DateTime? asOf,
  }) {
    final activeLinks = links ?? linksForGoal(draft.id);
    return _progressFor(draft, activeLinks, asOf ?? _logicalNow);
  }

  Future<Goal> saveGoal(
    Goal draft, {
    int? expectedRevision,
    List<GoalHabitLink>? links,
  }) async {
    late Goal saved;
    await _change((state) {
      final old = _find(state.goals, draft.id);
      final meta = _saveMeta(old, draft.meta, expectedRevision);
      if (old?.isArchived == true) {
        throw const GoalOperationException(GoalFailure.archived);
      }
      var habitLinks = state.habitLinks;
      final entries = [...state.entries];
      saved = draft.copyWith(
        meta: meta,
        title: draft.title.trim(),
        description: draft.description.trim(),
        category: draft.category.trim(),
        why: draft.why.trim(),
        unit: draft.unit.trim(),
        currency: draft.currency.trim(),
        order: old?.order ?? _nextOrder(state.goals.map((goal) => goal.order)),
      );
      final existingActiveLinks = state.habitLinks
          .where((link) => link.goalId == saved.id && !link.isDeleted)
          .toList();
      final activeLinks = links == null
          ? existingActiveLinks
          : _preparedGoalLinks(state, saved, links, entries);
      if (old == null ||
          _goalMeasurementConfigChanged(old, saved) ||
          (links != null &&
              _contributorLinksChanged(existingActiveLinks, activeLinks))) {
        _requireSavableProgress(saved, activeLinks, state: state);
      }
      if (saved.status == GoalStatus.achieved &&
          old?.status != GoalStatus.achieved) {
        saved = _achievedGoal(saved, activeLinks, state);
      }
      if (old == null) {
        entries.add(
          _goalEvent(
            saved,
            WorkEntryKind.scopeChange,
            text: jsonEncode({'type': 'goal', 'action': 'create'}),
          ),
        );
        if (saved.source == GoalSource.manual &&
            saved.current != saved.baseline) {
          entries.add(
            _goalEvent(saved, WorkEntryKind.progress, value: saved.current),
          );
        }
      }
      if (old != null && old.status != saved.status) {
        entries.add(
          _goalEvent(
            saved,
            WorkEntryKind.statusChange,
            fromStatus: old.status.name,
            status: saved.status.name,
          ),
        );
      }
      if (old != null &&
          saved.source == GoalSource.manual &&
          (old.current != saved.current || old.source != GoalSource.manual)) {
        entries.add(
          _goalEvent(
            saved,
            WorkEntryKind.progress,
            fromValue: _sameMeasurementUnit(old, saved) ? old.current : null,
            value: saved.current,
          ),
        );
      }
      if (old != null && _goalScopeHistoryChanged(old, saved)) {
        entries.add(
          _goalEvent(
            saved,
            WorkEntryKind.scopeChange,
            text: jsonEncode({'type': 'goal'}),
          ),
        );
      }
      if (links != null) {
        habitLinks = _replaceLinksForGoal(habitLinks, saved.id, activeLinks);
      }
      return state.copyWith(
        goals: _put(state.goals, saved),
        habitLinks: habitLinks,
        entries: entries,
      );
    });
    return byId(saved.id)!;
  }

  Future<Goal> recordProgress(
    Goal original,
    double value, {
    String note = '',
    String? date,
  }) async {
    if (original.source != GoalSource.manual) {
      throw const GoalOperationException(GoalFailure.invalidMeasurement);
    }
    if (!value.isFinite) {
      throw const GoalOperationException(GoalFailure.invalidMeasurement);
    }
    final day = date ?? _todayKey;
    requireDay(day, 'date');
    if (parseDayKey(day).epochDay > _logicalNow.epochDay) {
      throw const GoalOperationException(GoalFailure.invalidMeasurement);
    }
    late Goal saved;
    await _change((state) {
      final current = _requireCurrentGoal(state, original);
      final trimmed = note.trim();
      final observedDay = state.entries
          .where(
            (entry) =>
                entry.entityKind == WorkEntityKind.goal &&
                entry.entityId == current.id &&
                entry.kind == WorkEntryKind.progress &&
                !entry.isDeleted,
          )
          .fold<int?>(null, (latest, entry) {
            final day = parseDayKey(entry.date).epochDay;
            return latest == null || day > latest ? day : latest;
          });
      final latestDay =
          observedDay ??
          (current.current == current.baseline
              ? null
              : parseDayKey(current.meta.createdDay).epochDay);
      final isLatest =
          latestDay == null || parseDayKey(day).epochDay >= latestDay;
      saved = current.copyWith(
        meta: _touch(current.meta),
        current: isLatest ? value : current.current,
      );
      final entries = [...state.entries];
      entries.add(
        _goalEvent(
          saved,
          WorkEntryKind.progress,
          date: day,
          text: trimmed,
          fromValue: isLatest ? current.current : null,
          value: value,
        ),
      );
      return state.copyWith(goals: _put(state.goals, saved), entries: entries);
    });
    return byId(saved.id)!;
  }

  Future<void> setStatus(Goal original, GoalStatus status) async {
    await _change((state) {
      final current = _requireCurrentGoal(state, original);
      var next = current;
      if (status == GoalStatus.achieved) {
        next = _achievedGoal(
          current,
          state.habitLinks
              .where((link) => link.goalId == current.id && !link.isDeleted)
              .toList(),
          state,
        );
      }
      if (next.status == status &&
          (next.measurement != GoalMeasurement.completion ||
              next.current == current.current)) {
        return state;
      }
      next = next.copyWith(meta: _touch(next.meta), status: status);
      return state.copyWith(
        goals: _put(state.goals, next),
        entries: [
          ...state.entries,
          if (next.current != current.current)
            _goalEvent(
              next,
              WorkEntryKind.progress,
              fromValue: current.current,
              value: next.current,
            ),
          _goalEvent(
            next,
            WorkEntryKind.statusChange,
            fromStatus: current.status.name,
            status: status.name,
          ),
        ],
      );
    });
  }

  Future<void> setArchived(Goal original, bool archived) async {
    await _change((state) {
      final current = _requireCurrentGoal(state, original, allowArchived: true);
      if (current.isArchived == archived) return state;
      final next = current.copyWith(
        meta: _touch(current.meta, archived: archived),
      );
      return state.copyWith(goals: _put(state.goals, next));
    });
  }

  Future<void> setPinned(Goal original, bool pinned) async {
    await _change((state) {
      final current = _requireCurrentGoal(state, original);
      if (current.pinned == pinned) return state;
      final next = current.copyWith(meta: _touch(current.meta), pinned: pinned);
      return state.copyWith(goals: _put(state.goals, next));
    });
  }

  Future<WorkEntry> saveNote(
    Goal original,
    String text, {
    WorkEntry? existing,
    List<String>? photos,
  }) async {
    final trimmed = text.trim();
    final attachments = List<String>.of(photos ?? existing?.photos ?? const []);
    if (trimmed.isEmpty || attachments.any((path) => path.trim().isEmpty)) {
      throw const GoalOperationException(GoalFailure.invalidNote);
    }
    late WorkEntry saved;
    await _change((state) {
      _requireCurrentGoal(state, original);
      final old = existing == null ? null : _find(state.entries, existing.id);
      if (existing != null) {
        if (old == null ||
            old.isDeleted ||
            old.kind != WorkEntryKind.note ||
            old.entityKind != WorkEntityKind.goal ||
            old.entityId != original.id) {
          throw const GoalOperationException(GoalFailure.missing);
        }
        if (old.meta.revision != existing.meta.revision) {
          throw const GoalOperationException(GoalFailure.stale);
        }
        saved = old.copyWith(
          meta: _touch(old.meta),
          text: trimmed,
          photos: attachments,
        );
      } else {
        saved = WorkEntry(
          meta: _newMeta(),
          entityKind: WorkEntityKind.goal,
          entityId: original.id,
          kind: WorkEntryKind.note,
          text: trimmed,
          photos: attachments,
        );
      }
      return state.copyWith(entries: _put(state.entries, saved));
    });
    return _find(work.data.entries, saved.id)!;
  }

  Future<void> removeNote(WorkEntry original) async {
    await _change((state) {
      final current = _find(state.entries, original.id);
      if (current == null ||
          current.isDeleted ||
          current.kind != WorkEntryKind.note ||
          current.entityKind != WorkEntityKind.goal) {
        throw const GoalOperationException(GoalFailure.invalidNote);
      }
      final goal = _find(state.goals, current.entityId);
      if (goal == null || goal.isDeleted) {
        throw const GoalOperationException(GoalFailure.missing);
      }
      if (goal.isArchived) {
        throw const GoalOperationException(GoalFailure.archived);
      }
      if (current.meta.revision != original.meta.revision) {
        throw const GoalOperationException(GoalFailure.stale);
      }
      return state.copyWith(
        entries: _put(
          state.entries,
          current.copyWith(meta: _touch(current.meta, deleted: true)),
        ),
      );
    });
  }

  GoalHabitLink buildHabitLink({
    required String goalId,
    required String habitId,
    GoalHabitRole role = GoalHabitRole.supporting,
    HabitGoalMetric metric = HabitGoalMetric.completedDays,
    String? startDate,
    String? endDate,
    String? unit,
    GoalHabitLink? existing,
  }) {
    final meta = existing?.meta ?? _newMeta();
    if (role == GoalHabitRole.supporting) {
      return GoalHabitLink(
        meta: meta,
        goalId: goalId,
        habitId: habitId,
        role: role,
        metric: metric,
        startDate: startDate,
        endDate: endDate,
        unit: unit ?? '',
      );
    }
    final habit = habits.byId(habitId);
    if (habit == null) throw ArgumentError('Unknown habit source');
    return GoalHabitLink.forHabit(
      meta: meta,
      goalId: goalId,
      habit: habit,
      role: role,
      metric: metric,
      startDate: startDate,
      endDate: endDate,
      unit: unit,
    );
  }

  GoalProgressResult previewHabitLink(GoalHabitLink draft) {
    final goal = byId(draft.goalId);
    if (goal == null || goal.isDeleted) {
      return const GoalProgressResult(issue: GoalProgressIssue.invalidData);
    }
    return previewGoal(
      goal,
      links: _linkReplacement(linksForGoal(goal.id), draft),
    );
  }

  Future<GoalHabitLink> saveHabitLink(
    GoalHabitLink draft, {
    int? expectedRevision,
  }) async {
    late GoalHabitLink saved;
    await _change((state) {
      final goal = _find(state.goals, draft.goalId);
      if (goal == null || goal.isDeleted) {
        throw const GoalOperationException(GoalFailure.missing);
      }
      if (goal.isArchived) {
        throw const GoalOperationException(GoalFailure.archived);
      }
      final old = _find(state.habitLinks, draft.id);
      if (old?.isDeleted == true) {
        throw const GoalOperationException(GoalFailure.missing);
      }
      if (old != null && old.meta.revision != expectedRevision) {
        throw const GoalOperationException(GoalFailure.stale);
      }
      if (old == null && expectedRevision != null) {
        throw const GoalOperationException(GoalFailure.missing);
      }
      final samePair = state.habitLinks
          .where(
            (link) =>
                !link.isDeleted &&
                link.goalId == draft.goalId &&
                link.habitId == draft.habitId,
          )
          .firstOrNull;
      if (samePair != null && samePair.id != draft.id) {
        throw const GoalOperationException(GoalFailure.invalidLink);
      }
      final changed = old == null || !_sameLinkBody(old, draft);
      saved = changed ? _prepareSingleLink(goal, draft, old) : old;
      if (!changed) return state;
      if (saved.role == GoalHabitRole.contributor ||
          old?.role == GoalHabitRole.contributor) {
        _requireSavableProgress(
          goal,
          _linkReplacement(
            state.habitLinks
                .where((link) => link.goalId == goal.id && !link.isDeleted)
                .toList(),
            saved,
          ),
          state: state,
        );
      }
      return state.copyWith(
        goals: _put(state.goals, goal.copyWith(meta: _touch(goal.meta))),
        habitLinks: _put(state.habitLinks, saved),
        entries: [
          ...state.entries,
          _goalEvent(
            goal,
            WorkEntryKind.scopeChange,
            text: _linkEventText(saved, old == null ? 'add' : 'update'),
          ),
        ],
      );
    });
    return _find(work.data.habitLinks, saved.id)!;
  }

  GoalProgressResult previewUnlink(GoalHabitLink link) {
    final goal = byId(link.goalId);
    if (goal == null || goal.isDeleted) {
      return const GoalProgressResult(issue: GoalProgressIssue.invalidData);
    }
    return previewGoal(
      goal,
      links: linksForGoal(
        goal.id,
      ).where((candidate) => candidate.id != link.id).toList(),
    );
  }

  Future<void> unlinkHabit(GoalHabitLink original) async {
    await _change((state) {
      final current = _find(state.habitLinks, original.id);
      if (current == null || current.isDeleted) {
        throw const GoalOperationException(GoalFailure.missing);
      }
      if (current.meta.revision != original.meta.revision) {
        throw const GoalOperationException(GoalFailure.stale);
      }
      final goal = _find(state.goals, current.goalId);
      if (goal == null || goal.isDeleted) {
        throw const GoalOperationException(GoalFailure.missing);
      }
      if (goal.isArchived) {
        throw const GoalOperationException(GoalFailure.archived);
      }
      final removed = current.copyWith(
        meta: _touch(current.meta, deleted: true),
      );
      return state.copyWith(
        goals: _put(state.goals, goal.copyWith(meta: _touch(goal.meta))),
        habitLinks: _put(state.habitLinks, removed),
        entries: [
          ...state.entries,
          _goalEvent(
            goal,
            WorkEntryKind.scopeChange,
            text: _linkEventText(current, 'remove'),
          ),
        ],
      );
    });
  }

  Future<void> setSupportingGoals(
    String habitId,
    Set<String> selectedGoalIds,
  ) async {
    if (habits.byId(habitId) == null) {
      throw const GoalOperationException(GoalFailure.missing);
    }
    await _change((state) {
      var links = state.habitLinks;
      final entries = [...state.entries];
      final changedGoals = <String>{};
      final active = state.habitLinks
          .where((link) => link.habitId == habitId && !link.isDeleted)
          .toList();
      final activeByGoal = {for (final link in active) link.goalId: link};
      final preserved = {
        for (final link in active)
          if (link.role == GoalHabitRole.contributor ||
              _find(state.goals, link.goalId)?.isArchived == true)
            link.goalId,
      };
      final selected = {...selectedGoalIds, ...preserved};
      for (final id in selected) {
        if (activeByGoal.containsKey(id)) continue;
        final goal = _find(state.goals, id);
        if (goal == null || goal.isDeleted) {
          throw const GoalOperationException(GoalFailure.missing);
        }
        if (goal.isArchived) {
          throw const GoalOperationException(GoalFailure.archived);
        }
      }
      for (final link in active) {
        if (link.role == GoalHabitRole.supporting &&
            !selected.contains(link.goalId)) {
          final removed = link.copyWith(meta: _touch(link.meta, deleted: true));
          links = _put(links, removed);
          changedGoals.add(link.goalId);
          final goal = _find(state.goals, link.goalId);
          if (goal != null) {
            entries.add(
              _goalEvent(
                goal,
                WorkEntryKind.scopeChange,
                text: _linkEventText(link, 'remove'),
              ),
            );
          }
        }
      }
      for (final id in selectedGoalIds) {
        final existing = active.where((link) => link.goalId == id).firstOrNull;
        if (existing != null) continue;
        final goal = _find(state.goals, id)!;
        final link = GoalHabitLink(
          meta: _newMeta(),
          goalId: id,
          habitId: habitId,
        );
        links = _put(links, link);
        changedGoals.add(id);
        entries.add(
          _goalEvent(
            goal,
            WorkEntryKind.scopeChange,
            text: _linkEventText(link, 'add'),
          ),
        );
      }
      if (changedGoals.isEmpty) return state;
      return state.copyWith(
        goals: [
          for (final goal in state.goals)
            if (changedGoals.contains(goal.id))
              goal.copyWith(meta: _touch(goal.meta))
            else
              goal,
        ],
        habitLinks: links,
        entries: entries,
      );
    });
  }

  Future<void> _change(WorkData Function(WorkData) change) async {
    try {
      await LocalStore.updateWork(change);
    } on GoalOperationException {
      work.reload();
      rethrow;
    }
    work.reload();
  }

  GoalProgressResult _progressFor(
    Goal goal,
    List<GoalHabitLink> links,
    DateTime asOf, {
    WorkData? state,
  }) {
    final snapshot = state ?? data;
    try {
      requireDay(asOf.dayKey, 'asOf');
      if (goal.source == GoalSource.habits) {
        final contributors = links
            .where(
              (link) =>
                  !link.isDeleted &&
                  link.goalId == goal.id &&
                  link.role == GoalHabitRole.contributor,
            )
            .toList();
        if (contributors.isEmpty) {
          return const GoalProgressResult(issue: GoalProgressIssue.needsHabit);
        }
        final allHabits = _allHabits();
        for (final link in contributors) {
          final habit = allHabits[link.habitId];
          if (habit == null) {
            return const GoalProgressResult(
              issue: GoalProgressIssue.missingHabit,
            );
          }
          if (link.sourceSignature !=
              GoalHabitLink.signatureFor(habit, metric: link.metric)) {
            return const GoalProgressResult(
              issue: GoalProgressIssue.sourceChanged,
            );
          }
        }
        return GoalProgressResult(
          progress: GoalProgress.compute(
            goal: goal,
            links: links,
            habits: allHabits,
            asOf: asOf,
          ),
        );
      }
      if (goal.source == GoalSource.work) {
        if (goal.taskIds.isEmpty && goal.projectIds.isEmpty) {
          return const GoalProgressResult(issue: GoalProgressIssue.needsWork);
        }
        final workProgress = WorkProgress.of(
          snapshot.tasks,
          taskIds: goal.taskIds,
          projectIds: goal.projectIds,
          excludedProjectIds: _excludedProjects(snapshot),
        );
        if (workProgress.fraction == null) {
          return const GoalProgressResult(issue: GoalProgressIssue.noWorkItems);
        }
        return GoalProgressResult(
          progress: GoalProgress.compute(
            goal: goal,
            asOf: asOf,
            workFraction: workProgress.fraction,
          ),
        );
      }
      return GoalProgressResult(
        progress: GoalProgress.compute(goal: goal, links: links, asOf: asOf),
      );
    } on FormatException {
      return const GoalProgressResult(issue: GoalProgressIssue.invalidData);
    } on ArgumentError catch (error) {
      return GoalProgressResult(issue: _argumentIssue(error));
    } on StateError catch (error) {
      return GoalProgressResult(issue: _stateIssue(error));
    }
  }

  Goal _achievedGoal(
    Goal goal,
    List<GoalHabitLink> links,
    WorkData state,
  ) {
    if (goal.source == GoalSource.manual &&
        goal.measurement == GoalMeasurement.completion) {
      return goal.copyWith(current: 1);
    }
    final progress = _progressFor(goal, links, _logicalNow, state: state);
    if (progress.progress == null || !progress.progress!.reachedTarget) {
      throw const GoalOperationException(GoalFailure.incomplete);
    }
    return goal;
  }

  void _requireSavableProgress(
    Goal goal,
    List<GoalHabitLink> activeLinks, {
    required WorkData state,
  }) {
    final result = _progressFor(goal, activeLinks, _logicalNow, state: state);
    switch (result.issue) {
      case null:
      case GoalProgressIssue.needsHabit:
      case GoalProgressIssue.needsWork:
      case GoalProgressIssue.noWorkItems:
        return;
      case GoalProgressIssue.sourceChanged:
        throw const GoalOperationException(GoalFailure.sourceChanged);
      case GoalProgressIssue.missingHabit:
      case GoalProgressIssue.incompatible:
      case GoalProgressIssue.invalidData:
        throw const GoalOperationException(GoalFailure.invalidLink);
    }
  }

  GoalHabitLink _prepareSingleLink(
    Goal goal,
    GoalHabitLink draft,
    GoalHabitLink? old,
  ) {
    if (draft.goalId != goal.id) {
      throw const GoalOperationException(GoalFailure.invalidLink);
    }
    if (old != null &&
        (old.goalId != draft.goalId || old.habitId != draft.habitId)) {
      throw const GoalOperationException(GoalFailure.invalidLink);
    }
    if (draft.role == GoalHabitRole.contributor &&
        goal.source != GoalSource.habits) {
      throw const GoalOperationException(GoalFailure.invalidLink);
    }
    if (habits.byId(draft.habitId) == null) {
      throw const GoalOperationException(GoalFailure.missing);
    }
    return draft.copyWith(meta: old == null ? draft.meta : _touch(old.meta));
  }

  List<GoalHabitLink> _preparedGoalLinks(
    WorkData state,
    Goal goal,
    List<GoalHabitLink> supplied,
    List<WorkEntry> entries,
  ) {
    final existing = state.habitLinks
        .where((link) => link.goalId == goal.id && !link.isDeleted)
        .toList();
    final used = <String>{};
    final result = <GoalHabitLink>[];
    for (final draft in supplied.where((link) => !link.isDeleted)) {
      if (draft.goalId != goal.id || !used.add(draft.habitId)) {
        throw const GoalOperationException(GoalFailure.invalidLink);
      }
      final stored = _find(state.habitLinks, draft.id);
      if (stored?.isDeleted == true) {
        throw const GoalOperationException(GoalFailure.missing);
      }
      if (stored != null &&
          (stored.goalId != draft.goalId || stored.habitId != draft.habitId)) {
        throw const GoalOperationException(GoalFailure.invalidLink);
      }
      if (stored != null && stored.meta.revision != draft.meta.revision) {
        throw const GoalOperationException(GoalFailure.stale);
      }
      final old = existing
          .where((link) => link.id == draft.id || link.habitId == draft.habitId)
          .firstOrNull;
      if (old != null && old.id != draft.id) {
        throw const GoalOperationException(GoalFailure.invalidLink);
      }
      final prepared = old == null || !_sameLinkBody(old, draft)
          ? _prepareSingleLink(goal, draft, old)
          : old;
      result.add(prepared);
      if (old == null || !_sameLinkBody(old, prepared)) {
        entries.add(
          _goalEvent(
            goal,
            WorkEntryKind.scopeChange,
            text: _linkEventText(prepared, old == null ? 'add' : 'update'),
          ),
        );
      }
    }
    for (final old in existing) {
      if (!used.contains(old.habitId)) {
        result.add(old.copyWith(meta: _touch(old.meta, deleted: true)));
        entries.add(
          _goalEvent(
            goal,
            WorkEntryKind.scopeChange,
            text: _linkEventText(old, 'remove'),
          ),
        );
      }
    }
    return result;
  }

  List<GoalHabitLink> _replaceLinksForGoal(
    List<GoalHabitLink> all,
    String goalId,
    List<GoalHabitLink> replacements,
  ) {
    final byId = {for (final link in replacements) link.id: link};
    return [
      for (final link in all)
        if (link.goalId == goalId && byId.containsKey(link.id))
          byId.remove(link.id)!
        else
          link,
      ...byId.values,
    ];
  }

  List<GoalHabitLink> _linkReplacement(
    List<GoalHabitLink> current,
    GoalHabitLink draft,
  ) => [
    for (final link in current)
      if (link.id != draft.id && link.habitId != draft.habitId) link,
    if (!draft.isDeleted) draft,
  ];

  Goal _requireCurrentGoal(
    WorkData state,
    Goal original, {
    bool allowArchived = false,
  }) {
    final current = _find(state.goals, original.id);
    if (current == null || current.isDeleted) {
      throw const GoalOperationException(GoalFailure.missing);
    }
    if (!allowArchived && current.isArchived) {
      throw const GoalOperationException(GoalFailure.archived);
    }
    if (current.meta.revision != original.meta.revision) {
      throw const GoalOperationException(GoalFailure.stale);
    }
    return current;
  }

  RecordMeta _saveMeta(Goal? old, RecordMeta draft, int? expected) {
    if (old == null) {
      if (expected != null) {
        throw const GoalOperationException(GoalFailure.missing);
      }
      return draft;
    }
    if (old.isDeleted) throw const GoalOperationException(GoalFailure.missing);
    if (expected != old.meta.revision) {
      throw const GoalOperationException(GoalFailure.stale);
    }
    return _touch(old.meta);
  }

  RecordMeta _newMeta() =>
      RecordMeta(id: const Uuid().v4(), createdAt: _now().toUtc());

  RecordMeta _touch(RecordMeta meta, {bool? archived, bool? deleted}) {
    final at = _now().toUtc();
    return meta.revise(
      at: at.isBefore(meta.updatedAt) ? meta.updatedAt : at,
      archived: archived,
      deleted: deleted,
    );
  }

  WorkEntry _goalEvent(
    Goal goal,
    WorkEntryKind kind, {
    String? date,
    String text = '',
    String? fromStatus,
    String? status,
    double? fromValue,
    double? value,
  }) => WorkEntry(
    meta: _newMeta(),
    entityKind: WorkEntityKind.goal,
    entityId: goal.id,
    kind: kind,
    text: text,
    date: date,
    previousStatus: fromStatus,
    status: status,
    previousValue: fromValue,
    value: value,
    measurementUnit: goal.measurement == GoalMeasurement.currency
        ? goal.currency
        : goal.unit,
    measurementKind: goal.measurement.name,
    measurementSource: goal.source.name,
    measurementBaseline: goal.baseline,
    measurementTarget: goal.target,
  );

  String _linkEventText(GoalHabitLink link, String action) => jsonEncode({
    'type': 'habitLink',
    'action': action,
    'goalId': link.goalId,
    'habitId': link.habitId,
    'role': link.role.name,
    'metric': link.metric.name,
    'linkId': link.id,
    'habitTitle': habits.byId(link.habitId)?.name ?? '',
    'startDate': link.startDate,
    'endDate': link.endDate,
    'unit': link.unit,
    'sourceSignature': link.sourceSignature,
  });

  Map<String, Habit> _allHabits() {
    final result = <String, Habit>{
      for (final habit in habits.habits) habit.id: habit,
      for (final habit in habits.archived) habit.id: habit,
    };
    for (final link in data.habitLinks) {
      final habit = habits.byId(link.habitId);
      if (habit != null) result[habit.id] = habit;
    }
    return result;
  }

  Set<String> _excludedProjects(WorkData state) => {
    for (final project in state.projects)
      if (project.isDeleted || project.status == WorkProjectStatus.cancelled)
        project.id,
  };

  DateTime get _logicalNow =>
      _now().subtract(Duration(hours: AppClock.cutoffHour));

  String get _todayKey => _logicalNow.dayKey;
}

T? _find<T extends StoredRecord>(Iterable<T> records, String? id) {
  if (id == null) return null;
  for (final record in records) {
    if (record.id == id) return record;
  }
  return null;
}

List<T> _put<T extends StoredRecord>(List<T> records, T record) => [
  for (final existing in records)
    if (existing.id == record.id) record else existing,
  if (!records.any((existing) => existing.id == record.id)) record,
];

int _nextOrder(Iterable<int> values) =>
    values.fold<int>(-1, (a, b) => a > b ? a : b) + 1;

int _goalSort(Goal a, Goal b) {
  final pinned = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
  if (pinned != 0) return pinned;
  final order = a.order.compareTo(b.order);
  return order != 0 ? order : a.id.compareTo(b.id);
}

int _linkSort(GoalHabitLink a, GoalHabitLink b) {
  final date = a.meta.createdAt.compareTo(b.meta.createdAt);
  return date != 0 ? date : a.id.compareTo(b.id);
}

bool _goalMeasurementConfigChanged(Goal a, Goal b) =>
    a.source != b.source ||
    a.measurement != b.measurement ||
    a.baseline != b.baseline ||
    a.target != b.target ||
    a.unit != b.unit ||
    a.currency != b.currency ||
    a.startDate != b.startDate ||
    a.endDate != b.endDate ||
    (b.source == GoalSource.work &&
        (!listEquals(a.taskIds, b.taskIds) ||
            !listEquals(a.projectIds, b.projectIds)));

bool _sameMeasurementUnit(Goal a, Goal b) =>
    a.measurement == b.measurement &&
    a.source == b.source &&
    a.unit == b.unit &&
    a.currency == b.currency;

bool _goalScopeHistoryChanged(Goal a, Goal b) =>
    _goalMeasurementConfigChanged(a, b) ||
    a.scope != b.scope ||
    a.areaId != b.areaId ||
    a.projectId != b.projectId ||
    !listEquals(a.taskIds, b.taskIds) ||
    !listEquals(a.projectIds, b.projectIds);

bool _sameLinkBody(GoalHabitLink a, GoalHabitLink b) =>
    a.goalId == b.goalId &&
    a.habitId == b.habitId &&
    a.role == b.role &&
    a.metric == b.metric &&
    a.startDate == b.startDate &&
    a.endDate == b.endDate &&
    a.unit == b.unit &&
    a.sourceSignature == b.sourceSignature &&
    a.isDeleted == b.isDeleted;

bool _contributorLinksChanged(
  List<GoalHabitLink> before,
  List<GoalHabitLink> after,
) {
  final oldLinks = {
    for (final link in before)
      if (!link.isDeleted && link.role == GoalHabitRole.contributor)
        link.habitId: link,
  };
  final newLinks = {
    for (final link in after)
      if (!link.isDeleted && link.role == GoalHabitRole.contributor)
        link.habitId: link,
  };
  if (!setEquals(oldLinks.keys.toSet(), newLinks.keys.toSet())) return true;
  for (final habitId in oldLinks.keys) {
    if (!_sameLinkBody(oldLinks[habitId]!, newLinks[habitId]!)) return true;
  }
  return false;
}

GoalProgressIssue _argumentIssue(ArgumentError error) {
  final message = '${error.message}';
  if (message.contains('Different habit metrics') ||
      message.contains('measurement') ||
      message.contains('Consistency') ||
      message.contains('Accumulated activity') ||
      message.contains('compatible scheduling') ||
      message.contains('Quantity requires') ||
      message.contains('Duration requires')) {
    return GoalProgressIssue.incompatible;
  }
  return GoalProgressIssue.invalidData;
}

GoalProgressIssue _stateIssue(StateError error) {
  final message = error.message;
  if (message.contains('Missing contributing habit')) {
    return GoalProgressIssue.missingHabit;
  }
  if (message.contains('settings changed') ||
      message.contains('unit does not match')) {
    return GoalProgressIssue.sourceChanged;
  }
  return GoalProgressIssue.invalidData;
}
