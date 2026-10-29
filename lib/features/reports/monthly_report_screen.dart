import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/ledger.dart';
import '../../ui/theme.dart';
import 'report_models.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key, this.initialMonth});
  final DateTime? initialMonth;
  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _ReportData {
  const _ReportData(this.report, this.employees, this.branches);
  final Json report;
  final List<Json> employees, branches;
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  late MonthlyReportFilter _filter;
  late Future<_ReportData> _future;
  Future<List<List<Json>>>? _lookups;

  @override
  void initState() {
    super.initState();
    _filter = MonthlyReportFilter(month: widget.initialMonth ?? DateTime.now());
    _future = _fetch(_filter);
  }

  Future<_ReportData> _fetch(MonthlyReportFilter filter) async {
    final session = context.read<SessionController>();
    final api = session.api, user = session.user!;
    _lookups ??= user.canManage
        ? Future.wait(
            ['/employees', '/branches'].map(
              (path) => api
                  .get(path)
                  .then(
                    (value) => (value as List)
                        .map((row) => Map<String, dynamic>.from(row as Map))
                        .toList(),
                  ),
            ),
          )
        : Future.value([<Json>[], <Json>[]]);
    final values = await Future.wait([
      api.get('/reports/monthly', query: filter.query(user)),
      _lookups!,
    ]);
    final lists = values[1] as List<List<Json>>;
    return _ReportData(
      Map<String, dynamic>.from(values[0] as Map),
      lists[0],
      lists[1],
    );
  }

  void _select(MonthlyReportFilter value) => setState(() {
    _filter = value;
    _future = _fetch(value);
  });
  Future<void> _refresh() async {
    setState(() {
      _lookups = null;
      _future = _fetch(_filter);
    });
    try {
      await _future;
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _pickMonth() async {
    var year = _filter.month.year, month = _filter.month.month;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('Chọn tháng đối soát'),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Năm trước',
                      onPressed: year > 2020
                          ? () => change(() => year--)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '$year',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Năm sau',
                      onPressed: year < 2100
                          ? () => change(() => year++)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.7,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var value = 1; value <= 12; value++)
                      OutlinedButton(
                        onPressed: () => change(() => month = value),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: month == value
                              ? AppColors.palePink
                              : null,
                          padding: EdgeInsets.zero,
                        ),
                        child: Text('Th ${value.toString().padLeft(2, '0')}'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, DateTime(year, month)),
              child: const Text('Xem tháng này'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) _select(_filter.forMonth(selected));
  }

  Widget _choice({
    required String key,
    required String label,
    required String? selected,
    required Map<String, String> values,
    required ValueChanged<String?> onChanged,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$key-$selected-${values.keys.join()}'),
    initialValue: selected ?? '',
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem(value: '', child: Text('Tất cả')),
      if (selected != null && !values.containsKey(selected))
        DropdownMenuItem(value: selected, child: Text('$label đã chọn')),
      for (final item in values.entries)
        DropdownMenuItem(
          value: item.key,
          child: Text(item.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) => onChanged(value == '' ? null : value),
  );

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!,
        period = _filter.month;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảng công tháng'),
        actions: [
          IconButton(
            tooltip: 'Xóa bộ lọc',
            onPressed: _filter.employeeId == null && _filter.branchId == null
                ? null
                : () => _select(MonthlyReportFilter(month: period)),
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
      body: AppPage(
        onRefresh: _refresh,
        children: [
          const LedgerHeading(
            kicker: 'ĐỐI SOÁT / THỜI GIAN',
            title: 'Bảng công tháng',
            subtitle: 'Giờ chấm gốc được giữ riêng với giờ sau điều chỉnh.',
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Tháng trước',
                onPressed: period.year > 2020 || period.month > 1
                    ? () => _select(
                        _filter.forMonth(
                          DateTime(period.year, period.month - 1),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _pickMonth,
                  child: Text(
                    'Tháng ${period.month.toString().padLeft(2, '0')} / ${period.year}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tháng sau',
                onPressed: period.year < 2100 || period.month < 12
                    ? () => _select(
                        _filter.forMonth(
                          DateTime(period.year, period.month + 1),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const Divider(height: 28),
          AsyncPanel<_ReportData>(
            future: _future,
            onRetry: () => _refresh(),
            builder: (data) {
              final report = data.report,
                  totals = Map<String, dynamic>.from(report['totals'] as Map);
              final rows = (report['rows'] as List)
                  .map((row) => Map<String, dynamic>.from(row as Map))
                  .toList();
              final zone = report['timeZone'] as String;
              final employees = data.employees.where(
                (person) =>
                    _filter.branchId == null ||
                    person['branchId'] == _filter.branchId,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (user.canManage) ...[
                    if (user.isAdmin)
                      _choice(
                        key: 'branch',
                        label: 'Chi nhánh',
                        selected: _filter.branchId,
                        values: {
                          for (final branch in data.branches)
                            branch['id'] as String: branch['name'] as String,
                        },
                        onChanged: (value) => _select(_filter.forBranch(value)),
                      ),
                    const SizedBox(height: 12),
                    _choice(
                      key: 'employee',
                      label: 'Nhân viên',
                      selected: _filter.employeeId,
                      values: {
                        for (final person in employees)
                          person['id'] as String:
                              '${person['fullName']}${person['username'] == null ? '' : ' · ${person['username']}'}',
                      },
                      onChanged: (value) => _select(_filter.forEmployee(value)),
                    ),
                    const SizedBox(height: 20),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        user.fullName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  LedgerSheet(
                    label: 'TỔNG HỢP CA',
                    reference: report['month'].toString(),
                    footer: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Khoảng giờ sau điều chỉnh: ${reportDuration(totals['rawSpanMinutes'])}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Khoảng giờ chấm gốc: ${reportDuration(totals['recordedSpanMinutes'])}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Chỉ cộng khoảng giờ có đủ đầu vào và đầu ra. Chưa trừ giờ nghỉ hoặc tính quy định lương, tăng ca.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                    child: Wrap(
                      spacing: 22,
                      runSpacing: 18,
                      children: [
                        for (final metric in [
                          ('shiftCount', 'Tổng số ca'),
                          ('completedCount', 'Đã ra ca'),
                          ('inProgressCount', 'Đang làm'),
                          ('upcomingCount', 'Sắp đến'),
                          ('notCheckedInCount', 'Chưa vào'),
                          ('missingCheckInCount', 'Thiếu giờ vào'),
                          ('missingCheckOutCount', 'Thiếu giờ ra'),
                          ('lateCount', 'Đi muộn'),
                          ('earlyLeaveCount', 'Về sớm'),
                        ])
                          SizedBox(
                            width: 78,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  totals[metric.$1]?.toString() ?? '—',
                                  style: const TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  metric.$2,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 18),
                    child: Text(
                      'Ngày công theo $zone. Ca qua đêm được xếp vào ngày bắt đầu ca.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const LedgerSection(
                    number: '01',
                    title: 'Sổ chi tiết từng ca',
                  ),
                  if (rows.isEmpty)
                    const EmptyState(
                      title: 'Tháng này chưa có ca',
                      message: 'Đổi tháng hoặc bộ lọc để xem các ca trong phạm vi được phân quyền.',
                      icon: Icons.event_note_outlined,
                    ),
                  for (final row in rows) _ledgerRow(row, zone, user.canManage),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _ledgerRow(Json row, String zone, bool showEmployee) {
    final timing = Map<String, dynamic>.from(row['timing'] as Map),
        date = row['workDate'].toString();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ReportShiftDetail(row: row, timeZone: zone),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date.length >= 10 ? date.substring(8, 10) : '—',
                      style: const TextStyle(
                        fontSize: 22,
                        color: AppColors.pink,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      date.length >= 7 ? '/${date.substring(5, 7)}' : '',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['title'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (showEmployee)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          row['employeeName'].toString(),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Text(
                      row['branchName'].toString(),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      reportStateLabel(timing['state'] as String),
                      style: TextStyle(
                        color: timing['state'] == 'completed'
                            ? AppColors.green
                            : AppColors.pink,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (timing['late'] == true)
                      Text(
                        'Đi muộn ${timing['arrivalDelayMinutes']} phút',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.pink,
                        ),
                      ),
                    if (timing['earlyLeave'] == true)
                      Text(
                        'Về sớm ${timing['earlyLeaveMinutes']} phút',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.pink,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 68,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      reportLocalTime(row, 'checkInAt', clockOnly: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      'vào · ra',
                      style: TextStyle(fontSize: 9, color: AppColors.muted),
                    ),
                    Text(
                      reportLocalTime(row, 'checkOutAt', clockOnly: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportShiftDetail extends StatelessWidget {
  const _ReportShiftDetail({required this.row, required this.timeZone});
  final Json row;
  final String timeZone;
  @override
  Widget build(BuildContext context) {
    final timing = Map<String, dynamic>.from(row['timing'] as Map);
    final policy = Map<String, dynamic>.from(row['timePolicySnapshot'] as Map);
    return Scaffold(
      appBar: AppBar(title: const Text('Đối soát một ca')),
      body: AppPage(
        children: [
          LedgerHeading(
            kicker: row['workDate'].toString(),
            title: row['title'].toString(),
            subtitle: '${row['employeeName']} · ${row['branchName']}',
          ),
          Text(
            'Múi giờ: $timeZone',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          LedgerSection(
            number: '01',
            title: reportStateLabel(timing['state'] as String),
          ),
          for (final span in [
            ('Kế hoạch', 'startsAt', 'endsAt'),
            ('Giờ chấm gốc', 'recordedCheckInAt', 'recordedCheckOutAt'),
            ('Giờ sau điều chỉnh', 'checkInAt', 'checkOutAt'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(span.$1, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  InfoRow('Vào', reportLocalTime(row, span.$2)),
                  InfoRow('Ra', reportLocalTime(row, span.$3)),
                  const Divider(),
                ],
              ),
            ),
          if (row['source'] == 'correction')
            const Notice(
              'Giờ hiệu lực đã được cập nhật theo đơn điều chỉnh được duyệt. Giờ chấm gốc được giữ để đối chiếu.',
            ),
          InfoRow('Khoảng hiệu lực', reportDuration(timing['rawSpanMinutes'])),
          InfoRow('Khoảng gốc', reportDuration(timing['recordedSpanMinutes'])),
          const Text(
            'Đây là khoảng thời gian giữa hai mốc, chưa phải số giờ được trả lương.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const LedgerSection(
            number: '02',
            title: 'Chính sách đã áp dụng cho ca',
          ),
          InfoRow('Vào sớm', '${policy['checkInEarlyMinutes']} phút'),
          InfoRow('Ân hạn muộn', '${policy['lateGraceMinutes']} phút'),
          InfoRow('Ân hạn về sớm', '${policy['earlyLeaveGraceMinutes']} phút'),
          InfoRow('Ra muộn tối đa', '${policy['checkOutLateMinutes']} phút'),
          const SizedBox(height: 14),
          InfoRow(
            'Chênh lệch vào',
            row['checkInAt'] == null
                ? 'Chưa có giờ vào'
                : '${timing['arrivalDelayMinutes']} phút',
          ),
          InfoRow(
            'Chênh lệch ra',
            row['checkOutAt'] == null
                ? 'Chưa có giờ ra'
                : '${timing['earlyLeaveMinutes']} phút',
          ),
          Text(
            'Đi muộn: ${row['checkInAt'] == null
                ? 'Chưa có giờ vào'
                : timing['late'] == true
                ? 'Vượt ân hạn'
                : 'Không vượt ân hạn'}. Về sớm: ${row['checkOutAt'] == null
                ? 'Chưa có giờ ra'
                : timing['earlyLeave'] == true
                ? 'Vượt ân hạn'
                : 'Không vượt ân hạn'}.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
