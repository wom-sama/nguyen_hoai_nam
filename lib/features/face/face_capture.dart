import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../ui/components.dart';
import '../../ui/theme.dart';

class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key, required this.enrolling});
  final bool enrolling;
  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  String? _error;
  bool _busy = false;
  bool _initializing = false, _foreground = true;
  Future<void> _cleanup = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      await old?.dispose();
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
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      if (!mounted || !_foreground) return;
      _camera = next;
      setState(() => _error = null);
    } on CameraException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code.contains('AccessDenied')
              ? 'Cần quyền camera để chụp khuôn mặt. Bạn có thể quay lại đăng nhập bằng mật khẩu và OTP.'
              : 'Chưa mở được camera. Kiểm tra cấu hình camera của giả lập rồi thử lại.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Chưa có camera khả dụng. Hãy cấu hình camera cho giả lập rồi thử lại.',
        );
      }
    } finally {
      if (next != null && !identical(_camera, next)) await next.dispose();
      if (mounted) {
        setState(() => _initializing = false);
        if (_foreground && _camera == null && _error == null) {
          unawaited(_initialize());
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _foreground = false;
      final old = _camera;
      _camera = null;
      if (old != null) _cleanup = _cleanup.then((_) => old.dispose());
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
    if (old != null) unawaited(_cleanup.then((_) => old.dispose()));
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    XFile? picture;
    try {
      picture = await camera.takePicture();
      final bytes = await picture.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) throw Exception('IMAGE_TOO_LARGE');
      if (mounted) Navigator.pop(context, base64Encode(bytes));
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Chưa chụp được ảnh hợp lệ. Vui lòng thử lại.');
        setState(() => _busy = false);
      }
    } finally {
      if (picture != null) {
        final file = File(picture.path);
        if (await file.exists()) await file.delete();
      }
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
        PageHeading(
          eyebrow: 'CAMERA',
          title: 'Chụp khuôn mặt',
          subtitle: widget.enrolling
              ? 'Đặt mặt trong khung, nhìn thẳng và chọn nơi đủ sáng.'
              : 'Đặt mặt trong khung. Sau khi khớp, xác nhận mã gửi qua email.',
        ),
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
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed:
              _camera?.value.isInitialized == true && !_busy && !_initializing
              ? _capture
              : null,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(_busy ? 'Đang chụp…' : 'Chụp và tiếp tục'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Nhìn thẳng, chỉ một khuôn mặt, đủ sáng và không che mắt.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}
