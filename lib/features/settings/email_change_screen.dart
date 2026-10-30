import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';

String _emailStatus(String? status) => switch (status) {
  'pending_verification' => 'Chờ xác nhận hai email',
  'pending_approval' => 'Chờ quản trị viên khác duyệt',
  'approved' => 'Đã duyệt',
  'rejected' => 'Đã từ chối',
  'expired' => 'Yêu cầu đã hết hạn',
  'invalidated' => 'Yêu cầu không còn hiệu lực',
  _ => 'Chưa có yêu cầu đổi email',
};

class EmailChangeScreen extends StatefulWidget {
  const EmailChangeScreen({super.key});
  @override
  State<EmailChangeScreen> createState() => _EmailChangeScreenState();
}

class _EmailChangeScreenState extends State<EmailChangeScreen> {
  final _emailForm = GlobalKey<FormState>(), _codeForm = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _old = TextEditingController(),
      _new = TextEditingController();
  Json? _request;
  bool _loading = true, _working = false;
  String? _error;
  DateTime? _retryAt;
  Timer? _timer;
  late final String? _userId;
  @override
  void initState() {
    super.initState();
    _userId = context.read<SessionController>().user?.id;
    unawaited(_load());
  }

  bool get _current =>
      mounted && context.read<SessionController>().user?.id == _userId;
  int get _remaining {
    final seconds = _retryAt?.difference(DateTime.now()).inSeconds ?? 0;
    return seconds < 0 ? 0 : seconds;
  }

  void _apply(Json? value) {
    _request = value;
    final retry = (value?['retryAfterSeconds'] as num?)?.toInt() ?? 0;
    _retryAt = DateTime.now().add(Duration(seconds: retry));
    _timer?.cancel();
    if (retry > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_remaining == 0) {
            timer.cancel();
            _retryAt = null;
          }
        });
      });
    }
  }

  Future<void> _load() async {
    try {
      final data = await context.read<SessionController>().api.get(
        '/me/email-change',
      );
      if (_current) {
        setState(() {
          _apply(data == null ? null : Map<String, dynamic>.from(data as Map));
          _error = null;
        });
      }
    } catch (error) {
      if (_current) setState(() => _error = errorMessage(error));
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_working || _remaining > 0 || !_emailForm.currentState!.validate()) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final data = await context.read<SessionController>().api.post(
        '/me/email-change',
        {'newEmail': _email.text.trim()},
      );
      if (_current) {
        setState(() {
          _apply(Map<String, dynamic>.from(data as Map));
          _old.clear();
          _new.clear();
        });
      }
    } catch (error) {
      if (_current) setState(() => _error = errorMessage(error));
    } finally {
      if (_current) setState(() => _working = false);
    }
  }

  Future<void> _verify() async {
    if (_working || !_codeForm.currentState!.validate()) return;
    final request = _request!;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final data = await context.read<SessionController>().api.post(
        '/me/email-change/${request['requestId']}/verify',
        {'oldCode': _old.text, 'newCode': _new.text},
      );
      if (_current) {
        setState(() {
          _apply(Map<String, dynamic>.from(data as Map));
          _old.clear();
          _new.clear();
        });
      }
    } catch (error) {
      if (_current) setState(() => _error = errorMessage(error));
    } finally {
      if (_current) setState(() => _working = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  Widget _code(TextEditingController controller, String label) => TextFormField(
    controller: controller,
    enabled: !_working,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(6),
    ],
    decoration: InputDecoration(labelText: label),
    validator: (value) =>
        RegExp(r'^\d{6}$').hasMatch(value ?? '') ? null : 'Nhập đủ 6 chữ số.',
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Đổi email'),
      actions: [
        IconButton(
          tooltip: 'Cập nhật yêu cầu',
          onPressed: _working ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : AppPage(
            children: [
              if (_error != null) Notice(_error!, isError: true),
              const Notice(
                'Xác nhận mã gửi đến email hiện tại và email mới, sau đó chờ quản trị viên khác duyệt.',
              ),
              if (_request != null)
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _emailStatus(_request!['status'] as String?),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      InfoRow(
                        'Email hiện tại',
                        _request!['maskedOldEmail']?.toString() ?? '—',
                      ),
                      InfoRow(
                        'Email mới',
                        _request!['maskedNewEmail']?.toString() ?? '—',
                      ),
                      if (_request!['expiresAt'] != null)
                        InfoRow(
                          'Hết hạn',
                          '${dateText(_request!['expiresAt'])} ${timeText(_request!['expiresAt'])}',
                        ),
                      if (_request!['status'] == 'pending_verification')
                        Form(
                          key: _codeForm,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 12),
                              _code(_old, 'Mã từ email hiện tại'),
                              const SizedBox(height: 16),
                              _code(_new, 'Mã từ email mới'),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _working ? null : _verify,
                                child: Text(
                                  _working
                                      ? 'Đang xác nhận…'
                                      : 'Xác nhận hai mã',
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_request!['status'] == 'approved')
                        const Text(
                          'Đăng nhập lại để dùng email mới. Tên đăng nhập giữ nguyên.',
                        ),
                    ],
                  ),
                ),
              Surface(
                child: Form(
                  key: _emailForm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _email,
                        enabled: !_working,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email mới',
                        ),
                        validator: (value) =>
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(value?.trim() ?? '')
                            ? null
                            : 'Nhập địa chỉ email hợp lệ.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _working || _remaining > 0 ? null : _send,
                        icon: const Icon(Icons.mail_outline),
                        label: Text(
                          _remaining > 0
                              ? 'Gửi lại sau ${_remaining}s'
                              : 'Gửi mã đến hai email',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
  );
}

class EmailChangeReviewScreen extends StatefulWidget {
  const EmailChangeReviewScreen({super.key});
  @override
  State<EmailChangeReviewScreen> createState() =>
      _EmailChangeReviewScreenState();
}

class _EmailChangeReviewScreenState extends State<EmailChangeReviewScreen> {
  late Future<List<Json>> _future;
  bool _working = false;
  String? _error;
  late final String? _userId;
  @override
  void initState() {
    super.initState();
    _userId = context.read<SessionController>().user?.id;
    _load();
  }

  void _load() {
    _future = context
        .read<SessionController>()
        .api
        .get('/email-change-requests')
        .then(
          (data) => (data as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(),
        );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _review(Json request, String decision) async {
    if (_working || request['userId'] == _userId) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().api.post(
        '/email-change-requests/${request['requestId']}/review',
        {'decision': decision},
      );
      if (mounted && context.read<SessionController>().user?.id == _userId) {
        await _refresh();
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Duyệt đổi email'),
      actions: [
        IconButton(
          tooltip: 'Cập nhật danh sách',
          onPressed: _working ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: AppPage(
      onRefresh: _refresh,
      children: [
        if (_error != null) Notice(_error!, isError: true),
        AsyncPanel<List<Json>>(
          future: _future,
          onRetry: () => setState(_load),
          builder: (requests) => Column(
            children: [
              if (requests.isEmpty)
                const EmptyState(
                  title: 'Không có yêu cầu chờ duyệt',
                  message:
                      'Các yêu cầu đã xác nhận hai email sẽ xuất hiện tại đây.',
                ),
              for (final request in requests)
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        request['fullName']?.toString() ?? 'Tài khoản',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('@${request['username']}'),
                      InfoRow(
                        'Email hiện tại',
                        request['oldEmail']?.toString() ?? '—',
                      ),
                      InfoRow(
                        'Email mới',
                        request['newEmail']?.toString() ?? '—',
                      ),
                      if (request['userId'] == _userId)
                        const Text(
                          'Cần quản trị viên khác duyệt yêu cầu của bạn.',
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _working
                                    ? null
                                    : () => _review(request, 'rejected'),
                                child: const Text('Từ chối'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _working
                                    ? null
                                    : () => _review(request, 'approved'),
                                child: const Text('Duyệt'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
