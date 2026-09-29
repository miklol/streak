import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/express/express_type.dart';
import 'package:streak/core/express/express_shapes.dart';

class ExpressNavItem {
  const ExpressNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class ExpressNavBar extends StatelessWidget {
  const ExpressNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<ExpressNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: dark ? 0.22 : 0.16),
          dark ? scheme.surface : Colors.white,
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.42 : 0.14),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              flex: i == index ? 2 : 1,
              child: _NavPill(
                item: items[i],
                selected: i == index,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ExpressNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final tint = selected ? scheme.onPrimary : scheme.onSurface;

    return MergeSemantics(child: Tooltip(
      message: item.label,
      excludeFromSemantics: true,
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          style: TextButton.styleFrom(
            foregroundColor: tint,
            backgroundColor: selected ? scheme.primary : Colors.transparent,
            minimumSize: const Size(44, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          child: Semantics(
            label: item.label,
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 21),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Flexible(child: Text(item.label, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ExpressType.headline.at(14, weight: 800, color: tint))),
                ],
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class ExpressNavRail extends StatelessWidget {
  const ExpressNavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    required this.brand,
  });

  static const width = 224.0;

  final List<ExpressNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget brand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              brand,
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _RailPill(
                            item: items[i],
                            selected: i == index,
                            onTap: () => onSelect(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailPill extends StatefulWidget {
  const _RailPill({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ExpressNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailPill> createState() => _RailPillState();
}

class _RailPillState extends State<_RailPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final scheme = context.colors;
    final tint = selected ? scheme.onPrimary : context.tokens.muted;

    return MergeSemantics(child: Tooltip(
      message: item.label,
      excludeFromSemantics: true,
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          onHover: (value) => setState(() => _hover = value),
          style: TextButton.styleFrom(
            foregroundColor: tint,
            backgroundColor: selected ? scheme.primary
                : scheme.primary.withValues(alpha: _hover ? 0.16 : 0.06),
            minimumSize: const Size(40, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(selected ? 24 : 14)),
          ),
          child: Semantics(
            label: item.label,
            excludeSemantics: true,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero : const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: 30,
                  height: 30,
                  decoration: ShapeDecoration(
                    color: selected ? Colors.white.withValues(alpha: 0.22)
                        : Colors.transparent,
                    shape: ExpressBorder(shape: selected
                        ? ExpressShape.cookie : ExpressShape.squircle),
                  ),
                  child: Icon(item.icon, size: 17, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(item.label, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ExpressType.headline.at(14, weight: 800, color: tint))),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}
