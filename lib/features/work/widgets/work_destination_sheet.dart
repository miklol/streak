import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:streak/app/theme/app_tokens.dart';
import 'package:streak/core/i18n/l10n.dart';
import 'package:streak/core/utils/responsive.dart';
import 'package:streak/core/widgets/app_empty_state.dart';
import 'package:streak/core/widgets/sheet_type.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/state/work_controller.dart';
import 'package:streak/features/work/widgets/work_ui.dart';

class WorkDestination {
  const WorkDestination({this.areaId, this.projectId});

  final String? areaId;
  final String? projectId;
}

Future<WorkDestination?> showWorkDestinationPicker(
  BuildContext context, {
  String? areaId,
  String? projectId,
}) {
  return showModalBottomSheet<WorkDestination>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: isWideLayout(context) ? 560 : double.infinity,
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (sheet) => _WorkDestinationSheet(
      areaId: areaId,
      projectId: projectId,
    ),
  );
}

class _WorkDestinationSheet extends StatelessWidget {
  const _WorkDestinationSheet({this.areaId, this.projectId});

  final String? areaId;
  final String? projectId;

  @override
  Widget build(BuildContext context) {
    final work = context.watch<WorkController>();
    final areas = work.areas();
    final projects = work
        .projects()
        .where(
          (project) =>
              project.status != WorkProjectStatus.done &&
              project.status != WorkProjectStatus.cancelled,
        )
        .toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(
              context.l10n.work_destination_picker_title,
              subtitle: context.l10n.work_destination_picker_sub,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _DestinationTile(
                    icon: LucideIcons.inbox,
                    title: context.l10n.work_scope_inbox,
                    subtitle: context.l10n.work_destination_inbox_sub,
                    selected: areaId == null && projectId == null,
                    onTap: () => Navigator.of(context).pop(
                      const WorkDestination(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (areas.isEmpty && projects.isEmpty)
                    AppEmptyState(
                      icon: LucideIcons.briefcase,
                      title: context.l10n.work_destination_empty,
                      message: context.l10n.work_destination_empty_sub,
                      compact: true,
                    )
                  else ...[
                    if (areas.isNotEmpty) ...[
                      Text(
                        context.l10n.work_areas,
                        style: sheetLabelStyle(context),
                      ),
                      const SizedBox(height: 8),
                      for (final area in areas) ...[
                        _DestinationTile(
                          icon: LucideIcons.briefcase,
                          title: area.name,
                          subtitle: workAreaTypeLabel(context, area.type),
                          selected: projectId == null && areaId == area.id,
                          onTap: () => Navigator.of(context).pop(
                            WorkDestination(areaId: area.id),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 10),
                    ],
                    if (projects.isNotEmpty) ...[
                      Text(
                        context.l10n.work_projects,
                        style: sheetLabelStyle(context),
                      ),
                      const SizedBox(height: 8),
                      for (final project in projects) ...[
                        _DestinationTile(
                          icon: LucideIcons.folder,
                          title: project.name,
                          subtitle: workProjectContextLabel(
                            context,
                            work,
                            project,
                          ),
                          selected: projectId == project.id,
                          onTap: () => Navigator.of(context).pop(
                            WorkDestination(
                              areaId: project.areaId,
                              projectId: project.id,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = context.colors.primary;
    return Material(
      color: selected
          ? selectedColor.withValues(alpha: 0.12)
          : context.colors.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? selectedColor.withValues(alpha: 0.18)
                      : context.colors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? selectedColor : context.tokens.muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: sheetHeadingStyle(context, size: 15)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: sheetBodyStyle(context, size: 13)),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  LucideIcons.check,
                  size: 18,
                  color: selectedColor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
