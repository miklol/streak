import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart' show HiveError;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_theme.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/extensions/date_extensions.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/core/utils/app_snackbar.dart';
import 'package:streak/core/utils/cover_storage.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/delete_sheet.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/data/focus_target.dart';
import 'package:streak/features/focus/state/focus_audio.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/focus/state/work_focus_actions.dart';
import 'package:streak/core/widgets/celebration_overlay.dart';
import 'package:streak/features/focus/widgets/focus_backgrounds.dart';
import 'package:streak/features/focus/widgets/focus_end_dialog.dart';
import 'package:streak/features/focus/widgets/focus_task_lists.dart';
import 'package:streak/features/focus/widgets/focus_video_scene.dart';
import 'package:streak/features/focus/widgets/music_sheet.dart';
import 'package:streak/features/focus/widgets/timer_clocks.dart';
import 'package:streak/features/habits/data/habit.dart';
import 'package:streak/features/habits/state/habits_controller.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';
import 'package:streak/core/widgets/app_confirm_dialog.dart';
import 'package:streak/services/notification_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class FocusPage extends StatefulWidget implements FullWidthPage {
  const FocusPage({
    super.key,
    this.startHabitId,
    this.startTarget,
    this.startMinutes,
    this.breakMinutes,
  });

  final String? startHabitId;
  final FocusTarget? startTarget;
  final int? startMinutes;
  final int? breakMinutes;

  static const routeName = 'focus';

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  bool _leaving = false;
  final _confetti = ValueNotifier(0);
  late final FocusController _focus = context.read<FocusController>();

  Timer? _lead;
  int _leadValue = 0;
  bool _immersive = false;
  bool _awakeRequested = false;

  @override
  void initState() {
    super.initState();
    _focus.completedTick.addListener(_celebrate);
    if (context.read<SettingsController>().focusKeepAwake) {
      _awakeRequested = true;
      unawaited(_setKeepAwake(true));
    }

    if (widget.startMinutes != null) {
      _leadValue = 3;
      _begin();
    }
  }

  Future<void> _setKeepAwake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } on PlatformException catch (error) {
      debugPrint('Focus keep-awake is unavailable: $error');
      if (enabled && mounted) {
        AppSnackbar.warning(context, context.l10n.work_focus_keep_awake_error);
      }
    } on MissingPluginException catch (error) {
      debugPrint('Focus keep-awake is unavailable: $error');
      if (enabled && mounted) {
        AppSnackbar.warning(context, context.l10n.work_focus_keep_awake_error);
      }
    }
  }

  Future<void> _begin() async {
    if (_focus.isActive) {
      setState(() => _leadValue = 0);
      return;
    }
    await NotificationService().requestNotifications();
    if (!mounted) return;
    _runLead(() {
      if (_focus.isActive) return;
      var target = widget.startTarget;
      if (target?.kind == FocusTargetKind.workTask) {
        final work = context.read<WorkController>();
        work.reload();
        if (!workFocusTargetAvailable(context, target!.id)) {
          AppNavigator.pop();
          return;
        }
        target = FocusTarget.fromWork(work.data, target.id);
      }
      try {
        _focus.start(
          habitId: widget.startHabitId ?? '',
          target: target,
          targetMinutes: widget.startMinutes!,
          breakMinutes: widget.breakMinutes ?? 0,
        );
      } on ArgumentError {
        AppSnackbar.warning(context, context.l10n.work_action_failed);
        AppNavigator.pop();
        return;
      } on StateError {
        AppSnackbar.warning(context, context.l10n.work_action_failed);
        AppNavigator.pop();
        return;
      }
      _scheduleEndAlarm();
      unawaited(_startSavedTrack());
    });
  }

  Future<void> _startSavedTrack() async {
    if (FocusAudio.playing.value) return;
    final settings = context.read<SettingsController>();
    final saved = settings.focusTrack;
    if (saved.isEmpty) return;

    final tracks = focusTracksOf(context, settings);
    final index = tracks.indexWhere((track) => track.id == saved);
    if (index == -1) return;
    try {
      await FocusAudio.playQueue(
        tracks,
        shuffle: settings.focusShuffle,
        from: tracks[index],
      );
    } catch (e) {
      debugPrint('Could not start the saved track: $e');
    }
  }

  void _runLead(VoidCallback then) {
    _lead?.cancel();
    setState(() => _leadValue = 3);
    _lead = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _leadValue--);
      if (_leadValue > 0) return;
      timer.cancel();
      then();
    });
  }

  void _scheduleEndAlarm() {
    if (_focus.isFlow) return;
    NotificationService().scheduleFocusEnd(
      title: context.l10n.focus_done_title,
      body: context.l10n.focus_notif_body,
      after: Duration(seconds: _focus.remainingSeconds),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_awakeRequested) unawaited(_setKeepAwake(false));
    _lead?.cancel();
    _confetti.dispose();
    _focus.completedTick.removeListener(_celebrate);
    super.dispose();
  }

  void _toggleImmersive() {
    setState(() => _immersive = !_immersive);
    SystemChrome.setEnabledSystemUIMode(
      _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _celebrate() {
    if (!mounted) return;
    FocusAudio.chime();
    HapticFeedback.heavyImpact();
    _confetti.value++;
    if (_focus.isPomodoro && _focus.isActive) _scheduleEndAlarm();
  }

  Future<void> _confirmStop() async {
    final focus = context.read<FocusController>();
    final habits = context.read<HabitsController>();
    final workTarget = focus.target.kind == FocusTargetKind.workTask;
    final habit = workTarget || focus.habitId.isEmpty
        ? null
        : habits.byId(focus.habitId);
    final reached = focus.reachedTarget || focus.isFlow;
    final checked =
        habit?.completions[DateTime.now().dayKey]?.steps ?? const <String>{};
    final pending = habit == null
        ? focus.pendingTasks
        : habit.substeps.where((step) => !checked.contains(step.id)).length;

    final lines = <String>[
      if (focus.isFlow)
        context.l10n.focus_end_flow(formatHoursShort(focus.elapsedSeconds))
      else if (reached)
        workTarget
            ? context.l10n.focus_target_reached
            : context.l10n.focus_end_reached
      else
        context.l10n.focus_end_short(formatHoursShort(focus.remainingSeconds)),
      if (!workTarget && pending > 0) context.l10n.focus_end_tasks(pending),
    ];

    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => FocusEndDialog(
        reached: reached,
        lines: lines,
        accent: habit?.color ?? Theme.of(dialog).colorScheme.primary,
        allowComplete: !workTarget,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _leaving = true);
    final habitId = focus.habitId;
    final completed = reached || result == 'done';
    FocusSession? session;
    final stopError = workTarget
        ? context.l10n.focus_work_storage_error
        : context.l10n.work_action_failed;
    try {
      session = await focus.stop(completed: completed);
    } on ArgumentError {
      if (mounted) {
        setState(() => _leaving = false);
        AppSnackbar.warning(context, stopError);
      }
      return;
    } on StateError {
      if (mounted) {
        setState(() => _leaving = false);
        AppSnackbar.warning(context, stopError);
      }
      return;
    } on FileSystemException {
      if (mounted) {
        setState(() => _leaving = false);
        AppSnackbar.warning(context, stopError);
      }
      return;
    } on HiveError {
      if (mounted) {
        setState(() => _leaving = false);
        AppSnackbar.warning(context, stopError);
      }
      return;
    } on PlatformException {
      if (mounted) {
        setState(() => _leaving = false);
        AppSnackbar.warning(context, stopError);
      }
      return;
    }
    await FocusAudio.stop();
    await NotificationService().cancelFocusEnd();
    if (!mounted) return;

    if (session != null) {
      if (session.target.kind == FocusTargetKind.workTask) {
        final finish = await _showWorkFinishDialog(context, session);
        if (!mounted) return;
        AppSnackbar.success(
          context,
          finish?.markDone == true
              ? context.l10n.work_focus_saved_completed
              : context.l10n.work_focus_saved_no_completion,
        );
        AppNavigator.pop();
        return;
      }
      final target = habitId.isEmpty ? null : habits.byId(habitId);
      if (target != null && target.isTimeAmount) {
        await habits.addProgress(
          target.id,
          DateTime.now(),
          session.seconds / 60,
        );
      } else if (completed &&
          target != null &&
          target.kind == HabitKind.positive &&
          !target.isCompletedOn(DateTime.now())) {
        await habits.toggle(target.id, DateTime.now(), fromFocus: true);
      }
      if (!mounted) return;
      AppSnackbar.success(
        context,
        context.l10n.focus_saved(formatHoursShort(session.seconds)),
      );
    }
    AppNavigator.pop();
  }

  Future<void> _resetPhase() async {
    if (_focus.target.kind != FocusTargetKind.workTask ||
        _focus.isBreak ||
        _focus.elapsedSeconds == 0) {
      _runLead(() {
        _focus.reset();
        _scheduleEndAlarm();
      });
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.work_focus_restart,
      message: context.l10n.work_focus_restart_body,
      confirmLabel: context.l10n.work_focus_save_restart,
      icon: LucideIcons.rotateCcw,
      danger: false,
    );
    if (confirmed != true || !mounted) return;
    final targetId = _focus.target.id;
    final minutes = _focus.focusMinutes;
    final breaks = _focus.breakMinutes;
    setState(() => _leaving = true);
    await runWorkAction(context, () async {
      await _focus.stop(completed: _focus.reachedTarget);
      if (!mounted) return;
      final work = context.read<WorkController>();
      work.reload();
      if (!workFocusTargetAvailable(context, targetId)) return;
      _focus.start(
        habitId: '',
        target: FocusTarget.fromWork(work.data, targetId),
        targetMinutes: minutes,
        breakMinutes: breaks,
      );
      await _focus.ready;
    });
    if (mounted) setState(() => _leaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final focus = context.watch<FocusController>();
    final habits = context.watch<HabitsController>();
    final leading = _leadValue > 0;
    final starting = leading && !focus.isActive;
    final activeTarget = starting
        ? (widget.startTarget ??
              ((widget.startHabitId ?? '').isEmpty
                  ? FocusTarget.free()
                  : FocusTarget.habit(widget.startHabitId!)))
        : focus.target;
    final habitId = activeTarget.kind == FocusTargetKind.habit
        ? activeTarget.id
        : '';
    final habit = habitId.isEmpty ? null : habits.byId(habitId);
    final leadMinutes = starting
        ? (widget.startMinutes ?? focus.targetMinutes)
        : focus.targetMinutes;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    if (!focus.isActive && !_leaving && _leadValue == 0) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppNavigator.pop();
      });
    }

    final style =
        ClockStyle.values[settings.focusClockStyle.clamp(
          0,
          ClockStyle.values.length - 1,
        )];
    final label = focus.isBreak
        ? context.l10n.focus_break
        : activeTarget.kind == FocusTargetKind.workTask
        ? activeTarget.title
        : (habit?.name ?? context.l10n.focus);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBars(Brightness.dark),
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            FocusBackground(
              scene: settings.focusScene,
              imagePath: settings.focusImage,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final landscape =
                        constraints.maxWidth > constraints.maxHeight;
                    final typing = inset > 0;

                    final listHeight = typing
                        ? (constraints.maxHeight * 0.32).clamp(110.0, 240.0)
                        : 156.0;
                    final tasks = activeTarget.kind == FocusTargetKind.workTask
                        ? FocusWorkTaskList(
                            target: activeTarget,
                            maxHeight: listHeight,
                          )
                        : habit == null
                        ? FocusFreeTaskList(focus: focus, maxHeight: listHeight)
                        : FocusTaskList(habit: habit, maxHeight: listHeight);

                    final header = AnimatedBuilder(
                      animation: focus,
                      builder: (context, _) => _TopBar(
                        immersive: _immersive,
                        onImmersive: _toggleImmersive,
                        title: label,
                        target: leadMinutes <= 0
                            ? context.l10n.focus_flowtime
                            : focus.isPomodoro && !leading
                            ? '${context.l10n.minutes_short('${focus.targetMinutes}')}  ·  ${context.l10n.focus_round(focus.round)}'
                            : context.l10n.minutes_short('$leadMinutes'),
                      ),
                    );

                    final clock = AnimatedBuilder(
                      animation: focus,
                      builder: (context, _) => FocusClock(
                        style: style,
                        seconds: leading
                            ? (leadMinutes <= 0 ? 0 : leadMinutes * 60)
                            : focus.displaySeconds,
                        progress: leading ? 0 : focus.progress,
                        color: habit?.color ?? context.colors.primary,
                        label: label,
                        size: landscape
                            ? (constraints.maxHeight * 0.62).clamp(140.0, 300.0)
                            : (constraints.maxWidth * 0.66).clamp(160.0, 320.0),
                      ),
                    );

                    final controls = AnimatedBuilder(
                      animation: focus,
                      builder: (context, _) => _Controls(
                        running: focus.isRunning,
                        onReset: _resetPhase,
                        onToggle: () {
                          if (focus.isRunning) {
                            focus.pause();
                            NotificationService().cancelFocusEnd();
                          } else {
                            focus.resume();
                            _scheduleEndAlarm();
                          }
                        },
                        onStop: _confirmStop,
                      ),
                    );

                    if (landscape) {
                      return Column(
                        children: [
                          header,
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      8,
                                      12,
                                      18,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: clock,
                                          ),
                                        ),
                                        if (!typing) ...[
                                          const SizedBox(height: 24),
                                          controls,
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  key: const ValueKey('focus-tasks'),
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      8,
                                      20,
                                      20,
                                    ),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 420,
                                        ),
                                        child: tasks,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: inset),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        header,
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: clock,
                            ),
                          ),
                        ),
                        if (!typing) ...[
                          KeyedSubtree(
                            key: const ValueKey('focus-controls'),
                            child: controls,
                          ),
                          const SizedBox(height: 22),
                        ],
                        Padding(
                          key: const ValueKey('focus-tasks'),
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                          child: tasks,
                        ),
                        SizedBox(height: inset),
                      ],
                    );
                  },
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _confetti,
                  builder: (context, trigger, _) => IgnorePointer(
                    child: CelebrationOverlay(trigger: trigger),
                  ),
                ),
              ),
            ),
            if (_leadValue > 0)
              Positioned.fill(
                child: _LeadIn(value: _leadValue),
              ),
            if (focus.lastPersistenceError != null)
              PositionedDirectional(
                start: 16,
                end: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: Material(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(context.l10n.focus_work_storage_error),
                          TextButton(
                            onPressed: () =>
                                runWorkAction(context, focus.retryPersistence),
                            child: Text(context.l10n.work_focus_retry_save),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkFinishResult {
  const _WorkFinishResult({required this.note, required this.markDone});

  final String note;
  final bool markDone;
}

Future<_WorkFinishResult?> _showWorkFinishDialog(
  BuildContext context,
  FocusSession session,
) => showDialog<_WorkFinishResult>(
  context: context,
  builder: (_) => _WorkFinishDialog(session: session),
);

class _WorkFinishDialog extends StatefulWidget {
  const _WorkFinishDialog({required this.session});

  final FocusSession session;

  @override
  State<_WorkFinishDialog> createState() => _WorkFinishDialogState();
}

class _WorkFinishDialogState extends State<_WorkFinishDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.session.note,
  );
  bool _markDone = false;
  bool _saving = false;
  String? _error;
  late FocusSession _session = widget.session;

  Future<void> _save() async {
    if (_saving) return;
    final work = context.read<WorkController>();
    final remaining = _markDone ? work.openSubtaskCount(_session.target.id) : 0;
    if (remaining > 0) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: context.l10n.work_complete_task,
        message: context.l10n.work_complete_task_confirm(remaining),
        confirmLabel: context.l10n.work_complete_task,
        icon: LucideIcons.circleCheck,
        danger: false,
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await runWorkAction(
      context,
      () async {
        final focus = context.read<FocusController>();
        if (_session.note != _note.text.trim()) {
          await focus.updateWorkNote(_session, _note.text.trim());
          _session = focus.sessions.firstWhere(
            (session) => session.id == _session.id,
          );
        }
        if (_markDone) {
          await work.setTaskStatus(
            _session.target.id,
            WorkTaskStatus.done,
            completeSubtasks: remaining > 0,
          );
        }
        if (mounted) {
          Navigator.of(context).pop(
            _WorkFinishResult(note: _note.text.trim(), markDone: _markDone),
          );
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _error = workErrorMessage(context, error);
        });
      },
    );
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.work_focus_note_label),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _note,
            enabled: !_saving,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.l10n.work_focus_note_hint,
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _markDone,
            onChanged: _saving
                ? null
                : (value) => setState(() => _markDone = value ?? false),
            title: Text(context.l10n.work_focus_mark_done),
          ),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(context.l10n.save),
      ),
    ],
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.target,
    required this.immersive,
    required this.onImmersive,
  });

  final String title;
  final String target;
  final bool immersive;
  final VoidCallback onImmersive;

  Future<void> _pickStyle(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final labels = [
      context.l10n.focus_style_digital,
      context.l10n.focus_style_flip,
      context.l10n.focus_style_dots,
    ];
    await _sheet(
      context,
      title: context.l10n.focus_style,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(labels[i]),
              trailing: settings.focusClockStyle == i
                  ? Icon(LucideIcons.check, color: context.colors.primary)
                  : null,
              onTap: () {
                settings.setFocusClockStyle(i);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickScene(BuildContext context) async {
    final settings = context.read<SettingsController>();

    Future<void> pickImage() async {
      if (settings.focusImages.length >= 10) {
        AppSnackbar.warning(context, context.l10n.focus_images_limit);
        return;
      }
      final dest = await CoverStorage.store(folder: 'focus');
      if (dest == null) return;
      await settings.addFocusImage(dest);
      await settings.setFocusImage(dest);
      await settings.setFocusScene(kCustomScene);
    }

    await _sheet(
      context,
      title: context.l10n.app_background,
      child: Consumer<SettingsController>(
        builder: (sheetContext, s, __) => LayoutBuilder(
          builder: (_, box) {
            const columns = 4;
            const gap = 10.0;
            final tile = ((box.maxWidth - gap * (columns - 1)) / columns)
                .floorToDouble();
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < focusSceneCount; i++)
                  if (!s.isSceneHidden(i) && (i == 0 || !hasVideoScenes))
                    SizedBox(
                      width: tile,
                      child: FocusScenePreview(
                        scene: i,
                        imagePath: '',
                        selected: s.focusScene == i && s.focusImage.isEmpty,
                        onTap: () {
                          s.setFocusScene(i);
                          s.setFocusImage('');
                        },
                        onLongPress: i == 0
                            ? null
                            : () async {
                                if (await showDeleteSheet(sheetContext)) {
                                  await s.hideScene(i);
                                }
                              },
                      ),
                    ),
                if (hasVideoScenes)
                  for (var i = 0; i < focusVideoScenes.length; i++)
                    if (!s.isSceneHidden(kFirstVideoScene + i))
                      SizedBox(
                        width: tile,
                        child: FocusScenePreview(
                          scene: kFirstVideoScene + i,
                          imagePath: '',
                          selected:
                              s.focusScene == kFirstVideoScene + i &&
                              s.focusImage.isEmpty,
                          onTap: () {
                            s.setFocusScene(kFirstVideoScene + i);
                            s.setFocusImage('');
                          },
                          onLongPress: () async {
                            if (await showDeleteSheet(sheetContext)) {
                              await s.hideScene(kFirstVideoScene + i);
                            }
                          },
                        ),
                      ),
                for (final path in s.focusImages)
                  SizedBox(
                    width: tile,
                    child: AspectRatio(
                      aspectRatio: 0.78,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Semantics(
                              button: true,
                              label: sheetContext.l10n.app_background,
                              child: GestureDetector(
                                onTap: () {
                                  s.setFocusImage(path);
                                  s.setFocusScene(kCustomScene);
                                },
                                onLongPress: () async {
                                  if (await showDeleteSheet(sheetContext)) {
                                    await s.removeFocusImage(path);
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.all(
                                    s.focusImage == path ? 2.5 : 0,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: s.focusImage == path
                                        ? Border.all(
                                            color: sheetContext.colors.primary,
                                            width: 2.5,
                                          )
                                        : null,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      s.focusImage == path ? 12 : 14,
                                    ),
                                    child: File(path).existsSync()
                                        ? Image.file(
                                            File(path),
                                            fit: BoxFit.cover,
                                          )
                                        : ColoredBox(
                                            color: sheetContext
                                                .colors
                                                .surfaceContainerHighest,
                                            child: const SizedBox.expand(),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SizedBox(
                  width: tile,
                  child: AspectRatio(
                    aspectRatio: 0.78,
                    child: Semantics(
                      button: true,
                      label: sheetContext.l10n.add_image,
                      child: GestureDetector(
                        onTap: pickImage,
                        child: Container(
                          decoration: BoxDecoration(
                            color: sheetContext.colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            LucideIcons.imagePlus,
                            size: 20,
                            color: sheetContext.tokens.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (s.hiddenScenes.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: s.restoreScenes,
                        child: Text(sheetContext.l10n.restore),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Future<void> _sheet(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: phoneWidth,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: sheetTitleStyle(sheet)),
              const SizedBox(height: 16),
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
            onPressed: () => AppNavigator.pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  target,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          _TopIcon(
            icon: immersive ? LucideIcons.minimize2 : LucideIcons.maximize2,
            onTap: onImmersive,
          ),
          _TopIcon(
            icon: LucideIcons.music,
            onTap: () => showMusicSheet(context),
          ),
          _TopIcon(
            icon: LucideIcons.layoutPanelTop,
            onTap: () => _pickStyle(context),
          ),
          _TopIcon(
            icon: LucideIcons.image,
            onTap: () => _pickScene(context),
          ),
        ],
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: 19, color: Colors.white.withValues(alpha: 0.85)),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.running,
    required this.onReset,
    required this.onToggle,
    required this.onStop,
  });

  final bool running;
  final VoidCallback onReset;
  final VoidCallback onToggle;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 18,
      runSpacing: 12,
      children: [
        _RoundButton(
          icon: LucideIcons.rotateCcw,
          label: context.l10n.work_focus_restart,
          onTap: () {
            HapticFeedback.selectionClick();
            onReset();
          },
        ),
        FilledButton.icon(
          onPressed: () {
            HapticFeedback.mediumImpact();
            onToggle();
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.65),
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 50),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          ),
          icon: Icon(running ? LucideIcons.pause : LucideIcons.play, size: 18),
          label: Text(
            running ? context.l10n.focus_pause : context.l10n.focus_resume,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        _RoundButton(
          icon: LucideIcons.square,
          label: context.l10n.focus_end,
          onTap: onStop,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.65),
        minimumSize: const Size(50, 50),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
      ),
    );
  }
}

class _LeadIn extends StatelessWidget {
  const _LeadIn({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(value),
          tween: Tween(begin: 0.5, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
          ),
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: 128,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -6,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
