import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../../ui/ledger.dart';
import '../reports/monthly_report_screen.dart';
import '../manage/resources_screen.dart';
import '../location/location_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<List<Json>>> _future;
  bool _punching = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<SessionController>().api;
    _future = Future.wait(
      ['/shifts', '/attendance', '/branches', '/corrections'].map(
        (path) => api
            .get(path)
            .then(
              (value) => (value as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList(),
            ),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _punch(Json shift, bool checkingOut) async {
    setState(() => _punching = true);
    try {
      final api = context.read<SessionController>().api;
      final p = await currentPosition();
      final result = await api.post(
        checkingOut ? '/attendance/check-out' : '/attendance/check-in',
        {
          'shiftId': shift['id'],
          'latitude': p.latitude,
          'longitude': p.longitude,
          'accuracyMeters': p.accuracy,
        },
      );
      if (mounted) {
        // The punch is already committed; a failed refresh must not report it as failed.
        setState(_load);
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          backgroundColor: AppColors.cream,
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LedgerSheet(
                    label: checkingOut
                        ? 'BIÊN NHẬN GIỜ RA'
                        : 'BIÊN NHẬN GIỜ VÀO',
                    reference: '',
                    footer: TweenAnimationBuilder<double>(
                      tween: Tween(begin: .86, end: 1),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, child) =>
                          Transform.scale(scale: value, child: child),
                      child: const Center(
                        child: ConfirmationStamp(label: 'ĐÃ GHI NHẬN'),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shift['title'].toString(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          timeText(
                            result[checkingOut ? 'checkOutAt' : 'checkInAt'],
                          ),
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontSize: 46),
                        ),
                        Text(
                          dateText(
                            result[checkingOut ? 'checkOutAt' : 'checkInAt'],
                          ),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Đã lưu giờ chấm công.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng biên nhận'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  void _openCorrections() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ResourceScreen(resource: 'corrections'),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!, now = DateTime.now();
    return AppPage(
      onRefresh: _refresh,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('EEEE, dd MMMM', 'vi').format(now),
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            StatusPill(user.role),
          ],
        ),
        const SizedBox(height: 14),
        const LedgerHeading(kicker: 'CHẤM CÔNG / HN', title: 'Ca làm hôm nay'),
        AsyncPanel<List<List<Json>>>(
          future: _future,
          onRetry: () => setState(_load),
          builder: (data) {
            final shifts = data[0],
                attendance = data[1],
                branches = data[2],
                corrections = data[3];
            final own = shifts.where((s) => s['employeeId'] == user.id).toList()
              ..sort(
                (a, b) => a['startsAt'].toString().compareTo(
                  b['startsAt'].toString(),
                ),
              );
            final openRecord = attendance
                .where(
                  (a) => a['employeeId'] == user.id && a['checkOutAt'] == null,
                )
                .firstOrNull;
            Json? selected = openRecord == null
                ? null
                : own
                      .where((s) => s['id'] == openRecord['shiftId'])
                      .firstOrNull;
            selected ??= own
                .where(
                  (s) =>
                      s['status'] != 'completed' &&
                      !DateTime.parse(s['endsAt'].toString()).isBefore(now) &&
                      (isSameLocalDay(s['startsAt'], now) ||
                          !DateTime.parse(s['startsAt'].toString())
                              .isAfter(now)),
                )
                .firstOrNull;
            final today = own
                .where(
                  (s) =>
                      isSameLocalDay(s['startsAt'], now) ||
                      (DateTime.parse(s['startsAt'].toString()).isBefore(now) &&
                          DateTime.parse(s['endsAt'].toString()).isAfter(now)),
                )
                .toList();
            final selectedRecord = selected == null
                ? null
                : attendance
                      .where(
                        (a) =>
                            a['shiftId'] == selected!['id'] &&
                            a['employeeId'] == user.id,
                      )
                      .firstOrNull;
            final branch = selected == null
                ? null
                : branches
                      .where((b) => b['id'] == selected!['branchId'])
                      .firstOrNull;
            final myPending = corrections
                .where(
                  (c) => c['employeeId'] == user.id && c['status'] == 'pending',
                )
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (selected != null)
                  _punchCard(context, selected, selectedRecord, branch)
                else
                  LedgerSheet(
                    label: 'PHIẾU CA / HÔM NAY',
                    reference: '',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.event_available_outlined,
                          color: AppColors.pink,
                          size: 28,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Hôm nay chưa có ca cần chấm công',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user.canManage
                              ? 'Xếp ca tại mục Quản lý.'
                              : 'Ca sẽ xuất hiện sau khi quản lý phân công.',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (user.canManage)
                  Surface(
                    color: AppColors.palePink,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.groups_outlined,
                          color: AppColors.pink,
                          size: 29,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            '${shifts.where((s) => isSameLocalDay(s['startsAt'], now)).length} ca hôm nay · ${corrections.where((c) => c['status'] == 'pending').length} đơn chờ xử lý',
                            style: const TextStyle(height: 1.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MonthlyReportScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: const Text('Bảng công tháng'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openCorrections,
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: Text(
                          myPending > 0
                              ? 'Đơn của tôi ($myPending)'
                              : 'Điều chỉnh công',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: 'Chia sẻ vị trí',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LocationScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.share_location_outlined),
                    ),
                  ],
                ),
                const LedgerSection(number: '01', title: 'Dòng thời gian ca'),
                if (today.isEmpty)
                  const Text(
                    'Chưa có ca được phân công trong ngày.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                for (final shift in today)
                  _shiftLine(
                    context,
                    shift,
                    attendance
                        .where((a) => a['shiftId'] == shift['id'])
                        .firstOrNull,
                  ),
                const LedgerSection(number: '02', title: 'Biên nhận gần đây'),
                if (attendance.where((a) => a['employeeId'] == user.id).isEmpty)
                  const Text(
                    'Chưa có biên nhận chấm công.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                for (final record
                    in attendance
                        .where((a) => a['employeeId'] == user.id)
                        .take(5))
                  LedgerSheet(
                    label: 'BIÊN NHẬN CHẤM CÔNG',
                    reference: '',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              color: AppColors.pink,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                dateText(record['checkInAt']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            StatusPill(
                              record['checkOutAt'] == null
                                  ? 'in_progress'
                                  : 'completed',
                            ),
                          ],
                        ),
                        const Divider(),
                        InfoRow('Giờ vào', timeText(record['checkInAt'])),
                        InfoRow('Giờ ra', timeText(record['checkOutAt'])),
                        if (record['accuracyMeters'] != null)
                          InfoRow(
                            'Sai số GPS',
                            '${(record['accuracyMeters'] as num).toStringAsFixed(0)} m',
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _punchCard(
    BuildContext context,
    Json shift,
    Json? record,
    Json? branch,
  ) {
    final checkedIn = record != null,
        checkedOut = record?['checkOutAt'] != null;
    final missingCheckOut =
        record?['timing'] is Map &&
        record!['timing']['missingCheckOut'] == true;
    final window = shift['timeWindow'] as Map?;
    return LedgerSheet(
      label: 'PHIẾU CA / ${dateText(shift['startsAt'])}',
      reference: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shift['title'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusPill(
                missingCheckOut
                    ? 'missing_check_out'
                    : shift['status'].toString(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '${timeText(shift['startsAt'])} — ${timeText(shift['endsAt'])}',
            style: const TextStyle(
              fontFamily: 'Lora',
              fontSize: 32,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          if (!isSameLocalDay(
            shift['startsAt'],
            DateTime.parse(shift['endsAt'].toString()).toLocal(),
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Ca qua đêm · kết thúc ngày ${dateText(shift['endsAt'])}',
                style: const TextStyle(color: AppColors.pink, fontSize: 11),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined, size: 18, color: AppColors.pink),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  branch?['name']?.toString() ?? 'Chi nhánh đã phân công',
                ),
              ),
            ],
          ),
          if (branch != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Phạm vi chấm công ${branch['radiusMeters']} m',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 24),
          if (window != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                checkedIn
                    ? 'Nhận giờ ra đến ${timeText(window['checkOutClosesAt'])} · ${dateText(window['checkOutClosesAt'])}'
                    : 'Nhận giờ vào ${timeText(window['checkInOpensAt'])}–${timeText(window['checkInClosesAt'])}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
          if (!checkedOut && !missingCheckOut)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Lấy vị trí hiện tại khi chấm công để kiểm tra phạm vi chi nhánh.',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
          FilledButton.icon(
            onPressed: _punching || checkedOut
                ? null
                : missingCheckOut
                ? _openCorrections
                : () => _punch(shift, checkedIn),
            icon: Icon(
              missingCheckOut
                  ? Icons.edit_calendar_outlined
                  : checkedIn
                  ? Icons.logout_rounded
                  : Icons.login_rounded,
            ),
            label: Text(
              _punching
                  ? 'Đang xác định vị trí…'
                  : checkedOut
                  ? 'Đã hoàn tất ca'
                  : missingCheckOut
                  ? 'Gửi đơn bổ sung giờ ra'
                  : checkedIn
                  ? 'Chấm công ra'
                  : 'Chấm công vào',
            ),
          ),
          if (record != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                missingCheckOut
                    ? 'Quá giờ chấm ra · Giờ vào gốc ${timeText(record['checkInAt'])} được giữ nguyên.'
                    : 'Đã vào ${timeText(record['checkInAt'])}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _shiftLine(BuildContext context, Json shift, Json? record) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 55,
          child: Text(
            timeText(shift['startsAt']),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Container(width: 2, height: 56, color: AppColors.line),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shift['title'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                record == null
                    ? 'Chưa có giờ vào'
                    : 'Đã vào ${timeText(record['checkInAt'])}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        StatusPill(shift['status'].toString()),
      ],
    ),
  );
}
