import 'package:flutter/material.dart';

class EditorToolAction {
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  const EditorToolAction(
      {required this.id,
      required this.label,
      required this.icon,
      required this.onPressed,
      this.selected = false});
}

/// Labeled actions wrap by available width and font size, never one long row.
class EditorToolPalette extends StatelessWidget {
  final List<EditorToolAction> actions;
  final bool compact;
  const EditorToolPalette(
      {super.key, required this.actions, this.compact = false});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, box) {
        final theme = Theme.of(ctx);
        final scale = MediaQuery.textScalerOf(ctx).scale(14) / 14;
        final minWidth = 100 * scale.clamp(1, 1.8);
        final columns = (box.maxWidth / (minWidth + 8)).floor().clamp(1, 4);
        final width = (box.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final action in actions)
            SizedBox(
                width: width,
                child: Tooltip(
                  message: action.label,
                  child: FilledButton.tonal(
                    key: ValueKey('editor-tool-${action.id}'),
                    onPressed: action.onPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: action.selected
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      foregroundColor: action.selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: compact
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(action.icon, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                                child: Text(action.label,
                                    style: theme.textTheme.labelMedium)),
                          ])
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(action.icon, size: 20),
                            const SizedBox(height: 4),
                            Text(action.label,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelMedium),
                          ]),
                  ),
                )),
        ]);
      });
}
