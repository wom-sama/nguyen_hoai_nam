import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../handovers/handovers_screen.dart';
import 'translation_service.dart';
import 'camera_frame.dart';

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({
    super.key,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.translationService,
  });
  final String sourceLanguage, targetLanguage;
  final TranslationService? translationService;
  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _CameraTranslation {
  _CameraTranslation({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.originalText,
    required this.translatedText,
    this.saved = false,
    this.createdAt,
  }) : clientRequestId = _requestId();

  factory _CameraTranslation.fromJson(Json row) => _CameraTranslation(
    sourceLanguage: row['sourceLanguage'] as String,
    targetLanguage: row['targetLanguage'] as String,
    originalText: row['originalText'] as String,
    translatedText: row['translatedText'] as String,
    saved: true,
    createdAt: row['createdAt'] as String?,
  );
  final String sourceLanguage, targetLanguage, originalText, translatedText;
  final String clientRequestId;
  bool saved;
  String? createdAt;

  Json get payload => {
    'clientRequestId': clientRequestId,
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'originalText': originalText,
    'translatedText': translatedText,
  };

  static String _requestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class _LiveCameraScreenState extends State<LiveCameraScreen>
    with WidgetsBindingObserver {
  static const _interval = Duration(milliseconds: 1400);
  late final _service = widget.translationService ?? TranslationService();
  CameraController? _camera;
  Future<void>? _initializing, _processing;
  Future<void> _cleanup = Future.value();
  Timer? _timer;
  bool _cleanupPending = false, _cleanupFailed = false;
  _CameraTranslation? _result;
  String? _error;
  String _status = 'Đang mở camera…', _lastRecognized = '';
  bool _foreground = true, _running = true, _closing = false;
  bool _saving = false, _opening = false, _canPop = false;
  int _generation = 0;

  bool get _canScan =>
      mounted && !_closing && _foreground && _running && _camera != null;
  bool get _actionBusy => _saving || _opening || _closing;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_openCamera());
  }

  Future<void> _openCamera() async {
    if (!mounted ||
        _closing ||
        !_foreground ||
        !_running ||
        _cleanupPending ||
        _cleanupFailed ||
        _initializing != null ||
        _camera != null) {
      return;
    }
    final task = _initializeCamera();
    _initializing = task;
    try {
      await task;
    } finally {
      _initializing = null;
      if (mounted &&
          !_closing &&
          _foreground &&
          _running &&
          _camera == null &&
          _error == null) {
        unawaited(_openCamera());
      }
    }
  }

  Future<void> _initializeCamera() async {
    CameraController? next;
    setState(() {
      _error = null;
      _status = 'Đang mở camera…';
    });
    try {
      await _cleanup.timeout(const Duration(seconds: 4));
      if (!mounted || _closing || !_foreground || !_running) return;
      if (defaultTargetPlatform != TargetPlatform.android) {
        throw const ApiException(
          'CAMERA_PLATFORM',
          'Dịch trực tiếp qua camera hiện hỗ trợ thiết bị Android.',
        );
      }
      final cameras = await availableCameras().timeout(
        const Duration(seconds: 5),
      );
      if (cameras.isEmpty) throw CameraException('NoCamera', '');
      final selected =
          cameras
              .where(
                (camera) => camera.lensDirection == CameraLensDirection.back,
              )
              .firstOrNull ??
          cameras.first;
      next = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await next.initialize().timeout(const Duration(seconds: 8));
      await next
          .setFlashMode(FlashMode.off)
          .timeout(const Duration(seconds: 3));
      if (!mounted || _closing || !_foreground || !_running) return;
      final camera = next;
      _camera = camera;
      next = null;
      setState(() => _status = 'Hướng camera vào chữ cần dịch');
      await camera
          .startImageStream((image) => _onFrame(image, camera))
          .timeout(const Duration(seconds: 5));
    } on CameraException catch (error) {
      if (mounted && !_closing) {
        setState(() {
          _running = false;
          _error =
              error.code.contains('AccessDenied') ||
                  error.code.contains('Restricted')
              ? 'Hãy cho phép sử dụng camera trong cài đặt thiết bị rồi thử lại.'
              : 'Chưa mở được camera. Hãy kiểm tra camera trên thiết bị rồi thử lại.';
        });
      }
    } catch (error) {
      if (mounted && !_closing) {
        setState(() {
          _running = false;
          _error = error is ApiException
              ? error.message
              : 'Chưa mở được camera. Vui lòng thử lại.';
        });
      }
    } finally {
      if (!_running && _camera != null) await _releaseCamera();
      if (next != null && !identical(_camera, next)) {
        await _closeController(next);
      }
    }
  }

  void _onFrame(CameraImage image, CameraController camera) {
    if (!_canScan ||
        !identical(camera, _camera) ||
        _processing != null ||
        _timer?.isActive == true) {
      return;
    }
    unawaited(_sample(image, camera));
  }

  Future<void> _sample(CameraImage image, CameraController camera) async {
    final task = _processFrame(image, camera, _generation);
    _processing = task;
    try {
      await task;
    } finally {
      _processing = null;
      if (_canScan) _timer = Timer(_interval, () => _timer = null);
    }
  }

  bool _current(int generation) => _canScan && generation == _generation;

  Future<void> _processFrame(
    CameraImage image,
    CameraController camera,
    int generation,
  ) async {
    try {
      if (!_current(generation)) return;
      final input = cameraFrameInput(
        image,
        camera.description,
        camera.value.deviceOrientation,
      );
      setState(() => _status = 'Đang đọc chữ…');
      final original = (await _service.recognizeFrame(
        input,
        sourceLanguage: widget.sourceLanguage,
      )).trim();
      if (!_current(generation)) return;
      if (original.isEmpty) return;
      if (original.length > 6000) {
        setState(() => _status = 'Hướng camera vào đoạn chữ ngắn hơn');
        return;
      }
      if (original == _lastRecognized && _result != null) {
        setState(() => _status = 'Đang dịch trực tiếp');
        return;
      }
      setState(() => _status = 'Đang dịch…');
      final translated = (await _service.translate(
        original,
        sourceLanguage: widget.sourceLanguage,
        targetLanguage: widget.targetLanguage,
      )).trim();
      if (!_current(generation)) return;
      if (translated.isEmpty || translated.length > 6000) {
        setState(() => _status = 'Hướng camera vào đoạn chữ ngắn hơn để dịch');
        return;
      }
      setState(() {
        _lastRecognized = original;
        _result = _CameraTranslation(
          sourceLanguage: widget.sourceLanguage,
          targetLanguage: widget.targetLanguage,
          originalText: original,
          translatedText: translated,
        );
        _error = null;
        _status = 'Đang dịch trực tiếp';
      });
    } catch (error) {
      if (!_current(generation)) return;
      if (error is ApiException && error.code == 'OCR_EMPTY') {
        setState(
          () => _status =
              'Chưa thấy chữ. Giữ camera ổn định và chọn nơi đủ sáng.',
        );
      } else {
        setState(() {
          _error = errorMessage(error);
          _running = false;
        });
        unawaited(_releaseCamera());
      }
    }
  }

  Future<void> _releaseCamera() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    final old = _camera;
    _camera = null;
    return old == null ? Future.value() : _closeController(old);
  }

  Future<void> _closeController(CameraController old) {
    _cleanupPending = true;
    _cleanup = _cleanup.then((_) async {
      try {
        try {
          if (old.value.isStreamingImages) await old.stopImageStream();
        } finally {
          await old.dispose();
        }
      } catch (_) {
        _cleanupFailed = true;
        if (mounted && !_closing) {
          setState(() {
            _running = false;
            _error = 'Chưa dừng được camera hoàn toàn. Hãy đóng màn hình này và thử lại sau.';
          });
        }
      } finally {
        _cleanupPending = false;
        if (mounted &&
            !_closing &&
            _foreground &&
            _running &&
            !_cleanupFailed &&
            _camera == null &&
            _error == null) {
          unawaited(_openCamera());
        }
      }
    });
    return _cleanup.timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        if (mounted && !_closing) {
          setState(() {
            _running = false;
            _error = 'Camera đang phản hồi chậm. Hãy đợi một lát trước khi tiếp tục.';
          });
        }
      },
    );
  }

  Future<void> _pause() async {
    if (mounted) {
      setState(() {
        _running = false;
        _status = 'Đã tạm dừng camera';
      });
    }
    await _releaseCamera();
  }

  void _resume() {
    if (_actionBusy) return;
    if (_cleanupPending || _cleanupFailed) {
      showMessage(
        context,
        'Camera chưa dừng hoàn toàn. Hãy đợi một lát rồi thử lại.',
      );
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    unawaited(_openCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (_running) unawaited(_openCamera());
    } else {
      _foreground = false;
      unawaited(_releaseCamera());
    }
  }

  Future<void> _leave() async {
    if (_closing) return;
    _closing = true;
    _running = false;
    await _releaseCamera();
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _closing = true;
    _running = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeResources());
    super.dispose();
  }

  Future<void> _disposeResources() async {
    await _releaseCamera();
    await _initializing;
    await _processing;
    await _service.dispose();
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || result.saved || _actionBusy) return;
    final api = context.read<SessionController>().api;
    setState(() => _saving = true);
    await _pause();
    try {
      final saved = await api.post('/camera-translations', result.payload);
      if (saved is! Map || saved['id'] is! String) {
        throw const FormatException();
      }
      result.saved = true;
      result.createdAt = saved['createdAt'] as String?;
      if (mounted) {
        setState(() {});
        showMessage(context, 'Đã lưu bản dịch.');
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _history() async {
    if (_actionBusy) return;
    final api = context.read<SessionController>().api;
    setState(() => _opening = true);
    try {
      await _pause();
      if (!mounted) return;
      final selected = await showModalBottomSheet<_CameraTranslation>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _CameraHistorySheet(api: api),
      );
      if (selected != null && mounted) {
        setState(() {
          _result = selected;
          _lastRecognized = '';
          _status = 'Đang xem bản dịch đã lưu';
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _handover() async {
    final result = _result;
    if (result == null || _actionBusy) return;
    setState(() => _opening = true);
    await _pause();
    if (!mounted) return;
    try {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => HandoverComposer(
            initial: HandoverDraft(
              originalText: result.originalText,
              translatedText: result.translatedText,
              sourceLanguage: result.sourceLanguage,
              targetLanguage: result.targetLanguage,
            ),
          ),
        ),
      );
      if (changed == true && mounted) {
        showMessage(context, 'Đã lưu phiếu bàn giao.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _leave),
          title: const Text('Dịch trực tiếp'),
          actions: [
            IconButton(
              tooltip: 'Bản dịch đã lưu',
              onPressed: _actionBusy ? null : _history,
              icon: const Icon(Icons.history),
            ),
          ],
        ),
        body: AppPage(
          children: [
            PageHeading(
              title: 'Hướng camera vào chữ',
              subtitle:
                  '${translationLanguages[widget.sourceLanguage]} → ${translationLanguages[widget.targetLanguage]}',
            ),
            if (_error != null) Notice(_error!, isError: true),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 280,
                child: ColoredBox(
                  color: Colors.black87,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_camera?.value.isInitialized == true)
                        CameraPreview(_camera!)
                      else
                        const Center(
                          child: Icon(
                            Icons.camera_alt_outlined,
                            color: Colors.white54,
                            size: 48,
                          ),
                        ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .65),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              _status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('toggle-live-camera'),
              onPressed: _actionBusy
                  ? null
                  : _running
                  ? _pause
                  : _resume,
              icon: Icon(_running ? Icons.pause : Icons.play_arrow),
              label: Text(_running ? 'Tạm dừng' : 'Tiếp tục dịch'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Hình ảnh được đọc và dịch trên thiết bị, không tạo tệp ảnh. Chỉ khi bấm Lưu, nội dung chữ và bản dịch mới được lưu vào tài khoản.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            if (result == null)
              const EmptyState(
                title: 'Chưa có bản dịch',
                message: 'Giữ camera ổn định, hướng vào chữ rõ nét và đủ sáng.',
                icon: Icons.translate,
              )
            else
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      result.saved ? 'Bản dịch đã lưu' : 'Kết quả gần nhất',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      translationLanguages[result.sourceLanguage] ?? 'Bản gốc',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      result.originalText,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const Divider(height: 24),
                    Text(
                      translationLanguages[result.targetLanguage] ?? 'Bản dịch',
                      style: const TextStyle(
                        color: AppColors.pink,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      result.translatedText,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const GoogleTranslationAttribution(),
                    const Text(
                      'Đối chiếu bản gốc trước khi sử dụng.',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: result.translatedText),
                            );
                            if (context.mounted) {
                              showMessage(context, 'Đã sao chép bản dịch.');
                            }
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Sao chép'),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('save-camera-translation'),
                          onPressed: _actionBusy || result.saved ? null : _save,
                          icon: Icon(
                            result.saved
                                ? Icons.check
                                : Icons.bookmark_add_outlined,
                          ),
                          label: Text(
                            _saving
                                ? 'Đang lưu…'
                                : result.saved
                                ? 'Đã lưu'
                                : 'Lưu bản dịch',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _actionBusy ? null : _handover,
                          icon: const Icon(Icons.playlist_add_check),
                          label: const Text('Tạo bàn giao'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraHistorySheet extends StatefulWidget {
  const _CameraHistorySheet({required this.api});
  final ApiClient api;
  @override
  State<_CameraHistorySheet> createState() => _CameraHistorySheetState();
}

class _CameraHistorySheetState extends State<_CameraHistorySheet> {
  late Future<List<Json>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.api
        .get('/camera-translations')
        .then(
          (value) =>
              (value as List).map((row) => Json.from(row as Map)).toList(),
        );
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .8,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bản dịch đã lưu',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Chọn một bản để xem, sao chép hoặc tạo bàn giao.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AsyncPanel<List<Json>>(
                future: _future,
                onRetry: () => setState(_load),
                builder: (rows) => rows.isEmpty
                    ? const EmptyState(
                        title: 'Chưa lưu bản dịch nào',
                        message: 'Bấm Lưu bản dịch sau khi dịch qua camera để xem lại ở đây.',
                        icon: Icons.bookmarks_outlined,
                      )
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              row['originalText'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${translationLanguages[row['sourceLanguage']]} → ${translationLanguages[row['targetLanguage']]} · ${dateText(row['createdAt'])} ${timeText(row['createdAt'])}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(
                              context,
                              _CameraTranslation.fromJson(row),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
