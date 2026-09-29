import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/routing/app_navigator.dart';
import 'package:streak/features/focus/data/focus_session.dart';
import 'package:streak/features/focus/pages/focus_page.dart';
import 'package:streak/features/focus/pages/focus_setup_page.dart';
import 'package:streak/features/focus/state/focus_controller.dart';
import 'package:streak/features/settings/state/settings_controller.dart';

class FocusPill extends StatelessWidget {
  const FocusPill({super.key, this.compact = false, this.dense = false});

  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusController>();
    final active = focus.isActive;
    if (!context.watch<SettingsController>().focusEnabled && !active) {
      return const SizedBox.shrink();
    }
    final accent = context.colors.primary;

    void open() {
      if (active && AppNavigator.isShowing(FocusPage.routeName)) return;
      active
          ? AppNavigator.push(
              const FocusPage(),
              fade: true,
              name: FocusPage.routeName,
            )
          : AppNavigator.push(const FocusSetupPage(), fullscreenDialog: true);
    }

    if (compact && !active) {
      return IconButton(
        tooltip: context.l10n.focus,
        onPressed: open,
        icon: Icon(
          LucideIcons.timer,
          size: 22,
          color: context.colors.onSurface,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: open,
        style: TextButton.styleFrom(
          backgroundColor: active
              ? accent.withValues(alpha: 0.16)
              : context.colors.surfaceContainerHighest,
          foregroundColor: active ? accent : context.tokens.muted,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 9 : 12,
            vertical: 8,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: active
              ? BorderSide(color: accent.withValues(alpha: 0.6))
              : null,
        ),
        icon: Icon(
          LucideIcons.timer,
          size: dense ? 15 : 16,
          color: active ? accent : context.tokens.muted,
        ),
        label: Text(
          active ? formatDuration(focus.displaySeconds) : context.l10n.focus,
          style: TextStyle(
            fontSize: dense ? 12.5 : 13.5,
            fontWeight: FontWeight.w700,
            color: active ? accent : context.tokens.muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
