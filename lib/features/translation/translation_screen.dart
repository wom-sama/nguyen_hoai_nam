import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../../ui/ledger.dart';
import '../handovers/handovers_screen.dart';
import 'speech_engine.dart';
import 'speech_models.dart';
import 'translation_service.dart';
import 'live_camera_screen.dart';
import 'translation_overlay.dart';

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({
    super.key,
    this.speechEngine,
    this.translationService,
  });

  /// Dependencies, when supplied, share this screen's ownership and lifecycle.
  final ContinuousSpeechEngine? speechEngine;
  final TranslationService? translationService;
  @override
  State<TranslationScreen> createState() => TranslationScreenState();
}

class _VoiceLine {
  _VoiceLine(this.id, this.original, this.source, this.target);
  final String id, original, source, target;
  String? translated, error;
}

class TranslationScreenState extends State<TranslationScreen>
    with WidgetsBindingObserver {
  static const _historyPageSize = 10;
  late final _service = widget.translationService ?? TranslationService();
  late final _engine = widget.speechEngine ?? ContinuousSpeechEngine();
  final _input = TextEditingController();
  FlutterTts? _tts;
  final List<_VoiceLine> _lines = [];
  // Chronological records are retained for this screen's complete session.
  // null follows the newest page; an explicit end anchors an older page even
  // while newly recognized speech is appended to the transcript.
  int? _historyEnd;
  StreamSubscription<SpeechEngineSnapshot>? _states;
  StreamSubscription<SpeechSegment>? _segments;
  SpeechEngineSnapshot _snapshot = const SpeechEngineSnapshot();
  Future<void> _translationQueue = Future.value();
  String _source = 'vi', _target = 'en', _mode = 'text', _output = '';
  bool _busy = false, _prepared = false, _listening = false, _closing = false;
  bool _openingCamera = false;
  ui.Image? _photoImage;
  OcrTranslation? _photoTranslation;
  bool _showPhotoText = false;
  int _queuedTranslations = 0;
  String? _error, _activity;
  int _voiceRequest = 0;
  Completer<void>? _foregroundResumed;
  Future<void> pause() async {
    _voiceRequest++;
    try {
      await _engine.stop();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine.setForeground(
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _states = _engine.states.listen((state) {
      if (mounted) {
        setState(() {
          _snapshot = state;
          if (state.error != null) _error = state.error;
          _listening =
              state.phase == 'listening' || state.phase == 'processing';
        });
      }
    });
    _segments = _engine.segments.listen(_onSegment);
  }

  void _onSegment(SpeechSegment segment) {
    if (!mounted || _closing) return;
    final line = _VoiceLine(
      segment.id,
      segment.text,
      segment.languageCode,
      _target,
    );
    final overloaded = _queuedTranslations >= 12;
    setState(() {
      _lines.add(line);
      if (overloaded) {
        line.error = 'Chưa dịch kịp đoạn này. Bản gốc vẫn được giữ lại.';
        _error = 'Bản dịch đang xử lý chậm. Đã dừng thu âm; các đoạn đã nhận vẫn được giữ trong lịch sử phiên này.';
      } else {
        _queuedTranslations++;
      }
    });
    if (overloaded) {
      unawaited(pause());
      return;
    }
    _translationQueue = _translationQueue.then((_) async {
      try {
        final translated = await _service.translate(
          line.original,
          sourceLanguage: line.source,
          targetLanguage: line.target,
        );
        if (mounted) setState(() => line.translated = translated);
      } catch (e) {
        if (mounted) setState(() => line.error = errorMessage(e));
      } finally {
        if (mounted) setState(() => _queuedTranslations--);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _engine.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      final resumed = _foregroundResumed;
      _foregroundResumed = null;
      if (resumed != null && !resumed.isCompleted) resumed.complete();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_engine.stop());
      unawaited(_tts?.stop() ?? Future.value());
    }
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _states?.cancel();
    _segments?.cancel();
    unawaited(_engine.dispose());
    unawaited(_service.dispose());
    unawaited(_tts?.stop() ?? Future.value());
    _input.dispose();
    _clearPhoto();
    super.dispose();
  }

  void _clearPhoto() {
    final old = _photoImage;
    _photoImage = null;
    _photoTranslation = null;
    _showPhotoText = false;
    // RawImage owns a clone in its RenderImage; release this screen's handle now.
    old?.dispose();
  }

  Future<void> _translate() async {
    if (_input.text.trim().isEmpty) {
      setState(() => _error = 'Nhập nội dung hoặc chọn ảnh có chữ để dịch.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _activity = 'Đang chuẩn bị gói ngôn ngữ và dịch…';
      _clearPhoto();
    });
    try {
      final value = await _service.translate(
        _input.text.trim(),
        sourceLanguage: _source,
        targetLanguage: _target,
      );
      if (mounted) setState(() => _output = value);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _activity = null;
        });
      }
    }
  }

  Future<void> _photo(ImageSource source) async {
    ui.Image? decoded;
    try {
      final picture = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2200,
        maxHeight: 2200,
        imageQuality: 90,
      );
      if (picture == null || !mounted) return;
      setState(() {
        _busy = true;
        _error = null;
        _activity = 'Đang đọc chữ trong ảnh…';
        _clearPhoto();
      });
      final codec = await ui.instantiateImageCodec(await picture.readAsBytes());
      try {
        decoded = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      final page = await _service.recognizeBitmap(
        decoded,
        sourceLanguage: _source,
      );
      if (!mounted) return;
      final translated = await _service.translatePage(
        page,
        sourceLanguage: _source,
        targetLanguage: _target,
      );
      if (mounted) {
        setState(() {
          _input.text = translated.originalText;
          _output = translated.translatedText;
          _photoImage = decoded;
          _photoTranslation = translated;
          decoded = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      decoded?.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
          _activity = null;
        });
      }
    }
  }

  Future<void> _openLiveCamera() async {
    if (_openingCamera) return;
    setState(() => _openingCamera = true);
    try {
      await pause();
      await _tts?.stop();
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => LiveCameraScreen(
            sourceLanguage: _source,
            targetLanguage: _target,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  Future<void> _voice() async {
    setState(() => _error = null);
    try {
      if (_listening) {
        await _engine.stop();
        return;
      }
      setState(() => _busy = true);
      final request = ++_voiceRequest;
      if (!await _engine.requestMicrophonePermission()) {
        throw const SpeechEngineException(
          'Chưa có quyền micro. Hãy cho phép micro để bắt đầu dịch.',
        );
      }
      if (!mounted || request != _voiceRequest) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        final resumed = _foregroundResumed ??= Completer<void>();
        await resumed.future.timeout(const Duration(seconds: 15));
      }
      if (!mounted || request != _voiceRequest) return;
      await _service.preparePair(
        sourceLanguage: _source,
        targetLanguage: _target,
      );
      if (!mounted ||
          request != _voiceRequest ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      await _engine.prepare(languageCode: _source);
      if (!mounted || request != _voiceRequest) return;
      _prepared = true;
      await _engine.start(languageCode: _source);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = e is SpeechEngineException ? e.message : errorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _speak(String text, String language) async {
    try {
      if (_listening) await _engine.stop();
      final tts = _tts ??= FlutterTts();
      final available = await tts.isLanguageAvailable(switch (language) {
        'vi' => 'vi-VN',
        'zh' => 'zh-CN',
        _ => 'en-US',
      });
      if (available != true) {
        if (mounted) {
          showMessage(context, 'Thiết bị chưa có giọng đọc cho ngôn ngữ này.');
        }
        return;
      }
      await tts.setLanguage(switch (language) {
        'vi' => 'vi-VN',
        'zh' => 'zh-CN',
        _ => 'en-US',
      });
      await tts.setSpeechRate(.45);
      await tts.speak(text);
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Chưa phát được giọng đọc trên thiết bị này.');
      }
    }
  }

  Future<void> _handover(
    String original,
    String translated,
    String source,
    String target,
  ) async {
    await _engine.stop();
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => HandoverComposer(
          initial: HandoverDraft(
            originalText: original,
            translatedText: translated,
            sourceLanguage: source,
            targetLanguage: target,
          ),
        ),
      ),
    );
    if (changed == true && mounted) {
      showMessage(context, 'Đã lưu phiếu bàn giao. Xem trong mục Bàn giao.');
    }
  }

  Future<void> _copyTranscript() async {
    final text = StringBuffer();
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      text.writeln(
        '[${index + 1} · ${translationLanguages[line.source] ?? line.source} → ${translationLanguages[line.target] ?? line.target}]',
      );
      text.writeln(line.original);
      text.writeln(line.translated ?? line.error ?? 'Đang dịch…');
      text.writeln();
    }
    await Clipboard.setData(ClipboardData(text: text.toString().trimRight()));
    if (mounted) {
      showMessage(context, 'Đã sao chép toàn bộ lịch sử của phiên này.');
    }
  }

  Widget _historyNavigation(int start, int end, {bool summary = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (summary) ...[
              Text(
                'Hiển thị đoạn ${start + 1}–$end / ${_lines.length}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _copyTranscript,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Sao chép toàn bộ phiên'),
                ),
              ),
            ],
            if (_lines.length > _historyPageSize)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: end >= _lines.length
                        ? null
                        : () => setState(() {
                            final next = end + _historyPageSize;
                            _historyEnd = next >= _lines.length ? null : next;
                          }),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Đoạn mới hơn'),
                  ),
                  OutlinedButton.icon(
                    onPressed: start == 0
                        ? null
                        : () => setState(() => _historyEnd = start),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Đoạn cũ hơn'),
                  ),
                ],
              ),
            if (summary && _historyEnd != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_lines.length - end} đoạn mới hơn đang được giữ.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _historyEnd = null),
                  child: const Text('Về đoạn mới nhất'),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _languagePicker(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey(value + onChanged.hashCode.toString()),
    initialValue: value,
    isExpanded: true,
    selectedItemBuilder: (context) => translationLanguages.entries
        .map(
          (e) => Text(
            e.value.replaceFirst('Tiếng ', ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            semanticsLabel: e.value,
          ),
        )
        .toList(),
    decoration: InputDecoration(
      labelText: label,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    items: translationLanguages.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: _busy || _listening
        ? null
        : (value) {
            if (value != null) onChanged(value);
          },
  );
  @override
  Widget build(BuildContext context) {
    final downloading = _snapshot.phase == 'downloading',
        loading = _snapshot.phase == 'loading';
    final historyEnd = _historyEnd ?? _lines.length;
    final historyStart = historyEnd > _historyPageSize
        ? historyEnd - _historyPageSize
        : 0;
    final visibleLines = _lines
        .getRange(historyStart, historyEnd)
        .toList(growable: false)
        .reversed;
    return AppPage(
      children: [
        const LedgerHeading(kicker: 'VIỆT · ANH · TRUNG', title: 'Dịch'),
        Row(
          children: [
            Expanded(
              child: _languagePicker(
                'Từ',
                _source,
                (v) => setState(() {
                  if (v == _target) _target = _source;
                  _source = v;
                  _output = '';
                  _clearPhoto();
                }),
              ),
            ),
            IconButton(
              tooltip: 'Đổi chiều dịch',
              onPressed: _busy || _listening
                  ? null
                  : () => setState(() {
                      final old = _source;
                      _source = _target;
                      _target = old;
                      _output = '';
                      _clearPhoto();
                    }),
              icon: const Icon(Icons.swap_horiz),
            ),
            Expanded(
              child: _languagePicker(
                'Sang',
                _target,
                (v) => setState(() {
                  if (v == _source) _source = _target;
                  _target = v;
                  _output = '';
                  _clearPhoto();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'text',
              label: Text('Ảnh / chữ'),
              icon: Icon(Icons.document_scanner_outlined),
            ),
            ButtonSegment(
              value: 'voice',
              label: Text('Giọng nói'),
              icon: Icon(Icons.mic_none_rounded),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: _busy
              ? null
              : (values) async {
                  await _engine.stop();
                  if (mounted) setState(() => _mode = values.first);
                },
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const ValueKey('open-live-camera'),
          onPressed: _busy || _openingCamera ? null : _openLiveCamera,
          icon: const Icon(Icons.video_camera_back_outlined),
          label: const Text('Dịch trực tiếp qua camera'),
        ),
        const SizedBox(height: 16),
        if (_error != null) Notice(_error!, isError: true),
        if (_activity != null) Notice(_activity!),
        if (_mode == 'text') ...[
          if (_photoImage != null && _photoTranslation != null) ...[
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Bản dịch trên ảnh',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng ảnh',
                        onPressed: () => setState(_clearPhoto),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      key: const ValueKey('photo-translation-preview'),
                      aspectRatio: _photoImage!.width / _photoImage!.height,
                      child: ColoredBox(
                        color: Colors.black87,
                        child: TranslationOverlayViewport(
                          imageSize: Size(
                            _photoImage!.width.toDouble(),
                            _photoImage!.height.toDouble(),
                          ),
                          image: RawImage(image: _photoImage, fit: BoxFit.fill),
                          regions: _photoTranslation!.regions,
                          onRegionTap: (region) =>
                              showOcrRegionDetails(context, region),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chạm vùng chữ để xem đầy đủ. Ảnh chỉ được xử lý trên thiết bị.',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  const GoogleTranslationAttribution(),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _showPhotoText = !_showPhotoText),
                    icon: Icon(
                      _showPhotoText ? Icons.expand_less : Icons.edit_outlined,
                    ),
                    label: Text(
                      _showPhotoText
                          ? 'Ẩn phần chỉnh sửa'
                          : 'Chỉnh sửa nội dung',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_photoImage == null || _showPhotoText)
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Bản gốc',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _input,
                    onChanged: (_) {
                      setState(() {
                        _clearPhoto();
                        _output = '';
                      });
                    },
                    minLines: 4,
                    maxLines: 9,
                    maxLength: 10000,
                    decoration: const InputDecoration(
                      hintText: 'Nhập nội dung cần dịch',
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _photo(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Chụp ảnh'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _photo(ImageSource.gallery),
                        icon: const Icon(Icons.photo_outlined),
                        label: const Text('Chọn ảnh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _busy ? null : _translate,
                    icon: const Icon(Icons.translate),
                    label: Text(_busy ? 'Đang xử lý…' : 'Dịch'),
                  ),
                ],
              ),
            ),
          if (_output.isNotEmpty)
            if (_photoImage != null)
              ExpansionTile(
                title: const Text('Xem nội dung và thao tác'),
                expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
                    ? AnimationStyle.noAnimation
                    : null,
                children: [
                  _resultCard(_input.text.trim(), _output, _source, _target),
                ],
              )
            else
              _resultCard(_input.text.trim(), _output, _source, _target),
        ] else ...[
          Surface(
            color: AppColors.palePink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      _listening ? Icons.graphic_eq : Icons.mic_none_rounded,
                      color: AppColors.pink,
                      size: 35,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _listening
                            ? 'Đang thu âm'
                            : downloading
                            ? 'Đang tải gói giọng nói…'
                            : loading
                            ? 'Đang chuẩn bị…'
                            : 'Chưa thu âm',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                if (_listening || (!_prepared && !downloading && !loading)) ...[
                  const SizedBox(height: 10),
                  Text(
                    _listening
                        ? 'Dừng ngắn giữa các ý để nhận bản dịch.'
                        : 'Lần đầu cần tải gói giọng nói khoảng ${(speechModelSetForLanguage(_source).downloadBytes / 1000000).ceil()} MB và gói dịch.',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _snapshot.progress),
                  const SizedBox(height: 7),
                  Text(
                    '${(_snapshot.progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppColors.pink, fontSize: 12),
                  ),
                ],
                if (_snapshot.queuedSegments > 0 || _queuedTranslations > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Đang xử lý ${_snapshot.queuedSegments + _queuedTranslations} đoạn',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _voice,
                  icon: Icon(
                    _listening
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                  ),
                  label: Text(
                    _listening
                        ? 'Dừng thu âm'
                        : _busy
                        ? 'Đang chuẩn bị…'
                        : 'Bắt đầu nghe',
                  ),
                ),
                if (_busy)
                  TextButton(
                    onPressed: () => _engine.stop(),
                    child: const Text('Hủy chuẩn bị'),
                  ),
              ],
            ),
          ),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(bottom: 16),
            shape: Border(),
            collapsedShape: Border(),
            title: Text('Cách dùng giọng nói', style: TextStyle(fontSize: 13)),
            children: [
              Text(
                'Sau khi tải gói, nhận dạng và dịch chạy trên thiết bị. Micro thu liên tục trong khi xử lý. Đổi màn hình hoặc đưa app về nền sẽ dừng thu. Lịch sử chỉ được giữ trong phiên này; sao chép trước khi đóng app.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ],
          ),
          if (_lines.isEmpty)
            const EmptyState(
              title: 'Chưa có đoạn nói',
              message: 'Bắt đầu nghe để nhận bản gốc và bản dịch.',
              icon: Icons.forum_outlined,
            ),
          if (_lines.isNotEmpty)
            _historyNavigation(historyStart, historyEnd, summary: true),
          for (final line in visibleLines) ...[
            if (line.error != null) Notice(line.error!, isError: true),
            if (line.translated != null)
              _resultCard(
                line.original,
                line.translated!,
                line.source,
                line.target,
                key: ValueKey('voice-line-${line.id}'),
              )
            else
              Surface(
                key: ValueKey('voice-line-${line.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.original),
                    const SizedBox(height: 10),
                    Text(
                      line.error == null
                          ? 'Đang dịch…'
                          : 'Chưa dịch được đoạn này.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
          ],
          if (_lines.length > _historyPageSize)
            _historyNavigation(historyStart, historyEnd),
        ],
        const SizedBox(height: 8),
        const Text(
          'Google Translate · Đối chiếu bản gốc trước khi sử dụng.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.7),
        ),
      ],
    );
  }

  Widget _resultCard(
    String original,
    String translated,
    String source,
    String target, {
    Key? key,
  }) => Surface(
    key: key,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          translationLanguages[source] ?? source,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        SelectableText(original, style: const TextStyle(fontSize: 13)),
        const Divider(),
        Text(
          translationLanguages[target] ?? target,
          style: const TextStyle(
            color: AppColors.pink,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SelectableText(
          translated,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            height: 1.6,
          ),
        ),
        const GoogleTranslationAttribution(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            IconButton(
              tooltip: 'Nghe bản dịch',
              onPressed: () => _speak(translated, target),
              icon: const Icon(Icons.volume_up_outlined),
            ),
            IconButton(
              tooltip: 'Sao chép bản dịch',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: translated));
                if (mounted) showMessage(context, 'Đã sao chép bản dịch.');
              },
              icon: const Icon(Icons.copy_outlined),
            ),
            OutlinedButton.icon(
              onPressed: () => _handover(original, translated, source, target),
              icon: const Icon(Icons.playlist_add_check_outlined),
              label: const Text('Tạo bàn giao'),
            ),
          ],
        ),
      ],
    ),
  );
}
