import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'components.dart';
import 'ledger.dart';
import 'theme.dart';

class FirstRunController extends ChangeNotifier {
  static const storageKey = 'hn_quick_guide_seen_v1';
  final _storage = const FlutterSecureStorage();
  bool completed = false;
  String? storageWarning;

  Future<void> load() async {
    try {
      completed = await _storage.read(key: storageKey) == '1';
    } on PlatformException {
      storageWarning = 'Không đọc được tùy chọn hướng dẫn trên thiết bị.';
    }
  }

  Future<void> complete() async {
    try {
      await _storage.write(key: storageKey, value: '1');
    } on PlatformException {
      storageWarning =
          'Không lưu được tùy chọn. Hướng dẫn có thể hiện lại lần sau.';
    }
    completed = true;
    notifyListeners();
  }
}

class FirstRunGate extends StatelessWidget {
  const FirstRunGate({
    super.key,
    required this.controller,
    required this.child,
  });
  final FirstRunController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => controller.completed
        ? child
        : QuickGuideScreen(
            warning: controller.storageWarning,
            onComplete: () async {
              await controller.complete();
              if (context.mounted && controller.storageWarning != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(controller.storageWarning!)),
                );
              }
            },
          ),
  );
}

Future<void> showQuickGuide(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => QuickGuideScreen(
          replay: true,
          onComplete: () async {
            Navigator.of(routeContext).pop();
          },
        ),
      ),
    );

class QuickGuideScreen extends StatefulWidget {
  const QuickGuideScreen({
    super.key,
    required this.onComplete,
    this.replay = false,
    this.warning,
  });
  final Future<void> Function() onComplete;
  final bool replay;
  final String? warning;
  @override
  State<QuickGuideScreen> createState() => _QuickGuideScreenState();
}

class _QuickGuideScreenState extends State<QuickGuideScreen> {
  int _step = 0;
  bool _saving = false;
  static const _steps = [
    (
      label: 'CA LÀM',
      title: 'Vào ca. Ra ca.',
      icon: Icons.schedule_outlined,
      body: 'Mở ca được phân, bật vị trí và chấm công. Cần sửa giờ? Gửi đơn để quản lý duyệt.',
      detail: 'Giờ gốc được giữ để đối soát.',
    ),
    (
      label: 'BÀN GIAO',
      title: 'Đọc kỹ. Xác nhận đúng.',
      icon: Icons.fact_check_outlined,
      body: 'Đối chiếu bản gốc với bản dịch, rồi nhập lại dữ kiện quan trọng để xác nhận đã hiểu.',
      detail: 'Phiếu thay đổi sẽ cần xác nhận lại.',
    ),
    (
      label: 'KẾT NỐI',
      title: 'Ảnh, lời nói và khuôn mặt.',
      icon: Icons.translate_outlined,
      body: 'Dịch ảnh hoặc giọng nói giữa Việt, Anh và Trung. Đăng ký khuôn mặt trong Tài khoản; đăng nhập vẫn cần OTP email.',
      detail: 'Camera, mic và vị trí chỉ dùng khi bạn chủ động bật.',
    ),
  ];

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.onComplete();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    return Scaffold(
      body: AppPage(
        children: [
          Row(
            children: [
              const HnMark(size: 38),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nguyễn Hoài Nam',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _finish,
                child: Text(widget.replay ? 'Đóng' : 'Bỏ qua'),
              ),
            ],
          ),
          if (widget.warning != null) Notice(widget.warning!),
          const SizedBox(height: 24),
          Row(
            children: [
              for (int index = 0; index < _steps.length; index++)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                    color: index <= _step ? AppColors.pink : AppColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            '${_step + 1} / 3 · ${step.label}',
            style: const TextStyle(
              color: AppColors.pink,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            child: _GuideIllustration(
              key: ValueKey(_step),
              step: _step,
              icon: step.icon,
            ),
          ),
          const SizedBox(height: 26),
          Text(step.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 14),
          Text(step.body, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          Text(
            step.detail,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving
                ? null
                : () => _step == 2 ? _finish() : setState(() => _step++),
            child: Text(
              _saving
                  ? 'Đang mở…'
                  : _step == 2
                  ? (widget.replay ? 'Xong' : 'Bắt đầu')
                  : 'Tiếp theo',
            ),
          ),
          if (_step > 0)
            TextButton(
              onPressed: _saving ? null : () => setState(() => _step--),
              child: const Text('Quay lại'),
            ),
        ],
      ),
    );
  }
}

class _GuideIllustration extends StatelessWidget {
  const _GuideIllustration({super.key, required this.step, required this.icon});
  final int step;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 170,
      child: Center(
        child: Transform.rotate(
          angle: step == 1 ? -.035 : .025,
          child: Container(
            width: 252,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppColors.pink, size: 32),
                    const Spacer(),
                    Text(
                      '0${step + 1}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                for (int line = 0; line < 3; line++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        if (step == 1)
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: AppColors.green,
                            ),
                          ),
                        Expanded(
                          child: Container(
                            height: 2,
                            margin: EdgeInsets.only(right: line == 2 ? 48 : 0),
                            color: line == 0
                                ? AppColors.palePink
                                : AppColors.line,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
