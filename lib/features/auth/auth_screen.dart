import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../../ui/ledger.dart';
import '../face/face_capture.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController(),
      _email = TextEditingController(),
      _confirm = TextEditingController();
  bool _register = false, _obscure = true;
  @override
  void dispose() {
    for (final c in [_username, _password, _name, _email, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final session = context.read<SessionController>();
    if (_register) {
      await session.register({
        'fullName': _name.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
      });
    } else {
      await session.login(_username.text.trim(), _password.text);
    }
    _password.clear();
    _confirm.clear();
  }

  Future<void> _face() async {
    if (!RegExp(r'^[a-zA-Z0-9_.]{3,32}$').hasMatch(_username.text.trim())) {
      showMessage(context, 'Nhập tên đăng nhập trước khi xác thực khuôn mặt.');
      return;
    }
    final session = context.read<SessionController>();
    final image = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const FaceCaptureScreen(enrolling: false),
      ),
    );
    if (image != null) await session.faceLogin(_username.text.trim(), image);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Scaffold(
      body: AppPage(
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              const HnMark(size: 46),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nguyễn Hoài Nam',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          PageHeading(
            eyebrow: 'CHẤM CÔNG / HN',
            title: _register ? 'Tạo tài khoản' : 'Đăng nhập',
            subtitle: _register
                ? 'Xác thực email rồi chờ quản trị viên duyệt tài khoản.'
                : null,
          ),
          if (session.error != null) Notice(session.error!, isError: true),
          LedgerSheet(
            label: _register ? 'ĐĂNG KÝ NHÂN VIÊN' : 'ĐĂNG NHẬP',
            reference: 'XÁC THỰC EMAIL',
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Họ và tên',
                        ),
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v?.trim().length ?? 0) < 2
                            ? 'Nhập họ và tên của bạn.'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                        autofillHints: const [AutofillHints.email],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(v?.trim() ?? '')
                            ? 'Nhập email hợp lệ.'
                            : null,
                      ),
                      const SizedBox(height: 18),
                    ],
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: 'Tên đăng nhập',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      autofillHints: const [AutofillHints.username],
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          !RegExp(r'^[a-zA-Z0-9_.]{3,32}$')
                              .hasMatch(v?.trim() ?? '')
                          ? 'Dùng 3–32 chữ không dấu, số, dấu chấm hoặc gạch dưới.'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      textInputAction: _register
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: (_) => _register ? null : _submit(),
                      validator: (v) => (v?.length ?? 0) < 10
                          ? 'Mật khẩu cần ít nhất 10 ký tự.'
                          : null,
                    ),
                    if (_register) ...[
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _confirm,
                        obscureText: _obscure,
                        decoration: const InputDecoration(
                          labelText: 'Nhập lại mật khẩu',
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => v != _password.text
                            ? 'Hai mật khẩu chưa khớp.'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: session.busy ? null : _submit,
                      child: session.busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? 'Tạo tài khoản' : 'Tiếp tục'),
                    ),
                    if (!_register) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: session.busy ? null : _face,
                        icon: const Icon(Icons.face_retouching_natural),
                        label: const Text('Đăng nhập bằng khuôn mặt'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: session.busy
                ? null
                : () => setState(() {
                    _register = !_register;
                    _form.currentState?.reset();
                  }),
            child: Text(
              _register ? 'Đã có tài khoản? Đăng nhập' : 'Đăng ký tài khoản',
            ),
          ),
        ],
      ),
    );
  }
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  Timer? _ticker;
  DateTime? _resendAt;
  String? _challengeId;
  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>(),
        challenge = session.challenge!;
    if (_challengeId != challenge.id) {
      _challengeId = challenge.id;
      _resendAt = DateTime.now().add(
        Duration(seconds: challenge.retryAfterSeconds),
      );
    }
    final wait = (_resendAt?.difference(DateTime.now()).inSeconds ?? 0).clamp(
      0,
      600,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) session.cancelChallenge();
      },
      child: Scaffold(
        body: AppPage(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: session.cancelChallenge,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Đổi cách đăng nhập'),
              ),
            ),
            const SizedBox(height: 16),
            const Icon(
              Icons.mark_email_read_outlined,
              size: 40,
              color: AppColors.pink,
            ),
            const SizedBox(height: 16),
            PageHeading(
              eyebrow: 'XÁC THỰC EMAIL',
              title: 'Xác nhận OTP',
              subtitle: 'Mã 6 chữ số gửi đến ${challenge.maskedEmail}.',
            ),
            if (session.error != null) Notice(session.error!, isError: true),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 9,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Mã OTP',
                      counterText: '',
                    ),
                    onSubmitted: (_) => session.verifyOtp(_code.text),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: session.busy
                        ? null
                        : () => session.verifyOtp(_code.text),
                    child: Text(
                      session.busy ? 'Đang xác thực…' : 'Xác nhận và tiếp tục',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: session.busy || wait > 0
                        ? null
                        : () async {
                            if (await session.resendOtp() && mounted) {
                              _code.clear();
                              setState(
                                () => _resendAt = DateTime.now().add(
                                  const Duration(seconds: 60),
                                ),
                              );
                            }
                          },
                    child: Text(
                      wait > 0 ? 'Gửi lại sau $wait giây' : 'Gửi lại mã OTP',
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Mã hết hạn lúc ${timeText(challenge.expiresAt.toIso8601String())}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceUnavailableScreen extends StatelessWidget {
  const ServiceUnavailableScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: AppPage(
      children: [
        SizedBox(height: 24),
        Align(alignment: Alignment.centerLeft, child: HnMark(size: 46)),
        SizedBox(height: 24),
        PageHeading(
          title: 'Ứng dụng chưa sẵn sàng',
          subtitle: 'Vui lòng cập nhật bản ứng dụng hoặc liên hệ quản trị viên để được hỗ trợ.',
        ),
      ],
    ),
  );
}

class PendingAccountScreen extends StatelessWidget {
  const PendingAccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>(), user = session.user!;
    final suspended = user.status == 'suspended';
    return Scaffold(
      body: AppPage(
        children: [
          const SizedBox(height: 35),
          Icon(
            suspended ? Icons.lock_clock_outlined : Icons.hourglass_top_rounded,
            size: 55,
            color: AppColors.pink,
          ),
          const SizedBox(height: 28),
          PageHeading(
            eyebrow: 'TRẠNG THÁI TÀI KHOẢN',
            title: suspended ? 'Tài khoản tạm dừng' : 'Chờ duyệt tài khoản',
            subtitle: suspended
                ? 'Liên hệ quản trị viên để kiểm tra trạng thái tài khoản.'
                : 'Quản trị viên cần duyệt và gắn bạn với chi nhánh trước khi chấm công.',
          ),
          if (session.error != null) Notice(session.error!, isError: true),
          Surface(
            child: Column(
              children: [
                Text(
                  user.fullName,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                InfoRow('Tên đăng nhập', user.username),
                InfoRow('Email', user.email),
                const SizedBox(height: 12),
                StatusPill(user.status),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: session.busy ? null : session.refreshProfile,
            icon: const Icon(Icons.refresh),
            label: const Text('Kiểm tra trạng thái'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: session.busy ? null : session.logout,
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}
