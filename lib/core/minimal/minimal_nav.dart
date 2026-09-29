import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/minimal/minimal_kit.dart';
import 'package:streak/core/minimal/minimal_type.dart';

class MinimalNavItem {
  const MinimalNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class MinimalNavRail extends StatelessWidget {
  const MinimalNavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    required this.brand,
    this.footer,
  });

  static const width = 208.0;

  final List<MinimalNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget brand;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 16),
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
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _RailTile(
                            item: items[i],
                            selected: i == index,
                            onTap: () => onSelect(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (footer != null) footer!,
            ],
          ),
        ),
      ),
    );
  }
}

class _RailTile extends StatefulWidget {
  const _RailTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final MinimalNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailTile> createState() => _RailTileState();
}

class _RailTileState extends State<_RailTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final scheme = context.colors;
    final tint = selected ? scheme.surface : context.tokens.muted;

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
            backgroundColor: selected ? scheme.onSurface
                : (_hover ? minimalRaised(context) : Colors.transparent),
            minimumSize: const Size(40, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Semantics(
            label: item.label,
            excludeSemantics: true,
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: tint),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MinimalType.label(size: 13.5, color: tint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}
