import 'package:flutter/material.dart';
import '../services/pc_gpu_service.dart';
import 'app_motion.dart';
import 'responsive_layout.dart';

/// This panel owns no forum preferences and writes only after an explicit save.
class PcGpuSettingsPanel extends StatefulWidget {
  final PcGpuService? service;
  const PcGpuSettingsPanel({super.key, this.service});
  @override
  State<PcGpuSettingsPanel> createState() => _PcGpuSettingsPanelState();
}

class _PcGpuSettingsPanelState extends State<PcGpuSettingsPanel> {
  PcGpuSnapshot? _snapshot;
  PcGpuPreference _selected = PcGpuPreference.auto;
  String? _error;
  bool _loading = false;
  bool _saving = false;
  bool _started = false;
  int _request = 0;
  PcGpuService get _service => widget.service ?? PcGpuService.instance;

  bool get _visible => PcGpuSnapshot.visible(
      windows: PcGpuService.supportedPlatform,
      desktop: ResponsiveBreakpoints.isDesktop(context));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_visible && !_started) {
      _started = true;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_saving || !_visible) return;
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final snapshot = await _service.read();
      if (!mounted || request != _request) return;
      setState(() {
        _snapshot = snapshot;
        _selected = snapshot.preference;
        _error = null;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    final old = _snapshot;
    if (_saving ||
        _loading ||
        !_visible ||
        old == null ||
        !old.supported ||
        (!old.canSave(_selected) && old.configurationError == null)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await _service.save(_selected);
      if (!mounted) return;
      setState(() {
        _snapshot = saved;
        _selected = saved.preference;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved.nextStartRequiresRestart
              ? '显卡偏好已保存，重新启动应用后生效'
              : '显卡偏好已保存，当前启动偏好无需变化')));
    } catch (error) {
      if (mounted) {
        setState(() {
          _selected = old.preference;
          _error = '未能确认保存，界面已恢复原选择。请刷新核对：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      await _service.openWindowsGraphicsSettings();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Widget _choices(ThemeData theme) => LayoutBuilder(builder: (_, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final columns = (constraints.maxWidth / (220 * scale.clamp(1.0, 1.8)))
            .floor()
            .clamp(1, 3);
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final preference in PcGpuPreference.values)
            SizedBox(
              width: width,
              child: Material(
                color: _selected == preference
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                        color: _selected == preference
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant)),
                child: Semantics(
                  key: ValueKey('pc-gpu-choice-${preference.wire}'),
                  selected: _selected == preference,
                  button: true,
                  child: InkWell(
                      key: ValueKey('pc-gpu-${preference.wire}'),
                      borderRadius: BorderRadius.circular(18),
                      onTap: _loading || _saving || _snapshot?.supported != true
                          ? null
                          : () => setState(() => _selected = preference),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(_selected == preference
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(preference.label,
                                          style: theme.textTheme.titleSmall)),
                                ]),
                                const SizedBox(height: 8),
                                Text(preference.description,
                                    style: theme.textTheme.bodySmall),
                              ]))),
                ),
              ),
            ),
        ]);
      });

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final busy = _loading || _saving;
    return Card.filled(
        key: const ValueKey('pc-gpu-panel'),
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.memory_rounded),
                const SizedBox(width: 12),
                Expanded(
                    child: Text('显卡与性能', style: theme.textTheme.titleLarge)),
                IconButton(
                    tooltip: '刷新本机显卡信息',
                    onPressed: busy ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 8),
              Text('只影响本应用下次启动的渲染偏好，保存后请自行重新启动应用。',
                  style: theme.textTheme.bodyMedium),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_error!,
                        key: const ValueKey('pc-gpu-error'),
                        style: TextStyle(color: theme.colorScheme.error))),
              if (_loading && snapshot == null)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Row(children: [
                      SizedBox(
                          width: 24,
                          height: 24,
                          child: AppLoadingIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Expanded(child: Text('正在读取本机显卡')),
                    ])),
              if (snapshot != null) ...[
                const SizedBox(height: 16),
                Text('当前渲染设备', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText(snapshot.currentName ?? '当前渲染设备暂不可确认',
                    key: const ValueKey('pc-gpu-current-device'),
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('本次启动：${snapshot.startupPreference.label} · '
                    '已保存：${snapshot.preference.label}'),
                if (snapshot.nextStartRequiresRestart)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Chip(
                          key: const ValueKey('pc-gpu-restart-required'),
                          avatar: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('下次启动生效'))),
                if (snapshot.configurationError != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          '已有配置未能完整读取，本次按自动启动：${snapshot.configurationError}',
                          style: TextStyle(color: theme.colorScheme.error))),
                const SizedBox(height: 18),
                _choices(theme),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  FilledButton.icon(
                      key: const ValueKey('pc-gpu-save'),
                      onPressed: busy ||
                              !snapshot.supported ||
                              (!snapshot.canSave(_selected) &&
                                  snapshot.configurationError == null)
                          ? null
                          : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? '正在保存' : '保存显卡偏好')),
                  OutlinedButton.icon(
                      key: const ValueKey('pc-gpu-windows-settings'),
                      onPressed:
                          busy || snapshot.preview ? null : _openSystemSettings,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('打开 Windows 图形设置')),
                ]),
                const SizedBox(height: 18),
                Text('本机硬件适配器', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                if (snapshot.adapters.isEmpty) const Text('没有取得可显示的硬件适配器信息'),
                for (final adapter in snapshot.adapters)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(adapter.name,
                                    style: theme.textTheme.titleSmall),
                                if (snapshot.isCurrent(adapter))
                                  Text('当前使用',
                                      style: TextStyle(
                                          color: theme.colorScheme.primary)),
                                const SizedBox(height: 4),
                                Text(
                                    '专用显存 ${PcGpuSnapshot.memoryLabel(adapter.dedicatedVideoMemory)}\n'
                                    '可共享系统内存上限 ${PcGpuSnapshot.memoryLabel(adapter.sharedSystemMemory)}'),
                              ]))),
                if (snapshot.inventoryError != null)
                  Text('显卡信息未能完整取得：${snapshot.inventoryError}',
                      style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 8),
                Text(
                    '当前 Flutter 引擎提供性能偏好，无法绑定指定显卡。若要为应用指定设备，请在 Windows 图形设置中配置；系统或驱动可能影响最终选择。',
                    style: theme.textTheme.bodySmall),
              ],
            ])));
  }
}
