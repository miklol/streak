import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/widgets/photo_deck.dart';
import 'package:streak/features/settings/state/settings_controller.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/todos/widgets/todo_labels.dart';

class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onEdit,
    required this.overdue,
    this.corners,
    this.onMoveToWork,
    this.busy = false,
  });

  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final bool overdue;
  final BorderRadius? corners;
  final VoidCallback? onMoveToWork;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final accent = todoPriorityColor(context, todo.priority);
    final due = todo.due;

    return GestureDetector(
      onTap: busy ? null : onEdit,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest
              .withValues(alpha: todo.done ? 0.3 : 0.55),
          borderRadius: corners ?? BorderRadius.circular(18),
          border: todo.priority == TodoPriority.none || todo.done
              ? null
              : Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: todo.done ? muted : scheme.onSurface,
                      decoration: todo.done ? TextDecoration.lineThrough : null,
                      decorationColor: muted,
                    ),
                  ),
                  if (todo.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      todo.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: muted,
                      ),
                    ),
                  ],
                  if (!todo.done &&
                      (due != null ||
                          todo.priority != TodoPriority.none)) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (due != null)
                          _MetaLabel(
                            icon: todo.time == null
                                ? LucideIcons.calendar
                                : LucideIcons.clock,
                            label: todoDueLabel(context, todo),
                            color: overdue ? context.tokens.danger : muted,
                          ),
                        if (todo.priority != TodoPriority.none)
                          _MetaLabel(
                            icon: LucideIcons.flag,
                            label:
                                todoPriorityLabels(context)[todo.priority.index],
                            color: accent,
                          ),
                      ],
                    ),
                  ],
                  if (todo.photos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    PhotoDeck(
                      shots: todoPhotoShots(todo),
                      size: 58,
                      swipe: false,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            _CheckButton(todo: todo, onToggle: busy ? null : onToggle),
            if (onMoveToWork != null)
              PopupMenuButton<String>(
                tooltip: context.l10n.work_actions_for(todo.title),
                enabled: !busy,
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'work') onMoveToWork!();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(context.l10n.edit)),
                  PopupMenuItem(value: 'work', child: Text(context.l10n.work_move_todo)),
                ],
                icon: busy
                    ? const SizedBox.square(dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.ellipsisVertical, size: 19),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Tooltip(
            message: label,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.todo, required this.onToggle});

  final Todo todo;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final circle = context.watch<SettingsController>().isCircleCheck;
    final radius = BorderRadius.circular(circle ? 13 : 8);
    final label = todo.done ? context.l10n.a11y_mark_not_done(todo.title)
        : context.l10n.a11y_mark_done(todo.title);

    return Tooltip(message: label, excludeFromSemantics: true,
      child: MergeSemantics(child: Semantics(
      container: true,
      label: label,
      checked: todo.done,
      child: IconButton(
        onPressed: onToggle == null ? null : () {
          HapticFeedback.selectionClick();
          onToggle!();
        },
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: const EdgeInsets.all(11),
        icon: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: todo.done ? scheme.primary : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: todo.done
                  ? scheme.primary
                  : context.tokens.muted.withValues(alpha: 0.5),
              width: 1.6,
            ),
          ),
          child: todo.done
              ? Icon(LucideIcons.check, size: 15, color: scheme.onPrimary)
              : null,
        ),
      ),
    )));
  }
}
