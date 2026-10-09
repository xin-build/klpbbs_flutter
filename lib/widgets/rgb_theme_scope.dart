import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../core/rgb_theme_policy.dart';
import '../services/rgb_theme_service.dart';

/// Hue updates stay below MaterialApp and preserve its Navigator/route child.
/// Widgets that depend on Theme still rebuild when their colors change.
class RgbThemeScope extends StatefulWidget {
  final Widget child;
  const RgbThemeScope({super.key, required this.child});

  @override
  State<RgbThemeScope> createState() => _RgbThemeScopeState();
}

class _RgbThemeScopeState extends State<RgbThemeScope> {
  final _themes = BoundedValueCache<int, ThemeData>(capacity: 12);
  ThemeData? _baseTheme;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    if (_baseTheme != base) {
      _baseTheme = base;
      _themes.clear();
    }
    final service = RgbThemeService.instance;
    return ListenableBuilder(
      listenable: service,
      child: widget.child,
      builder: (context, content) {
        return ValueListenableBuilder<int>(
          valueListenable: service.hueNotifier,
          child: content,
          builder: (context, hue, preservedChild) {
            final theme = service.isEnabled
                ? _themes.getOrCreate(hue, () {
                    final colors = base.brightness == Brightness.dark
                        ? service.getDarkColorScheme(
                            isOled: AppConfig.isOledDark)
                        : service.getLightColorScheme();
                    // Keep neutral surfaces/text stable. Updating accents is clearer
                    // than repainting the entire window background on every hue.
                    final neutral = base.colorScheme;
                    final scheme = colors.copyWith(
                      surface: neutral.surface,
                      onSurface: neutral.onSurface,
                      onSurfaceVariant: neutral.onSurfaceVariant,
                      surfaceContainerLowest: neutral.surfaceContainerLowest,
                      surfaceContainerLow: neutral.surfaceContainerLow,
                      surfaceContainer: neutral.surfaceContainer,
                      surfaceContainerHigh: neutral.surfaceContainerHigh,
                      surfaceContainerHighest: neutral.surfaceContainerHighest,
                      outline: neutral.outline,
                      outlineVariant: neutral.outlineVariant,
                    );
                    return AppTheme.polish(base.copyWith(
                      colorScheme: scheme,
                      primaryColor: scheme.primary,
                      indicatorColor: scheme.primary,
                      inputDecorationTheme: base.inputDecorationTheme.copyWith(
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: scheme.primary, width: 1.6),
                        ),
                      ),
                      textSelectionTheme: base.textSelectionTheme.copyWith(
                        cursorColor: scheme.primary,
                        selectionColor: scheme.primary.withAlpha(70),
                        selectionHandleColor: scheme.primary,
                      ),
                    ));
                  })
                : base;
            return Theme(
              key: const ValueKey('rgb-theme-scope'),
              data: theme,
              child: preservedChild!,
            );
          },
        );
      },
    );
  }
}
