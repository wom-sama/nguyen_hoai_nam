import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import 'share_timing.dart';

/// Schedules the nearest local privacy deadline independently of network I/O.
/// The injected clock keeps deadline behavior verifiable without a map/network.
class LocationShareExpiry {
  LocationShareExpiry({required this.onExpire, DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final VoidCallback onExpire;
  final DateTime Function() _now;
  Timer? _timer;
  List<DateTime> _deadlines = const [];
  bool _disposed = false;
  final Set<String> _hiddenIds = {};

  void forget(String id) => _hiddenIds.add(id);
  void restore(String id) => _hiddenIds.remove(id);

  List<Json> visibleRows(List<Json> rows) {
    final now = _now();
    return rows
        .where(
          (row) =>
              !_hiddenIds.contains(row['id']) &&
              (DateTime.tryParse(row['expiresAt']?.toString() ?? '')
                      ?.isAfter(now) ??
                  false),
        )
        .toList();
  }

  void schedule(List<Json> rows, {DateTime? consentExpiresAt}) {
    if (_disposed) return;
    _deadlines = [
      for (final row in rows)
        if (DateTime.tryParse(row['expiresAt']?.toString() ?? '')
            case final DateTime deadline)
          deadline,
      ?consentExpiresAt,
    ];
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    if (_disposed) return;
    final now = _now();
    final upcoming =
        _deadlines.where((deadline) => deadline.isAfter(now)).toList()..sort();
    if (upcoming.isEmpty) return;
    _timer = Timer(upcoming.first.difference(now), () {
      if (_disposed) return;
      onExpire();
      _arm();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen>
    with WidgetsBindingObserver {
  late Future<List<Json>> _future;
  Timer? _timer;
  late final LocationShareExpiry _expiry;
  List<Json> _loadedRows = const [];
  bool _loading = false;
  String? _shareId, _error;
  DateTime? _until;
  bool _busy = false, _updating = false, _collecting = false, _paused = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _expiry = LocationShareExpiry(onExpire: _expire);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
  }

  void _load() {
    if (_loading) return;
    _loading = true;
    final session = context.read<SessionController>(),
        userId = session.user!.id;
    _future = session.api
        .get('/location-shares')
        .then((value) {
          final rows = (value as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final own = _expiry
              .visibleRows(rows)
              .where((row) => row['userId'] == userId)
              .firstOrNull;
          if (mounted) {
            setState(() {
              _loadedRows = rows;
              _error = null;
              if (own == null && !_updating) {
                _shareId = null;
                _until = null;
                _collecting = false;
              } else if (own != null && _shareId == null) {
                _shareId = own['id'] as String;
                _until = DateTime.parse(own['expiresAt'] as String);
              }
            });
            _scheduleExpiry();
          }
          return rows;
        })
        .whenComplete(() => _loading = false);
  }

  void _scheduleExpiry() =>
      _expiry.schedule(_loadedRows, consentExpiresAt: _until);

  void _expire() {
    if (!mounted) return;
    setState(() {
      if (_until != null && !_until!.isAfter(DateTime.now())) {
        if (_shareId != null) _expiry.forget(_shareId!);
        _shareId = null;
        _until = null;
        _collecting = false;
      }
    });
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  Future<void> _tick() async {
    if (!mounted || _busy || _updating || _paused) return;
    if (_collecting &&
        _shareId != null &&
        (_until?.isAfter(DateTime.now()) ?? false)) {
      await _send(renew: false);
    }
    if (mounted) {
      try {
        await _refresh();
      } catch (e) {
        if (mounted) setState(() => _error = errorMessage(e));
      }
    }
  }

  Future<void> _send({required bool renew}) async {
    if (_updating) return;
    _updating = true;
    try {
      var minutes = renew
          ? 15
          : _until == null
          ? null
          : renewalMinutes(_until!, DateTime.now());
      if (minutes == null) {
        if (mounted) setState(() => _collecting = false);
        return;
      }
      final api = context.read<SessionController>().api;
      final p = await currentPosition();
      minutes = renew
          ? 15
          : _until == null
          ? null
          : renewalMinutes(_until!, DateTime.now());
      if (minutes == null || _paused) {
        if (mounted) setState(() => _collecting = false);
        return;
      }
      final result = await api.post('/location-shares', {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'accuracyMeters': p.accuracy,
        'ttlMinutes': minutes,
      }) as Json;
      if (mounted) {
        setState(() {
          if (!renew && !(_until?.isAfter(DateTime.now()) ?? false)) return;
          _shareId = result['id'] as String;
          if (renew) _expiry.restore(_shareId!);
          if (renew) _until = DateTime.parse(result['expiresAt'] as String);
          _collecting = true;
          _error = null;
        });
        _scheduleExpiry();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _collecting = false;
        });
      }
    } finally {
      _updating = false;
    }
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      if (_shareId != null) {
        await _stop();
      } else {
        await _send(renew: true);
      }
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final id = _shareId;
    if (id == null) return;
    await context.read<SessionController>().api.delete('/location-shares/$id');
    if (mounted) {
      setState(() {
        _expiry.forget(id);
        _shareId = null;
        _until = null;
        _collecting = false;
      });
      _scheduleExpiry();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _paused = true;
      _collecting = false;
    } else if (state == AppLifecycleState.resumed) {
      _paused = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _expiry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;
    return Scaffold(
      appBar: AppBar(title: const Text('Vị trí trong ca')),
      body: AppPage(
        onRefresh: _refresh,
        children: [
          const PageHeading(
            eyebrow: 'CHIA SẺ CÓ THỜI HẠN',
            title: 'Chia sẻ vị trí',
          ),
          if (_error != null) Notice(_error!, isError: true),
          Surface(
            color: AppColors.palePink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _shareId == null
                      ? 'Bạn đang không chia sẻ vị trí'
                      : _collecting
                      ? 'Đang cập nhật vị trí'
                      : 'Điểm vị trí cuối đang được chia sẻ',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  _until == null
                      ? 'Chỉ chia sẻ khi bạn chủ động bật.'
                      : 'Tự hết hạn lúc ${timeText(_until!.toIso8601String())}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Quản lý cùng chi nhánh xem vị trí tối đa 15 phút. Rời màn hình sẽ tạm dừng cập nhật; điểm cuối còn hiển thị đến khi hết hạn hoặc bạn bấm Dừng chia sẻ.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _toggle,
                  icon: Icon(
                    _shareId == null
                        ? Icons.share_location
                        : Icons.stop_circle_outlined,
                  ),
                  label: Text(
                    _busy
                        ? 'Đang xử lý…'
                        : _shareId == null
                        ? 'Chia sẻ trong 15 phút'
                        : 'Dừng chia sẻ',
                  ),
                ),
                if (_shareId != null &&
                    !_collecting &&
                    (_until?.isAfter(DateTime.now()) ?? false))
                  TextButton(
                    onPressed: _busy ? null : () => _send(renew: false),
                    child: const Text('Tiếp tục trong thời hạn còn lại'),
                  ),
              ],
            ),
          ),
          Text(
            user.canManage ? 'Các vị trí đang được chia sẻ' : 'Vị trí của bạn',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AsyncPanel<List<Json>>(
            future: _future,
            keepDataWhileLoading: true,
            onRetry: () => setState(_load),
            builder: (loaded) {
              final rows = _expiry.visibleRows(loaded);
              if (rows.isEmpty) {
                return const EmptyState(
                  title: 'Chưa có vị trí đang chia sẻ',
                  message: 'Chỉ những vị trí còn trong thời hạn chia sẻ mới hiển thị ở đây.',
                  icon: Icons.location_off_outlined,
                );
              }
              final first = rows.first;
              final center = LatLng(
                (first['latitude'] as num).toDouble(),
                (first['longitude'] as num).toDouble(),
              );
              return Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 300,
                      child: FlutterMap(
                        key: const ValueKey('location-map'),
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'com.example.nguyen_hoai_nam_2380601398',
                            maxNativeZoom: 19,
                          ),
                          MarkerLayer(
                            markers: rows
                                .map(
                                  (r) => Marker(
                                    point: LatLng(
                                      (r['latitude'] as num).toDouble(),
                                      (r['longitude'] as num).toDouble(),
                                    ),
                                    width: 44,
                                    height: 44,
                                    child: Tooltip(
                                      message:
                                          r['fullName']?.toString() ?? 'Vị trí',
                                      child: const Icon(
                                        Icons.location_pin,
                                        color: AppColors.pink,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                'OpenStreetMap contributors',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final row in rows)
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row['fullName']?.toString() ?? 'Bạn',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          InfoRow('Cập nhật', timeText(row['updatedAt'])),
                          InfoRow('Hết hạn', timeText(row['expiresAt'])),
                          InfoRow(
                            'Sai số',
                            '${(row['accuracyMeters'] as num).toStringAsFixed(0)} m',
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
