import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/first_run_guide.dart';
import '../../ui/theme.dart';
import '../../ui/ledger.dart';
import '../face/face_capture.dart';
import '../location/location_screen.dart';
import '../notifications/notification_controller.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<Json> _faceStatus;
  bool _working = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _faceStatus = context
        .read<SessionController>()
        .api
        .get('/face/status')
        .then((value) => Map<String, dynamic>.from(value as Map));
  }

  Future<void> _refreshProfile() async {
    final session = context.read<SessionController>();
    final refreshed = await session.refreshProfile();
    if (!mounted) return;
    showMessage(
      context,
      refreshed
          ? 'Đã cập nhật quyền và trạng thái tài khoản.'
          : session.error ?? 'Chưa cập nhật được tài khoản. Vui lòng thử lại.',
    );
  }

  Future<void> _enroll() async {
    final session = context.read<SessionController>();
    final image = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const FaceCaptureScreen(enrolling: true),
      ),
    );
    if (image == null || !mounted) return;
    setState(() => _working = true);
    try {
      await session.api.post('/face/enroll', {'imageBase64': image});
      if (mounted) {
        setState(_load);
        showMessage(context, 'Đã đăng ký khuôn mặt cho tài khoản của bạn.');
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _removeFace() async {
    if (!await confirmDelete(context, 'mẫu khuôn mặt của bạn')) return;
    if (!mounted) return;
    setState(() => _working = true);
    try {
      await context.read<SessionController>().api.delete('/face/enroll');
      if (mounted) setState(_load);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>(), user = session.user!;
    final notifications = context.watch<NotificationController?>();
    return AppPage(
      onRefresh: _refreshProfile,
      children: [
        const LedgerHeading(kicker: 'HỒ SƠ / HN', title: 'Tài khoản'),
        if (session.profileSyncError != null)
          const Notice(
            'Chưa cập nhật được quyền và trạng thái. Thông tin đang hiển thị là lần tải gần nhất.',
            isError: true,
          ),
        LedgerSheet(
          label: 'HỒ SƠ',
          reference: user.roleLabel.toUpperCase(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Tooltip(
                message: user.fullName,
                child: Text(
                  user.fullName,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 16),
              InfoRow('Tên đăng nhập', user.username),
              InfoRow('Email', user.email),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(user.status),
              ),
              if (session.profileSyncedAt != null)
                InfoRow(
                  'Cập nhật lúc',
                  timeText(session.profileSyncedAt!.toIso8601String()),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: session.busy ? null : _refreshProfile,
                icon: const Icon(Icons.refresh),
                label: const Text('Kiểm tra quyền và trạng thái'),
              ),
            ],
          ),
        ),
        const LedgerSection(number: '01', title: 'Đăng nhập khuôn mặt'),
        AsyncPanel<Json>(
          future: _faceStatus,
          onRetry: () => setState(_load),
          builder: (status) => Surface(
            color: AppColors.palePink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      status['enrolled'] == true
                          ? Icons.verified_user_outlined
                          : Icons.face_retouching_natural,
                      color: AppColors.pink,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        status['enrolled'] == true
                            ? 'Đã có mẫu khuôn mặt'
                            : 'Chưa đăng ký khuôn mặt',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Dùng khuôn mặt đã đăng ký và mã xác nhận gửi qua email để đăng nhập.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _working ? null : _enroll,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(
                    _working
                        ? 'Đang xử lý…'
                        : status['enrolled'] == true
                        ? 'Đăng ký lại khuôn mặt'
                        : 'Đăng ký khuôn mặt',
                  ),
                ),
                if (status['enrolled'] == true)
                  TextButton(
                    onPressed: _working ? null : _removeFace,
                    child: const Text('Xóa mẫu khuôn mặt'),
                  ),
              ],
            ),
          ),
        ),
        if (notifications != null)
          LedgerSheet(
            label: 'THÔNG BÁO THIẾT BỊ',
            reference: notifications.enabled ? 'ĐANG BẬT' : 'CHƯA BẬT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(notifications.status),
                const SizedBox(height: 10),
                const Text(
                  'Màn hình khóa chỉ hiện lời nhắc chung; mở ứng dụng để xem chi tiết.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: notifications.working
                      ? null
                      : notifications.enabled
                      ? notifications.refresh
                      : notifications.enable,
                  icon: const Icon(Icons.notifications_outlined),
                  label: Text(
                    notifications.working
                        ? 'Đang kết nối…'
                        : notifications.enabled
                        ? 'Kiểm tra kết nối'
                        : 'Bật thông báo',
                  ),
                ),
                if (notifications.optedIn ||
                    notifications.enabled ||
                    notifications.cleanupIncomplete)
                  TextButton(
                    onPressed: notifications.working
                        ? null
                        : notifications.disable,
                    child: const Text('Tắt trên thiết bị này'),
                  ),
              ],
            ),
          ),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Hướng dẫn sử dụng'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showQuickGuide(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.share_location_outlined),
                title: const Text('Vị trí trong ca'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LocationScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Về ứng dụng'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Nguyễn Hoài Nam',
                  applicationVersion: '1.0.0',
                  applicationIcon: const HnMark(size: 40),
                  applicationLegalese: 'Nguyễn Hoài Nam · 2380601398 · Nhóm 8',
                  children: const [
                    SizedBox(height: 16),
                    Text(
                      'Ứng dụng chấm công và bàn giao song ngữ. Môn Lập trình trên thiết bị di động.',
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Giọng nói: Zipformer VI (hynt, CC BY-NC-ND 4.0), Paraformer EN–ZH (Alibaba, Apache 2.0), sherpa-onnx. Dịch và OCR: Google ML Kit. Bản đồ: © OpenStreetMap contributors.',
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Nhận diện mặt qua ảnh 2D có giới hạn chống giả mạo; ứng dụng kết hợp OTP email.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: session.busy
              ? null
              : () async {
                  notifications?.suspendForLogout();
                  await session.logout();
                },
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
        ),
      ],
    );
  }
}
