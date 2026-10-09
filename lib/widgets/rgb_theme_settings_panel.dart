import 'package:flutter/material.dart';

import '../services/rgb_theme_service.dart';

/// The hidden color feature is optional; update budget and hue speed are
/// independent so selecting a faster color cycle does not add more timers.
class RgbThemeSettingsPanel extends StatefulWidget {
  const RgbThemeSettingsPanel({super.key});

  @override
  State<RgbThemeSettingsPanel> createState() => _RgbThemeSettingsPanelState();
}

class _RgbThemeSettingsPanelState extends State<RgbThemeSettingsPanel> {
  double? _dragSpeed;

  @override
  Widget build(BuildContext context) {
    final service = RgbThemeService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!service.isUnlocked) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final speed = _dragSpeed ?? service.speed;
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text('RGB 动态炫彩',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Card.filled(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      key: const ValueKey('rgb-enabled'),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      title: const Text('启用动态炫彩'),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(service.statusDescription),
                      ),
                      value: service.isEnabled,
                      onChanged: service.setEnabled,
                    ),
                    if (service.isEnabled) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('颜色变化方式',
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final mode in RgbMode.values)
                                  ChoiceChip(
                                    key: ValueKey('rgb-mode-${mode.name}'),
                                    label: Text(mode.label),
                                    selected: service.mode == mode,
                                    onSelected: (_) => service.setMode(mode),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(service.mode.description,
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 24),
                            Text('主题更新预算',
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final quality in RgbQuality.values)
                                  ChoiceChip(
                                    key:
                                        ValueKey('rgb-quality-${quality.name}'),
                                    label: Text(quality.label),
                                    selected: service.quality == quality,
                                    onSelected: (_) =>
                                        service.setQuality(quality),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(service.quality.description,
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 6),
                            Text('这里只限制主题更新次数，不代表应用帧率。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 24),
                            Text('变色速度 ${speed.toStringAsFixed(1)}×',
                                key: const ValueKey('rgb-speed-value'),
                                style: Theme.of(context).textTheme.titleSmall),
                            Slider(
                              key: const ValueKey('rgb-speed-slider'),
                              min: .2,
                              max: 3,
                              divisions: 28,
                              value: speed,
                              label: '${speed.toStringAsFixed(1)}×',
                              onChanged: (value) =>
                                  setState(() => _dragSpeed = value),
                              onChangeEnd: (value) {
                                service.setSpeed(value);
                                setState(() => _dragSpeed = null);
                              },
                            ),
                            Text('只改变色彩循环速度，不提高主题更新频率。',
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 20),
                            RepaintBoundary(
                              child: ValueListenableBuilder<int>(
                                valueListenable: service.hueNotifier,
                                child: const Text('动态配色预览',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black54,
                                            blurRadius: 3),
                                      ],
                                    )),
                                builder: (context, _, label) => Container(
                                  key: const ValueKey('rgb-color-preview'),
                                  width: double.infinity,
                                  constraints:
                                      const BoxConstraints(minHeight: 64),
                                  padding: const EdgeInsets.all(16),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: service.rainbowGradient,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: label,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('切到后台或开启减少动画时，动态颜色会暂停。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
