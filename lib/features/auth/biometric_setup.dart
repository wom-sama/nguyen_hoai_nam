import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../ui/components.dart';
import '../face/face_capture.dart';
import 'device_biometrics.dart';

class BiometricSetupGate extends StatefulWidget {
  const BiometricSetupGate({super.key, required this.child});
  final Widget child;
  @override
  State<BiometricSetupGate> createState() => _BiometricSetupGateState();
}

class _BiometricSetupGateState extends State<BiometricSetupGate> {
  final _biometrics = DeviceBiometrics();
  bool _loading = true, _ready = false, _working = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final session = context.read<SessionController>();
      final face = await session.api.get('/face/status') as Map;
      final ready =
          face['enrolled'] == true ||
          await _biometrics.isRegistered(session.api, session.user!.username);
      if (mounted) setState(() => _ready = ready);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enroll({required bool face}) async {
    if (_working) return;
    final session = context.read<SessionController>();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (face) {
        final image = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => const FaceCaptureScreen(enrolling: true),
          ),
        );
        if (image == null || !mounted) return;
        await session.api.post('/face/enroll', {'imageBase64': image});
      } else {
        await _biometrics.enroll(session.api, session.user!.username);
      }
      if (mounted) await _check();
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_ready) return widget.child;
    return Scaffold(
      body: AppPage(
        children: [
          const PageHeading(
            eyebrow: 'BẢO VỆ TÀI KHOẢN',
            title: 'Đăng ký đăng nhập nhanh',
            subtitle: 'Chọn khuôn mặt hoặc vân tay. Những lần sau bạn có thể đăng nhập không cần OTP.',
          ),
          if (_error != null) Notice(_error!, isError: true),
          FilledButton.icon(
            onPressed: _working ? null : () => _enroll(face: true),
            icon: const Icon(Icons.face_retouching_natural),
            label: const Text('Đăng ký khuôn mặt'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _working ? null : () => _enroll(face: false),
            icon: const Icon(Icons.fingerprint),
            label: const Text('Đăng ký vân tay thiết bị'),
          ),
          if (_working)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          TextButton(
            onPressed: _working ? null : _check,
            child: const Text('Kiểm tra lại'),
          ),
          TextButton(
            onPressed: _working
                ? null
                : context.read<SessionController>().logout,
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}
