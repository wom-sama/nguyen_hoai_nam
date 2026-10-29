import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/location.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../../ui/ledger.dart';
import '../reports/monthly_report_screen.dart';

const branchTimePolicyDefaults = <String, int>{
  'checkInEarlyMinutes': 30,
  'lateGraceMinutes': 10,
  'earlyLeaveGraceMinutes': 10,
  'checkOutLateMinutes': 120,
};
const branchTimePolicyLabels = <String, String>{
  'checkInEarlyMinutes': 'Cho phép vào sớm (phút)',
  'lateGraceMinutes': 'Ân hạn đi muộn (phút)',
  'earlyLeaveGraceMinutes': 'Ân hạn về sớm (phút)',
  'checkOutLateMinutes': 'Cho phép ra muộn tối đa (phút)',
};

Json resourceMutation(String resource, Json candidate, {Json? initial}) {
  final allowed = switch (resource) {
    'employees' => {
      'fullName',
      'username',
      'email',
      'password',
      'role',
      'status',
      'branchId',
    },
    'branches' => {
      'name',
      'address',
      'latitude',
      'longitude',
      'radiusMeters',
      'timePolicy',
    },
    'shifts' => {'title', 'branchId', 'employeeId', 'startsAt', 'endsAt'},
    'corrections' => {
      'shiftId',
      'requestedCheckIn',
      'requestedCheckOut',
      'reason',
    },
    _ => <String>{},
  };
  const dates = {'startsAt', 'endsAt', 'requestedCheckIn', 'requestedCheckOut'};
  Object? comparable(String key, Object? value) =>
      dates.contains(key) && value != null
      ? DateTime.parse(value.toString()).toUtc().toIso8601String()
      : value;
  final result = <String, dynamic>{};
  for (final entry in candidate.entries) {
    if (!allowed.contains(entry.key) ||
        (initial != null && entry.key == 'password' && entry.value == '')) {
      continue;
    }
    if (entry.key == 'timePolicy') {
      final value = entry.value;
      if (value is! Map ||
          value.length != 4 ||
          branchTimePolicyDefaults.keys.any(
            (key) =>
                value[key] is! int ||
                (value[key] as int) < 0 ||
                (value[key] as int) > 1440,
          )) {
        throw const FormatException(
          'Chính sách ca cần đủ 4 số nguyên từ 0 đến 1.440 phút.',
        );
      }
    }
    final current = comparable(entry.key, entry.value);
    final before = comparable(entry.key, initial?[entry.key]);
    final same = current is Map && before is Map
        ? mapEquals(current, before)
        : current == before;
    if (initial != null && same) continue;
    if (resource == 'shifts' &&
        initial?['planLocked'] == true &&
        {'employeeId', 'branchId', 'startsAt', 'endsAt'}.contains(entry.key)) {
      throw const FormatException(
        'Ca đã có dữ liệu chấm công hoặc đơn điều chỉnh. Chỉ tên ca còn được chỉnh sửa.',
      );
    }
    result[entry.key] = current;
  }
  return result;
}

String resourceLabel(String name) => switch (name) {
  'employees' => 'Nhân viên',
  'branches' => 'Chi nhánh',
  'shifts' => 'Ca làm',
  'corrections' => 'Điều chỉnh công',
  _ => name,
};
String recordTitle(String name, Json row) => switch (name) {
  'employees' => row['fullName']?.toString() ?? 'Nhân viên',
  'branches' => row['name']?.toString() ?? 'Chi nhánh',
  'shifts' => row['title']?.toString() ?? 'Ca làm',
  'corrections' => 'Đề nghị ngày ${dateText(row['createdAt'])}',
  _ => 'Dữ liệu',
};

class ManagementScreen extends StatelessWidget {
  const ManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;
    return AppPage(
      children: [
        LedgerHeading(
          kicker: user.isAdmin ? 'TÀI KHOẢN · CHI NHÁNH' : 'QUẢN LÝ CHI NHÁNH',
          title: user.isAdmin ? 'Quản trị' : 'Điều phối ca',
        ),
        Surface(
          color: AppColors.palePink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ResourceScreen(
                      resource: user.isAdmin ? 'employees' : 'shifts',
                    ),
                  ),
                ),
                icon: Icon(
                  user.isAdmin
                      ? Icons.people_outline
                      : Icons.event_available_outlined,
                ),
                label: Text(user.isAdmin ? 'Nhân viên' : 'Phân ca'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ResourceScreen(
                      resource: user.isAdmin ? 'branches' : 'corrections',
                    ),
                  ),
                ),
                icon: Icon(
                  user.isAdmin
                      ? Icons.store_outlined
                      : Icons.fact_check_outlined,
                ),
                label: Text(user.isAdmin ? 'Chi nhánh' : 'Duyệt đơn'),
              ),
            ],
          ),
        ),
        _menuRow(
          context,
          '01',
          user.isAdmin ? 'Bảng công tháng' : 'Bảng công chi nhánh',
          () => const MonthlyReportScreen(),
        ),
        for (final entry
            in (user.isAdmin
                    ? [('shifts', 'Ca làm'), ('corrections', 'Điều chỉnh công')]
                    : [
                        ('employees', 'Nhân viên chi nhánh'),
                        ('branches', 'Thông tin chi nhánh'),
                      ])
                .indexed)
          _menuRow(
            context,
            '${entry.$1 + 2}'.padLeft(2, '0'),
            entry.$2.$2,
            () => ResourceScreen(resource: entry.$2.$1),
          ),
      ],
    );
  }

  Widget _menuRow(
    BuildContext context,
    String index,
    String title,
    Widget Function() page,
  ) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page())),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                index,
                style: const TextStyle(
                  color: AppColors.pink,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_outward, color: AppColors.pink, size: 19),
          ],
        ),
      ),
    ),
  );
}

class ResourceScreen extends StatefulWidget {
  const ResourceScreen({super.key, required this.resource});
  final String resource;
  @override
  State<ResourceScreen> createState() => _ResourceScreenState();
}

class _ResourceScreenState extends State<ResourceScreen> {
  late Future<List<Json>> _future;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context
        .read<SessionController>()
        .api
        .get('/${widget.resource}')
        .then(
          (value) => (value as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  bool _canCreate(AppUser user) => switch (widget.resource) {
    'employees' || 'branches' => user.isAdmin,
    'shifts' => user.canManage,
    'corrections' => true,
    _ => false,
  };
  bool _canEdit(AppUser user, Json row) => switch (widget.resource) {
    'employees' || 'branches' => user.isAdmin,
    'shifts' => user.canManage,
    'corrections' => row['employeeId'] == user.id && row['status'] == 'pending',
    _ => false,
  };
  bool _canDelete(AppUser user, Json row) =>
      _canEdit(user, row) &&
      !(widget.resource == 'shifts' && row['planLocked'] == true);
  Future<void> _edit([Json? item]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ResourceEditor(resource: widget.resource, initial: item),
      ),
    );
    if (changed == true && mounted) await _refresh();
  }

  Future<void> _delete(Json item) async {
    if (!await confirmDelete(context, recordTitle(widget.resource, item))) {
      return;
    }
    if (!mounted) return;
    try {
      await context.read<SessionController>().api.delete(
        '/${widget.resource}/${item['id']}',
      );
      await _refresh();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  Future<void> _review(Json item, String status) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          status == 'approved' ? 'Duyệt điều chỉnh công' : 'Từ chối điều chỉnh',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoRow('Giờ vào', timeText(item['requestedCheckIn'])),
            InfoRow('Giờ ra', timeText(item['requestedCheckOut'])),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Ghi chú xử lý'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;
    try {
      await context.read<SessionController>().api.patch(
        '/corrections/${item['id']}',
        {'status': status, 'resolutionNote': note},
      );
      await _refresh();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;
    return Scaffold(
      appBar: AppBar(
        title: Text(resourceLabel(widget.resource)),
        actions: [
          if (_canCreate(user) && widget.resource != 'branches')
            IconButton(
              tooltip: 'Thêm mới',
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      floatingActionButton: widget.resource == 'branches' && user.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Thêm chi nhánh'),
            )
          : null,
      body: AppPage(
        onRefresh: _refresh,
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Tìm trong danh sách',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 20),
          AsyncPanel<List<Json>>(
            future: _future,
            onRetry: () => setState(_load),
            builder: (rows) {
              final visible = rows
                  .where(
                    (row) =>
                        [
                          recordTitle(widget.resource, row),
                          row['email'],
                          row['username'],
                          row['reason'],
                        ].whereType<String>().any(
                          (v) => v.toLowerCase().contains(_query),
                        ),
                  )
                  .toList();
              if (visible.isEmpty) {
                return EmptyState(
                  title: rows.isEmpty
                      ? 'Chưa có dữ liệu'
                      : 'Chưa tìm thấy kết quả',
                  message: rows.isEmpty
                      ? 'Thêm dữ liệu đầu tiên để bắt đầu quản lý.'
                      : 'Thử tên hoặc từ khóa khác.',
                  action: _canCreate(user)
                      ? OutlinedButton.icon(
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add),
                          label: Text(
                            widget.resource == 'branches'
                                ? 'Thêm chi nhánh'
                                : 'Thêm mới',
                          ),
                        )
                      : null,
                );
              }
              return Column(
                children: visible
                    .map(
                      (row) => Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    recordTitle(widget.resource, row),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                if (row['status'] != null)
                                  StatusPill(row['status'].toString()),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (widget.resource == 'employees') ...[
                              Text(
                                row['email'].toString(),
                                style: const TextStyle(color: AppColors.muted),
                              ),
                              const SizedBox(height: 8),
                              StatusPill(row['role'].toString()),
                            ],
                            if (widget.resource == 'branches') ...[
                              Text(row['address'].toString()),
                              InfoRow('Phạm vi', '${row['radiusMeters']} m'),
                              if (row['timePolicy'] is Map) ...[
                                InfoRow(
                                  'Vào sớm',
                                  '${row['timePolicy']['checkInEarlyMinutes']} phút',
                                ),
                                InfoRow(
                                  'Ân hạn muộn',
                                  '${row['timePolicy']['lateGraceMinutes']} phút',
                                ),
                                InfoRow(
                                  'Ân hạn về sớm',
                                  '${row['timePolicy']['earlyLeaveGraceMinutes']} phút',
                                ),
                                InfoRow(
                                  'Ra muộn tối đa',
                                  '${row['timePolicy']['checkOutLateMinutes']} phút',
                                ),
                              ],
                            ],
                            if (widget.resource == 'shifts') ...[
                              if (row['employeeName'] != null)
                                InfoRow(
                                  'Nhân viên',
                                  row['employeeName'].toString(),
                                ),
                              if (row['branchName'] != null)
                                InfoRow(
                                  'Chi nhánh',
                                  row['branchName'].toString(),
                                ),
                              InfoRow('Ngày làm', dateText(row['startsAt'])),
                              InfoRow(
                                'Thời gian',
                                '${timeText(row['startsAt'])} – ${timeText(row['endsAt'])}',
                              ),
                              if (row['planLocked'] == true)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Đã ghi công hoặc có đơn điều chỉnh: chỉ sửa tên ca.',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                            if (widget.resource == 'corrections') ...[
                              Text(row['reason'].toString()),
                              InfoRow(
                                'Giờ vào',
                                timeText(row['requestedCheckIn']),
                              ),
                              InfoRow(
                                'Giờ ra',
                                timeText(row['requestedCheckOut']),
                              ),
                              if ((row['resolutionNote']?.toString() ?? '')
                                  .isNotEmpty)
                                InfoRow(
                                  'Phản hồi',
                                  row['resolutionNote'].toString(),
                                ),
                            ],
                            if (_canEdit(user, row)) ...[
                              const Divider(),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _edit(row),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Chỉnh sửa'),
                                  ),
                                  if (_canDelete(user, row))
                                    TextButton.icon(
                                      onPressed: () => _delete(row),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      label: Text(
                                        widget.resource == 'corrections'
                                            ? 'Rút đơn'
                                            : 'Xóa',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (widget.resource == 'corrections' &&
                                user.canManage &&
                                row['employeeId'] != user.id &&
                                row['status'] == 'pending') ...[
                              const Divider(),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => _review(row, 'approved'),
                                    icon: const Icon(Icons.check),
                                    label: const Text('Duyệt đơn'),
                                  ),
                                  TextButton(
                                    onPressed: () => _review(row, 'rejected'),
                                    child: const Text('Từ chối'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Field {
  const _Field(
    this.key,
    this.label, {
    this.kind = 'text',
    this.required = true,
    this.choices = const {},
    this.minimum = 0,
    this.maximum = 100000,
  });
  final String key, label, kind;
  final bool required;
  final Map<String, String> choices;
  final double minimum, maximum;
}

class ResourceEditor extends StatefulWidget {
  const ResourceEditor({super.key, required this.resource, this.initial});
  final String resource;
  final Json? initial;
  @override
  State<ResourceEditor> createState() => _ResourceEditorState();
}

class _ResourceEditorState extends State<ResourceEditor> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _values = {};
  List<Json> _branches = [], _employees = [], _shifts = [];
  bool _loading = true, _saving = false;
  String? _error;
  bool get _editing => widget.initial != null;
  @override
  void initState() {
    super.initState();
    _values.addAll(widget.initial ?? {});
    if (widget.resource == 'branches') {
      final policy =
          widget.initial?['timePolicy'] as Map? ?? branchTimePolicyDefaults;
      for (final entry in branchTimePolicyDefaults.entries) {
        _values['timePolicy.${entry.key}'] = policy[entry.key] ?? entry.value;
      }
    }
    _prepare();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final session = context.read<SessionController>();
      final result = await Future.wait([
        session.api.get('/branches'),
        session.api.get('/employees'),
        session.api.get('/shifts'),
      ]);
      if (!mounted) return;
      _branches = (result[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _employees = (result[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _shifts = (result[2] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((s) => s['employeeId'] == session.user!.id)
          .toList();
      if (!_editing && widget.resource == 'employees') {
        _values['role'] = 'employee';
        _values['status'] = 'pending';
      }
    } catch (e) {
      _error = errorMessage(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Field> _fields() {
    final branches = {
      for (final b in _branches) b['id'].toString(): b['name'].toString(),
    };
    final eligible = _employees.where(
      (u) =>
          u['status'] == 'active' &&
          (_values['branchId'] == null || u['branchId'] == _values['branchId']),
    );
    final people = {
      for (final u in eligible) u['id'].toString(): u['fullName'].toString(),
    };
    final shifts = {
      for (final s in _shifts)
        s['id'].toString():
            '${s['title']} · ${dateText(s['startsAt'])} ${timeText(s['startsAt'])}',
    };
    return switch (widget.resource) {
      'employees' => [
        const _Field('fullName', 'Họ và tên'),
        const _Field('username', 'Tên đăng nhập', kind: 'username'),
        const _Field('email', 'Email', kind: 'email'),
        _Field(
          'password',
          _editing
              ? 'Mật khẩu mới (để trống nếu giữ nguyên)'
              : 'Mật khẩu ban đầu',
          kind: 'password',
          required: !_editing,
        ),
        const _Field(
          'role',
          'Vai trò',
          kind: 'select',
          choices: {
            'employee': 'Nhân viên',
            'manager': 'Quản lý',
            'admin': 'Quản trị viên',
          },
        ),
        const _Field(
          'status',
          'Trạng thái',
          kind: 'select',
          choices: {
            'pending': 'Chờ duyệt',
            'active': 'Đang hoạt động',
            'suspended': 'Tạm khóa',
          },
        ),
        _Field(
          'branchId',
          'Chi nhánh',
          kind: 'select',
          required: false,
          choices: branches,
        ),
      ],
      'branches' => [
        const _Field('name', 'Tên chi nhánh'),
        const _Field('address', 'Địa chỉ', kind: 'multiline'),
        const _Field(
          'latitude',
          'Vĩ độ',
          kind: 'number',
          minimum: -90,
          maximum: 90,
        ),
        const _Field(
          'longitude',
          'Kinh độ',
          kind: 'number',
          minimum: -180,
          maximum: 180,
        ),
        const _Field(
          'radiusMeters',
          'Bán kính chấm công (m)',
          kind: 'number',
          minimum: 20,
          maximum: 200000,
        ),
        for (final entry in branchTimePolicyLabels.entries)
          _Field(
            'timePolicy.${entry.key}',
            entry.value,
            kind: 'integer',
            minimum: 0,
            maximum: 1440,
          ),
      ],
      'shifts' => [
        const _Field('title', 'Tên ca làm'),
        _Field('branchId', 'Chi nhánh', kind: 'select', choices: branches),
        _Field(
          'employeeId',
          'Nhân viên được phân công',
          kind: 'select',
          choices: people,
        ),
        const _Field('startsAt', 'Bắt đầu ca', kind: 'date'),
        const _Field('endsAt', 'Kết thúc ca', kind: 'date'),
      ],
      'corrections' => [
        if (!_editing)
          _Field(
            'shiftId',
            'Ca cần điều chỉnh',
            kind: 'select',
            choices: shifts,
          ),
        const _Field(
          'requestedCheckIn',
          'Giờ vào đề nghị',
          kind: 'date',
          required: false,
        ),
        const _Field(
          'requestedCheckOut',
          'Giờ ra đề nghị',
          kind: 'date',
          required: false,
        ),
        const _Field('reason', 'Lý do điều chỉnh', kind: 'multiline'),
      ],
      _ => [],
    };
  }

  TextEditingController _controller(_Field f) => _controllers.putIfAbsent(
    f.key,
    () => TextEditingController(text: _values[f.key]?.toString() ?? ''),
  );
  Future<void> _pickDate(_Field f) async {
    final initial =
        DateTime.tryParse(_values[f.key]?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(
      () => _values[f.key] = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ).toUtc().toIso8601String(),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    final input = <String, dynamic>{};
    for (final f in _fields()) {
      dynamic value;
      if (f.kind == 'select' || f.kind == 'date') {
        value = _values[f.key];
      } else {
        final text = _controller(f).text;
        if (f.kind == 'password' && text.isEmpty && _editing) continue;
        value = f.kind == 'number'
            ? double.parse(text.trim().replaceAll(',', '.'))
            : f.kind == 'integer'
            ? int.parse(text.trim())
            : f.kind == 'password'
            ? text
            : text.trim();
      }
      if (value == '' || value == null) {
        if (!f.required) value = null;
      }
      input[f.key] = value;
    }
    if (widget.resource == 'corrections' &&
        input['requestedCheckIn'] == null &&
        input['requestedCheckOut'] == null &&
        _values['requestedCheckIn'] == null &&
        _values['requestedCheckOut'] == null) {
      setState(
        () => _error = 'Nhập ít nhất một giờ vào hoặc giờ ra cần điều chỉnh.',
      );
      return;
    }
    if (widget.resource == 'branches') {
      input['timePolicy'] = {
        for (final key in branchTimePolicyDefaults.keys)
          key: input.remove('timePolicy.$key'),
      };
    }
    Json changes;
    try {
      changes = resourceMutation(
        widget.resource,
        input,
        initial: widget.initial,
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      showMessage(context, error.message);
      return;
    }
    if (changes.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = context.read<SessionController>().api;
      if (_editing) {
        await api.patch(
          '/${widget.resource}/${widget.initial!['id']}',
          changes,
        );
      } else {
        await api.post('/${widget.resource}', changes);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        (_editing ? 'Chỉnh sửa ' : 'Thêm ') +
            resourceLabel(widget.resource).toLowerCase(),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : AppPage(
            children: [
              if (_error != null) Notice(_error!, isError: true),
              if (widget.resource == 'employees')
                const Notice(
                  'Nhân viên cần xác thực email bằng mã xác nhận và được phân chi nhánh trước khi xếp ca.',
                ),
              if (widget.resource == 'shifts' &&
                  widget.initial?['planLocked'] == true)
                const Notice(
                  'Ca đã ghi công hoặc có đơn điều chỉnh: chỉ sửa được tên ca.',
                ),
              if (widget.resource == 'shifts')
                const ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.only(bottom: 16),
                  shape: Border(),
                  collapsedShape: Border(),
                  title: Text('Lưu ý phân ca', style: TextStyle(fontSize: 13)),
                  children: [
                    Text(
                      'Trạng thái ca cập nhật tự động. Nhân viên, chi nhánh và giờ ca sẽ khóa khi có chấm công hoặc đơn điều chỉnh.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              if (widget.resource == 'branches')
                const Notice('Chính sách mới không tự đổi các ca đã tạo.'),
              if (widget.resource == 'branches')
                const ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.only(bottom: 16),
                  shape: Border(),
                  collapsedShape: Border(),
                  title: Text(
                    'Cách áp dụng chính sách',
                    style: TextStyle(fontSize: 13),
                  ),
                  children: [
                    Text(
                      'Giờ chấm công và nhãn muộn/về sớm dùng chính sách tại lúc tạo hoặc xếp lại ca chưa ghi công. Sửa chi nhánh không tự cập nhật các ca cũ.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              if (widget.resource == 'branches')
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            try {
                              final p = await currentPosition();
                              if (mounted) {
                                setState(() {
                                  _controller(const _Field('latitude', ''))
                                      .text = p.latitude
                                      .toString();
                                  _controller(const _Field('longitude', ''))
                                      .text = p.longitude
                                      .toString();
                                });
                              }
                            } catch (e) {
                              if (context.mounted) showFailure(context, e);
                            }
                          },
                    icon: const Icon(Icons.my_location),
                    label: const Text('Lấy tọa độ hiện tại'),
                  ),
                ),
              Surface(
                child: Form(
                  key: _form,
                  child: Column(
                    children: [
                      for (final f in _fields())
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _fieldWidget(f),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.check),
                          label: Text(_saving ? 'Đang lưu…' : 'Lưu thay đổi'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
  );
  Widget _fieldWidget(_Field f) {
    final locked =
        widget.resource == 'shifts' &&
        widget.initial?['planLocked'] == true &&
        {'employeeId', 'branchId', 'startsAt', 'endsAt'}.contains(f.key);
    if (locked) {
      final raw = _values[f.key]?.toString() ?? '';
      final parsed = DateTime.tryParse(raw)?.toLocal();
      final assignedName = widget
          .initial![f.key == 'employeeId' ? 'employeeName' : 'branchName'];
      final text = f.kind == 'date'
          ? (parsed == null
                ? '—'
                : DateFormat('dd/MM/yyyy HH:mm').format(parsed))
          : (f.choices[raw] ?? assignedName ?? 'Đã được phân công').toString();
      return TextFormField(
        initialValue: text,
        enabled: false,
        decoration: InputDecoration(
          labelText: f.label,
          suffixIcon: const Icon(Icons.lock_outline, size: 18),
        ),
      );
    }
    if (f.kind == 'select') {
      final selected = _values[f.key]?.toString();
      final valid = f.choices.containsKey(selected) ? selected : null;
      return DropdownButtonFormField<String>(
        key: ValueKey(f.key + f.choices.keys.join()),
        initialValue: valid,
        isExpanded: true,
        decoration: InputDecoration(labelText: f.label),
        items: [
          if (!f.required)
            const DropdownMenuItem(
              value: '',
              child: Text('Chưa phân chi nhánh'),
            ),
          for (final e in f.choices.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _saving
            ? null
            : (v) => setState(() {
                _values[f.key] = v == '' ? null : v;
                if (f.key == 'branchId' && widget.resource == 'shifts') {
                  _values.remove('employeeId');
                }
              }),
        validator: (v) => f.required && (v == null || v.isEmpty)
            ? 'Vui lòng chọn ${f.label.toLowerCase()}.'
            : null,
      );
    }
    if (f.kind == 'date') {
      final raw = _values[f.key]?.toString();
      final date = DateTime.tryParse(raw ?? '')?.toLocal();
      return TextFormField(
        key: ValueKey(f.key + (raw ?? '')),
        initialValue: date == null
            ? ''
            : DateFormat('dd/MM/yyyy HH:mm').format(date),
        readOnly: true,
        decoration: InputDecoration(
          labelText: f.label,
          suffixIcon: IconButton(
            tooltip: 'Chọn ngày giờ',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () => _pickDate(f),
          ),
        ),
        onTap: () => _pickDate(f),
        validator: (_) =>
            f.required && date == null ? 'Vui lòng chọn ngày giờ.' : null,
      );
    }
    return TextFormField(
      controller: _controller(f),
      obscureText: f.kind == 'password',
      maxLines: f.kind == 'multiline' ? 3 : 1,
      enabled: !_saving,
      keyboardType: f.kind == 'number' || f.kind == 'integer'
          ? TextInputType.numberWithOptions(
              decimal: f.kind == 'number',
              signed: f.minimum < 0,
            )
          : f.kind == 'email'
          ? TextInputType.emailAddress
          : TextInputType.text,
      decoration: InputDecoration(labelText: f.label),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) {
          return f.required ? 'Vui lòng nhập ${f.label.toLowerCase()}.' : null;
        }
        if (f.kind == 'number') {
          final number = double.tryParse(text.replaceAll(',', '.'));
          if (number == null ||
              !number.isFinite ||
              number < f.minimum ||
              number > f.maximum) {
            return 'Giá trị từ ${f.minimum} đến ${f.maximum}.';
          }
        }
        if (f.kind == 'integer') {
          final number = int.tryParse(text);
          if (number == null || number < f.minimum || number > f.maximum) {
            return 'Nhập số nguyên từ 0 đến 1.440 phút.';
          }
        }
        if (f.kind == 'email' &&
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
          return 'Email chưa hợp lệ.';
        }
        if (f.kind == 'username' &&
            !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.]{2,31}$').hasMatch(text)) {
          return 'Tên đăng nhập cần 3–32 ký tự không dấu.';
        }
        if (f.kind == 'password' && (value?.length ?? 0) < 10) {
          return 'Mật khẩu cần ít nhất 10 ký tự.';
        }
        if (f.key == 'reason' && text.length < 5) {
          return 'Mô tả lý do ít nhất 5 ký tự.';
        }
        if (f.kind == 'text' && text.length < 2) {
          return 'Vui lòng nhập ít nhất 2 ký tự.';
        }
        return null;
      },
    );
  }
}
