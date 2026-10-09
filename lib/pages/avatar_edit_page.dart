import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api/klpbbs_api.dart';
import '../core/avatar_image_processor.dart';
import '../core/dio_client.dart';
import '../core/discuz_avatar_protocol.dart';
import '../models/user_space.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_motion.dart';
import '../widgets/avatar_shape_clip.dart';
import '../widgets/thread_card.dart';
import 'phone_bind_page.dart';
import 'web_login_page.dart';

class AvatarEditPage extends StatefulWidget {
  final UserSpace? userSpace;
  const AvatarEditPage({super.key, this.userSpace});
  @override
  State<AvatarEditPage> createState() => _AvatarEditPageState();
}

class _AvatarEditPageState extends State<AvatarEditPage> {
  DiscuzAvatarReceipt? _receipt;
  AvatarImageInspection? _inspection;
  PreparedAvatar? _prepared;
  Uint8List? _bytes;
  AvatarCrop _crop = const AvatarCrop();
  Timer? _debounce;
  bool _loading = true,
      _selecting = false,
      _preparing = false,
      _submitting = false,
      _confirming = false;
  bool _keepAnimation = true, _resultSuccess = false;
  int _generation = 0,
      _revision = 0,
      _selectionSerial = 0,
      _confirmationSerial = 0,
      _preparedRevision = -1,
      _submittedRevision = -1;
  String? _loadError, _selectionError, _processingError, _submitError;
  String _fileName = '', _result = '';

  bool get _editingDisabled =>
      _loading || _selecting || _submitting || _confirming;

  UserSpace? get _currentSpace =>
      widget.userSpace?.uid == _receipt?.descriptor.uid
          ? widget.userSpace
          : null;

  @override
  void initState() {
    super.initState();
    DioClient.sessionChanges.addListener(_onAccountChanged);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    DioClient.sessionChanges.removeListener(_onAccountChanged);
    _bytes = null;
    super.dispose();
  }

  void _onAccountChanged() {
    _debounce?.cancel();
    setState(() {
      _receipt = null;
      _bytes = null;
      _inspection = null;
      _prepared = null;
      _result = '';
      _fileName = '';
      _resultSuccess = false;
      _crop = const AvatarCrop();
      _keepAnimation = true;
      _loadError = _selectionError = _processingError = _submitError = null;
      _revision++;
      _selectionSerial++;
      _confirmationSerial++;
      _preparedRevision = _submittedRevision = -1;
      _selecting = _submitting = _confirming = false;
    });
    _load();
  }

  String _message(Object error) => error is FileSystemException
      ? '所选图片无法读取，请检查文件后重试'
      : error.toString().replaceFirst(
          RegExp(r'^(Bad state:|Exception:|FormatException:)\s*'), '');

  Future<void> _load() async {
    final generation = ++_generation, session = DioClient.sessionKey;
    setState(() {
      _loading = true;
      _receipt = null;
      _loadError = null;
    });
    try {
      final receipt = await KlpbbsApi.getAvatarEditor(expectedSession: session);
      if (!mounted ||
          generation != _generation ||
          session != DioClient.sessionKey) {
        return;
      }
      setState(() => _receipt = receipt);
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          session == DioClient.sessionKey) {
        setState(() => _loadError = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<Uint8List> _readFile(PlatformFile file) async {
    if (file.size > AvatarImageProcessor.maxFileBytes) {
      throw const FormatException('请选择小于 8 MB 的头像图片');
    }
    if (file.bytes != null) {
      if (file.bytes!.length > AvatarImageProcessor.maxFileBytes) {
        throw const FormatException('请选择小于 8 MB 的头像图片');
      }
      return file.bytes!;
    }
    final stream = file.readStream ??
        (file.path == null ? null : File(file.path!).openRead());
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        if (builder.length + chunk.length > AvatarImageProcessor.maxFileBytes) {
          throw const FormatException('请选择小于 8 MB 的头像图片');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }
    throw const FormatException('所选图片无法读取，请重新选择');
  }

  Future<void> _select() async {
    if (_editingDisabled || _receipt?.descriptor.canUpload != true) {
      return;
    }
    final generation = _generation, session = DioClient.sessionKey;
    final selectionSerial = ++_selectionSerial;
    bool current() =>
        mounted &&
        selectionSerial == _selectionSerial &&
        generation == _generation &&
        session == DioClient.sessionKey;
    setState(() {
      _selecting = true;
      _selectionError = null;
      _submitError = null;
      _result = '';
    });
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'apng', 'webp'],
        withData: false,
        withReadStream: true,
      );
      if (selection == null || !current()) return;
      final bytes = await _readFile(selection.files.single);
      if (!current()) return;
      final inspection = await AvatarImageProcessor.inspect(bytes);
      if (!current()) return;
      setState(() {
        _bytes = bytes;
        _inspection = inspection;
        _fileName = selection.files.single.name;
        _crop = const AvatarCrop();
        _keepAnimation = true;
        _prepared = null;
        _selectionError = _processingError = null;
        _revision++;
        _preparedRevision = _submittedRevision = -1;
      });
      await _prepare();
    } catch (error) {
      if (current()) {
        // Some image decoders read beyond a truncated header before they can
        // return a FormatException. Keep damaged input errors readable here.
        setState(() => _selectionError =
            error is RangeError ? '图片数据不完整，请重新选择' : _message(error));
      }
    } finally {
      // A refresh invalidates selection results, but must still release the
      // selecting flag. A newer account's selection owns a different serial.
      if (mounted && selectionSerial == _selectionSerial) {
        setState(() => _selecting = false);
      }
    }
  }

  void _changeCrop(
      {double? horizontal, double? vertical, double? zoom, int? turns}) {
    if (_editingDisabled) return;
    setState(() {
      _crop = AvatarCrop(
        horizontal: (horizontal ?? _crop.horizontal).clamp(0, 1),
        vertical: (vertical ?? _crop.vertical).clamp(0, 1),
        zoom: (zoom ?? _crop.zoom).clamp(1, 4),
        quarterTurns: turns ?? _crop.quarterTurns,
      );
      _revision++;
      _result = '';
      _selectionError = _processingError = _submitError = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _prepare);
  }

  Future<void> _prepare() async {
    _debounce?.cancel();
    if (!mounted || _bytes == null || _preparing) return;
    setState(() => _preparing = true);
    try {
      // At most one worker is active. If the user changes the crop while it
      // runs, discard that result and prepare the latest selection next.
      while (mounted && _bytes != null && _preparedRevision != _revision) {
        final generation = _generation, revision = _revision;
        try {
          final prepared = await AvatarImageProcessor.prepare(_bytes!, _crop,
              keepAnimation: _keepAnimation);
          if (!mounted) return;
          if (generation != _generation || revision != _revision) continue;
          setState(() {
            _prepared = prepared;
            _preparedRevision = revision;
            _processingError = null;
          });
        } catch (error) {
          if (!mounted) return;
          if (generation != _generation || revision != _revision) continue;
          setState(() {
            _processingError = _message(error);
            _prepared = null;
          });
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _submit() async {
    final receipt = _receipt, prepared = _prepared, revision = _revision;
    if (receipt == null ||
        prepared == null ||
        _preparedRevision != revision ||
        _preparing ||
        _editingDisabled ||
        _submittedRevision == revision ||
        receipt.session != DioClient.sessionKey) {
      return;
    }
    final generation = _generation;
    final confirmationSerial = ++_confirmationSerial;
    final review = receipt.descriptor.requiresReview;
    setState(() => _confirming = true);
    bool? accepted;
    try {
      accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(review ? '提交头像审核' : '保存头像'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  AvatarShapeClip(
                      size: 88,
                      child: Image.memory(prepared.preview,
                          width: 88, height: 88, fit: BoxFit.cover)),
                  const SizedBox(height: 16),
                  Text('将为当前账号 UID ${receipt.descriptor.uid} 提交此头像。'),
                  if (prepared.animated) ...[
                    const SizedBox(height: 12),
                    const Text('将尝试保留动画；论坛可能拒绝动图或转换为静态图片，最终显示取决于论坛处理结果。'),
                  ],
                  if (review) ...[
                    const SizedBox(height: 12),
                    const Text('审核通过后，论坛才会更新你的头像。'),
                  ],
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      key: const ValueKey('avatar-confirm-submit'),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认提交')),
                ],
              ));
    } finally {
      if (mounted && confirmationSerial == _confirmationSerial) {
        setState(() => _confirming = false);
      }
    }
    if (!mounted ||
        accepted != true ||
        generation != _generation ||
        revision != _revision ||
        !identical(_receipt, receipt) ||
        receipt.session != DioClient.sessionKey) {
      return;
    }
    setState(() {
      _submitting = true;
      _result = '';
      _submitError = null;
    });
    try {
      final result = await KlpbbsApi.submitAvatar(receipt, prepared,
          allowAnimationAttempt: prepared.animated);
      if (!mounted ||
          generation != _generation ||
          receipt.session != DioClient.sessionKey) {
        return;
      }
      setState(() {
        _result = result.message;
        _resultSuccess = result.success;
        if (result.success) _submittedRevision = revision;
      });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          receipt.session == DioClient.sessionKey) {
        setState(() => _submitError = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _cropPreview() {
    final inspection = _inspection!;
    return LayoutBuilder(builder: (context, constraints) {
      final side = math.min(320.0, constraints.maxWidth);
      final swapped = _crop.quarterTurns.isOdd;
      final width = (swapped ? inspection.height : inspection.width).toDouble();
      final height =
          (swapped ? inspection.width : inspection.height).toDouble();
      final factor = side * _crop.zoom / math.min(width, height);
      final renderedWidth = width * factor, renderedHeight = height * factor;
      return Center(
          child: Semantics(
        label: '头像裁剪预览，可拖动调整位置',
        child: GestureDetector(
          key: const ValueKey('avatar-crop-preview'),
          onPanUpdate: _editingDisabled
              ? null
              : (event) => _changeCrop(
                    horizontal: renderedWidth > side
                        ? _crop.horizontal -
                            event.delta.dx / (renderedWidth - side)
                        : null,
                    vertical: renderedHeight > side
                        ? _crop.vertical -
                            event.delta.dy / (renderedHeight - side)
                        : null,
                  ),
          onPanEnd: (_) => _prepare(),
          child: SizedBox(
            width: side,
            height: side,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: RepaintBoundary(
                  child: Stack(children: [
                Positioned(
                  left: -(renderedWidth - side) * _crop.horizontal,
                  top: -(renderedHeight - side) * _crop.vertical,
                  width: renderedWidth,
                  height: renderedHeight,
                  child: RotatedBox(
                      quarterTurns: _crop.quarterTurns,
                      child: Image.memory(inspection.preview,
                          fit: BoxFit.fill, gaplessPlayback: true)),
                ),
                Positioned.fill(
                    child: IgnorePointer(
                        child: CustomPaint(
                            painter: _AvatarGuidePainter(Theme.of(context)
                                .colorScheme
                                .outlineVariant)))),
              ])),
            ),
          ),
        ),
      ));
    });
  }

  Widget _slider(
      String label, IconData icon, double value, ValueChanged<double> change,
      {double min = 0, double max = 1, Key? key}) {
    return Row(children: [
      Tooltip(message: label, child: Icon(icon, size: 22)),
      const SizedBox(width: 8),
      Expanded(
          child: Semantics(
              label: label,
              child: Slider(
                  key: key,
                  min: min,
                  max: max,
                  value: value,
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()}%',
                  onChanged: _editingDisabled ? null : change,
                  onChangeEnd: (_) => _prepare()))),
    ]);
  }

  Widget _editor() {
    final theme = Theme.of(context), inspection = _inspection!;
    return Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('调整头像', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            _cropPreview(),
            const SizedBox(height: 12),
            Text('拖动图片调整位置',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            _slider('缩放', Icons.zoom_in_rounded, _crop.zoom,
                (value) => _changeCrop(zoom: value),
                min: 1, max: 4, key: const ValueKey('avatar-zoom')),
            _slider('水平位置', Icons.swap_horiz_rounded, _crop.horizontal,
                (value) => _changeCrop(horizontal: value)),
            _slider('垂直位置', Icons.swap_vert_rounded, _crop.vertical,
                (value) => _changeCrop(vertical: value)),
            Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
              IconButton.filledTonal(
                  tooltip: '向左旋转',
                  onPressed: _editingDisabled
                      ? null
                      : () => _changeCrop(turns: _crop.quarterTurns - 1),
                  icon: const Icon(Icons.rotate_left_rounded)),
              IconButton.filledTonal(
                  tooltip: '向右旋转',
                  onPressed: _editingDisabled
                      ? null
                      : () => _changeCrop(turns: _crop.quarterTurns + 1),
                  icon: const Icon(Icons.rotate_right_rounded)),
              TextButton.icon(
                  onPressed: _editingDisabled
                      ? null
                      : () => _changeCrop(
                          horizontal: .5, vertical: .5, zoom: 1, turns: 0),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('重置裁剪')),
            ]),
            if (inspection.animated) ...[
              const Divider(height: 24),
              SwitchListTile(
                key: const ValueKey('avatar-keep-animation'),
                contentPadding: EdgeInsets.zero,
                title: const Text('保留动画'),
                subtitle: Text('${inspection.frames} 帧 · '
                    '${inspection.animationFormat == AvatarImageFormat.apng ? 'APNG' : 'GIF'}'),
                value: _keepAnimation,
                onChanged: _editingDisabled
                    ? null
                    : (value) {
                        setState(() {
                          _keepAnimation = value;
                          _revision++;
                          _result = '';
                          _selectionError =
                              _processingError = _submitError = null;
                        });
                        _prepare();
                      },
              ),
            ],
          ]),
        ));
  }

  Widget _uploadPreview() {
    final theme = Theme.of(context), prepared = _prepared;
    return Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('上传预览', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            if (_preparing || _selecting) ...[
              const SizedBox(
                  height: 110, child: Center(child: AppLoadingIndicator())),
              Text(_selecting ? '正在读取图片…' : '正在处理图片…',
                  textAlign: TextAlign.center),
            ] else if (prepared == null || _preparedRevision != _revision) ...[
              Icon(Icons.image_not_supported_outlined,
                  size: 56, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                  _processingError == null ? '调整裁剪后将更新预览' : '图片处理失败，请调整裁剪或更换图片',
                  textAlign: TextAlign.center),
            ] else ...[
              Wrap(
                  alignment: WrapAlignment.spaceAround,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 12,
                  runSpacing: 16,
                  children: [
                    for (var index = 0; index < 3; index++)
                      Column(children: [
                        RepaintBoundary(
                            child: AvatarShapeClip(
                                size: const [88.0, 64.0, 40.0][index],
                                child: Image.memory(
                                    prepared.format == AvatarImageFormat.apng
                                        ? prepared.preview
                                        : prepared.variants[index],
                                    semanticLabel:
                                        '上传头像 ${prepared.sizes[index]} 像素',
                                    fit: BoxFit.cover,
                                    width: const [88.0, 64.0, 40.0][index],
                                    height: const [88.0, 64.0, 40.0][index]))),
                        const SizedBox(height: 8),
                        Text('${prepared.sizes[index]} px',
                            style: theme.textTheme.labelMedium),
                      ]),
                  ]),
              const SizedBox(height: 16),
              Text(_fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                  '${(prepared.byteLength / 1024).toStringAsFixed(1)} KB · '
                  '${prepared.animated ? '${prepared.frames} 帧' : '静态图片'}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
                key: const ValueKey('avatar-choose-another'),
                onPressed: _editingDisabled ? null : _select,
                icon: const Icon(Icons.image_outlined),
                label: const Text('更换图片')),
            const SizedBox(height: 10),
            FilledButton.icon(
                key: const ValueKey('avatar-submit'),
                onPressed: _preparing ||
                        prepared == null ||
                        _preparedRevision != _revision ||
                        _submittedRevision == _revision ||
                        _editingDisabled
                    ? null
                    : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_rounded),
                label: Text(
                    _receipt!.descriptor.requiresReview ? '提交审核' : '保存头像')),
          ]),
        ));
  }

  Widget _notice(String message, {bool success = false}) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        success ? colors.onPrimaryContainer : colors.onErrorContainer;
    return Semantics(
        liveRegion: true,
        child: Card.filled(
          color: success ? colors.primaryContainer : colors.errorContainer,
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(
                    success
                        ? Icons.check_circle_outline_rounded
                        : Icons.info_outline_rounded,
                    color: foreground),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(message, style: TextStyle(color: foreground))),
              ])),
        ));
  }

  Widget _body() {
    final theme = Theme.of(context), descriptor = _receipt?.descriptor;
    if (_loading) return const Center(child: AppLoadingIndicator());
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 850;
      return Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(padding: EdgeInsets.all(wide ? 24 : 16), children: [
          if (_loadError != null) _notice(_loadError!),
          if (_selectionError != null) _notice(_selectionError!),
          if (_processingError != null) _notice(_processingError!),
          if (_submitError != null) _notice(_submitError!),
          if (_result.isNotEmpty) _notice(_result, success: _resultSuccess),
          Card.filled(
            color: theme.colorScheme.secondaryContainer,
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  if (descriptor?.uid != null) ...[
                    UserAvatarWidget(
                        uid: descriptor!.uid!,
                        author: _currentSpace?.username ?? '',
                        faceUrl: UserAvatarWidget.optionalFrame(
                            _currentSpace?.faceUrl),
                        reserveFrameSpace: true,
                        size: 56),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('让头像更有个性', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(descriptor?.requiresReview == true
                            ? '选择图片、调整裁剪，提交后等待论坛审核。'
                            : '选择图片，预览满意后保存。'),
                      ])),
                ])),
          ),
          if (descriptor?.canUpload != true)
            Card.outlined(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.account_circle_outlined,
                      size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('暂时无法修改头像', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Text(
                      descriptor?.statusMessage.isNotEmpty == true
                          ? descriptor!.statusMessage
                          : (_loadError != null
                              ? '头像页面读取失败，请重试'
                              : descriptor?.uid == null
                                  ? '请先登录论坛账号'
                                  : '论坛未提供当前账号可使用的头像上传表单'),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (descriptor?.phoneBindingUri != null)
                          FilledButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) => PhoneBindPage(
                                            userSpace: _currentSpace)));
                                if (mounted) _load();
                              },
                              child: const Text('绑定手机号')),
                        if (descriptor?.uid == null && _loadError == null)
                          FilledButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) => const WebLoginPage()));
                                if (mounted) _load();
                              },
                              child: const Text('登录论坛')),
                        OutlinedButton(
                            onPressed: _load, child: const Text('重新读取')),
                      ]),
                ]),
              ),
            )
          else if (_inspection == null)
            Card.outlined(
              margin: EdgeInsets.zero,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
                child: Column(children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 20),
                  Text('选择你的头像', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 10),
                  const Text('支持 JPG、PNG、GIF、APNG 和 WebP，最大 8 MB。',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                      key: const ValueKey('avatar-choose-image'),
                      onPressed: _selecting ? null : _select,
                      icon: _selecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.image_outlined),
                      label: Text(_selecting ? '读取图片…' : '选择图片')),
                ]),
              ),
            )
          else if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: _editor()),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: _uploadPreview()),
            ])
          else ...[_editor(), const SizedBox(height: 16), _uploadPreview()],
        ]),
      ));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            leading: const AppBackButton(),
            title: const Text('修改头像'),
            actions: [
              IconButton(
                  key: const ValueKey('avatar-refresh'),
                  tooltip: '刷新头像页面',
                  onPressed:
                      _loading || _selecting || _submitting || _confirming
                          ? null
                          : _load,
                  icon: const Icon(Icons.refresh_rounded))
            ]),
        body: _body(),
      );
}

class _AvatarGuidePainter extends CustomPainter {
  final Color color;
  const _AvatarGuidePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(
        size.center(Offset.zero), size.shortestSide / 2 - 1, paint);
  }

  @override
  bool shouldRepaint(_AvatarGuidePainter oldDelegate) =>
      oldDelegate.color != color;
}
