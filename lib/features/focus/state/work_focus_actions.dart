import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/app_snackbar.dart';
import 'package:streak/core/widgets/app_confirm_dialog.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/focus/pages/focus_page.dart';
import 'package:streak/features/focus/pages/focus_setup_page.dart';
import 'package:streak/features/focus/state/focus_actions.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

Future<void> openWorkFocus(
  BuildContext context, {
  required String taskId,
}) async {
  if (!context.read<SettingsController>().focusEnabled) {
    AppSnackbar.warning(context, context.l10n.work_action_failed);
    return;
  }
  final focus = context.read<FocusController>();
  if (focus.isActive &&
      focus.target.kind == FocusTargetKind.workTask &&
      focus.target.id == taskId) {
    _openFocusPage();
    return;
  }
  final work = context.read<WorkController>();
  work.reload();
  final task = work.taskById(taskId);
  if (!workFocusTargetAvailable(context, taskId)) return;

  if (focus.isActive) {
    final choice = await _resolveActiveFocus(context, task!.title);
    if (!context.mounted || choice == null) return;
    if (choice == _ActiveChoice.resume) {
      _openFocusPage();
      return;
    }
    if (choice == _ActiveChoice.finish) {
      final saved = await runWorkAction(context, () async {
        final session = await focus.stop(
          completed: focus.reachedTarget || focus.isFlow,
        );
        if (session != null) await applySavedFocusSession(session);
      });
      if (!saved) return;
    }
  }
  if (!context.mounted) return;

  work.reload();
  if (!workFocusTargetAvailable(context, taskId)) return;
  final current = work.taskById(taskId)!;
  if (current.status == WorkTaskStatus.done ||
      current.status == WorkTaskStatus.blocked) {
    final ok = await showAppConfirmDialog(
      context,
      title: current.status == WorkTaskStatus.done
          ? context.l10n.work_focus_open_done_title
          : context.l10n.work_focus_open_blocked_title,
      message: current.status == WorkTaskStatus.done
          ? context.l10n.work_focus_open_done_body
          : context.l10n.work_focus_open_blocked_body,
      confirmLabel: context.l10n.focus_start,
      icon: LucideIcons.timer,
      danger: false,
    );
    if (ok != true || !context.mounted) return;
  }
  AppNavigator.push(
    FocusSetupPage(workTaskId: current.id),
    fullscreenDialog: true,
  );
}

bool workFocusTargetAvailable(BuildContext context, String taskId) {
  final work = context.read<WorkController>();
  final task = work.taskById(taskId);
  if (task == null) {
    AppSnackbar.warning(context, context.l10n.work_error_missing);
    return false;
  }
  if (task.isDeleted || work.isTaskArchived(task)) {
    AppSnackbar.warning(context, context.l10n.work_error_archived_parent);
    return false;
  }
  if (task.status == WorkTaskStatus.cancelled) {
    AppSnackbar.warning(context, context.l10n.work_error_closed_parent);
    return false;
  }
  final parent = task.parentTaskId == null
      ? null
      : work.taskById(task.parentTaskId!);
  if (parent != null &&
      (parent.isDeleted ||
          work.isTaskArchived(parent) ||
          parent.status == WorkTaskStatus.cancelled ||
          parent.status == WorkTaskStatus.done)) {
    AppSnackbar.warning(context, context.l10n.work_error_closed_parent);
    return false;
  }
  final project = task.projectId == null
      ? null
      : work.projectById(task.projectId!);
  if (project != null &&
      (project.isDeleted ||
          work.isProjectArchived(project) ||
          project.status == WorkProjectStatus.cancelled ||
          project.status == WorkProjectStatus.done)) {
    AppSnackbar.warning(context, context.l10n.work_error_closed_parent);
    return false;
  }
  return true;
}

void _openFocusPage() {
  if (AppNavigator.isShowing(FocusPage.routeName)) return;
  AppNavigator.push(const FocusPage(), fade: true, name: FocusPage.routeName);
}

enum _ActiveChoice { resume, finish }

Future<_ActiveChoice?> _resolveActiveFocus(BuildContext context, String task) =>
    showDialog<_ActiveChoice>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.work_focus_active_title),
        content: Text(context.l10n.work_focus_active_body(task)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(_ActiveChoice.resume),
            child: Text(context.l10n.work_focus_resume_active),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(context.l10n.work_focus_cancel_active),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(_ActiveChoice.finish),
            child: Text(context.l10n.work_focus_finish_and_switch),
          ),
        ],
      ),
    );
