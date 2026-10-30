import 'dart:convert';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../translation/camera_frame.dart';
import 'face_frame.dart';
import 'face_scan.dart';

class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({
    super.key,
    required this.enrolling,
    this.scanner,
    this.scanTime,
    this.encodeFrame,
  });
  final bool enrolling;
  final FaceScanner? scanner;
  final Duration Function()? scanTime;
  final FaceScanEncoder? encodeFrame;
  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  late final FaceScanner _scanner;
  final FaceScanGate _gate = FaceScanGate();
  final Stopwatch _watch = Stopwatch()..start();
  FaceScanProgress _progress = const FaceScanProgress(FaceScanStatus.searching);
  DeviceOrientation? _orientation;
  Duration? _lastAnalysisAt;
  Future<void>? _analysis;
  bool _analyzing = false, _completed = false;
  int _epoch = 0;
  String? _error;
  bool _busy = false;
  bool _initializing = false, _foreground = true;
  Future<void> _cleanup = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanner = widget.scanner ?? MlKitFaceScanner();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing || !mounted || !_foreground) return;
    setState(() {
      _initializing = true;
      _error = null;
    });
    CameraController? next;
    try {
      await _cleanup;
      final old = _camera;
      _camera = null;
      _resetScan();
      if (old != null) await _closeCamera(old);
      if (!mounted || !_foreground) return;
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('NO_CAMERA');
      final selected =
          cameras
              .where((c) => c.lensDirection == CameraLensDirection.front)
              .firstOrNull ??
          cameras.first;
      next = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await next.initialize();
      if (!mounted || !_foreground) return;
      _camera = next;
      final active = next;
      _orientation = active.value.deviceOrientation;
      active.addListener(() {
        if (!mounted || _completed || !identical(_camera, active)) return;
        final orientation = active.value.deviceOrientation;
        if (_orientation != orientation) {
          setState(() {
            _resetScan();
            _orientation = orientation;
          });
        }
      });
      await active.startImageStream((frame) {
        _onFrame(frame, active);
      });
      setState(() => _error = null);
    } on CameraException catch (e) {
      if (identical(_camera, next)) _camera = null;
      if (mounted) {
        setState(
          () => _error = e.code.contains('AccessDenied')
              ? 'Cần quyền camera để chụp khuôn mặt. Bạn có thể quay lại đăng nhập bằng mật khẩu và OTP.'
              : 'Chưa mở được camera. Hãy kiểm tra quyền camera rồi thử lại.',
        );
      }
    } catch (e) {
      if (identical(_camera, next)) _camera = null;
      if (mounted) {
        setState(() => _error = 'Chưa mở được camera. Vui lòng thử lại.');
      }
    } finally {
      if (next != null && !identical(_camera, next)) await _closeCamera(next);
      if (mounted) {
        setState(() => _initializing = false);
        if (_foreground && _camera == null && _error == null) {
          unawaited(_initialize());
        }
      }
    }
  }

  Future<void> _closeCamera(CameraController camera) async {
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
    } finally {
      try {
        await _analysis;
      } finally {
        await camera.dispose();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _foreground = false;
      _resetScan();
      final old = _camera;
      _camera = null;
      if (old != null) _cleanup = _cleanup.then((_) => _closeCamera(old));
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _initialize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final old = _camera;
    _camera = null;
    _foreground = false;
    _completed = true;
    _resetScan();
    _watch.stop();
    unawaited(_disposeResources(old));
    super.dispose();
  }

  Future<void> _disposeResources(CameraController? old) async {
    try {
      await _cleanup;
      if (old != null) await _closeCamera(old);
    } finally {
      await _analysis;
      await _scanner.close();
    }
  }

  void _resetScan() {
    _epoch++;
    _gate.reset();
    _lastAnalysisAt = null;
    _orientation = null;
    _progress = const FaceScanProgress(FaceScanStatus.searching);
  }

  void _onFrame(CameraImage frame, CameraController camera) {
    if (!mounted || !_foreground || _completed || !identical(_camera, camera)) {
      return;
    }
    final orientation = camera.value.deviceOrientation;
    if (_orientation != null && orientation != _orientation) {
      setState(_resetScan);
    }
    _orientation = orientation;
    if (_initializing || _analyzing || _busy || _error != null) return;
    final at = widget.scanTime?.call() ?? _watch.elapsed;
    if (_lastAnalysisAt != null &&
        at - _lastAnalysisAt! < const Duration(milliseconds: 350)) {
      return;
    }
    _lastAnalysisAt = at;
    try {
      // Own the NV21 bytes before awaiting native analysis. The exact accepted
      // buffer is encoded; a later camera frame can never replace it.
      final input = cameraFrameInput(frame, camera.description, orientation);
      _analyzing = true;
      final drained = Completer<void>();
      _analysis = drained.future;
      unawaited(
        _analyze(input, camera, orientation, at, _epoch).whenComplete(() {
          _analyzing = false;
          _analysis = null;
          drained.complete();
        }),
      );
    } catch (_) {
      setState(
        () => _error = 'Chưa đọc được hình ảnh camera để quét. Hãy thử lại.',
      );
    }
  }

  Future<void> _analyze(
    InputImage input,
    CameraController camera,
    DeviceOrientation orientation,
    Duration at,
    int epoch,
  ) async {
    bool current() =>
        mounted &&
        _foreground &&
        !_completed &&
        epoch == _epoch &&
        identical(_camera, camera) &&
        camera.value.deviceOrientation == orientation;
    try {
      final faces = await _scanner.scan(input);
      if (!current()) return;
      final progress = _gate.observe(
        faces,
        size: uprightFaceFrameSize(input),
        at: at,
      );
      setState(() => _progress = progress);
      if (!progress.ready) return;
      setState(() => _busy = true);
      final bytes = await (widget.encodeFrame ?? faceFramePng)(input);
      if (bytes.length > 2 * 1024 * 1024) throw Exception('IMAGE_TOO_LARGE');
      if (mounted && current()) {
        _completed = true;
        Navigator.pop(context, base64Encode(bytes));
      }
    } catch (e) {
      if (current()) {
        _gate.reset();
        setState(() => _error = 'Chưa quét được khuôn mặt. Hãy thử lại.');
      }
    } finally {
      if (mounted && !_completed) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.enrolling ? 'Đăng ký khuôn mặt' : 'Xác thực khuôn mặt',
      ),
    ),
    body: AppPage(
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _busy ? 'Đang chuẩn bị ảnh…' : _scanMessage(_progress.status),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Hủy quét'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _busy ? 1 : _progress.fraction,
          minHeight: 4,
          semanticsLabel:
              'Giữ yên ${_progress.stableFrames.clamp(0, 3)} trên 3 khung hình',
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Notice(_error!, isError: true),
          OutlinedButton.icon(
            onPressed: _initializing || _busy ? null : _initialize,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử mở lại camera'),
          ),
        ] else
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: _camera?.value.isInitialized == true
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_camera!),
                        Center(
                          child: FractionallySizedBox(
                            widthFactor: .7,
                            heightFactor: .72,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                                borderRadius: const BorderRadius.all(
                                  Radius.elliptical(150, 200),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const ColoredBox(
                      color: AppColors.palePink,
                      child: Center(child: CircularProgressIndicator()),
                    ),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Chỉ một khuôn mặt, đủ sáng và không che mắt. Quét tự động không kiểm tra chống giả mạo.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

String _scanMessage(FaceScanStatus status) => switch (status) {
  FaceScanStatus.searching => 'Đưa khuôn mặt vào khung',
  FaceScanStatus.multiple => 'Chỉ một người trong khung',
  FaceScanStatus.tooSmall => 'Đưa khuôn mặt gần hơn',
  FaceScanStatus.tooClose => 'Lùi nhẹ để thấy trọn khuôn mặt',
  FaceScanStatus.offCenter => 'Đưa khuôn mặt vào giữa khung',
  FaceScanStatus.notFrontal => 'Nhìn thẳng và giữ đầu ngay',
  FaceScanStatus.unclear => 'Giữ mắt rõ trong khung, chọn nơi đủ sáng',
  FaceScanStatus.moving => 'Giữ yên để quét lại',
  FaceScanStatus.hold => 'Giữ yên, ảnh sẽ tự chụp',
  FaceScanStatus.ready => 'Đã có khung hình phù hợp',
};
