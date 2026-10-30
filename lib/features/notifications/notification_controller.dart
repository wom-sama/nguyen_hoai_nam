import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/session.dart';
import 'messaging_gateway.dart';

abstract interface class NotificationConsentStore {
  Future<bool> read(String scope);
  Future<void> write(String scope, bool enabled);
}

class SecureNotificationConsentStore implements NotificationConsentStore {
  final _storage = const FlutterSecureStorage();
  String _key(String scope) =>
      'notifications_${sha256.convert(utf8.encode(scope))}';
  @override
  Future<bool> read(String scope) async =>
      await _storage.read(key: _key(scope)) == 'yes';
  @override
  Future<void> write(String scope, bool enabled) =>
      _storage.write(key: _key(scope), value: enabled ? 'yes' : 'no');
}

class NotificationNavigation {
  const NotificationNavigation(this.hint, this.revision);
  final PushHint hint;
  final int revision;
}

class NotificationController extends ChangeNotifier {
  NotificationController({
    required this.session,
    required this.gateway,
    NotificationConsentStore? consentStore,
  }) : consentStore = consentStore ?? SecureNotificationConsentStore() {
    session.addListener(_sessionChanged);
  }

  final SessionController session;
  final MessagingGateway gateway;
  final NotificationConsentStore consentStore;
  final _banners = StreamController<PushHint>.broadcast();
  Stream<PushHint> get banners => _banners.stream;
  NotificationNavigation? navigation;
  String status = 'Chưa bật thông báo trên thiết bị này.';
  bool enabled = false, working = false, optedIn = false;
  bool cleanupIncomplete = false;
  String? _projectId, _scope, _deviceId, _boundFid;
  bool _initialized = false, _disposed = false, _suspended = false;
  Future<void>? _initializing;
  int _generation = 0, _revision = 0;
  Future<void> _operations = Future.value();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<String, PushHint> _pending = {};

  String? get _currentScope {
    final user = session.user;
    if (session.restoring || user == null || !user.isActive || _suspended) {
      return null;
    }
    return '${session.api.baseUrl}|${user.id}';
  }

  bool _current(int generation, String scope) =>
      !_disposed && generation == _generation && scope == _currentScope;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serial(Future<void> Function() operation) {
    final task = _operations.then((_) => operation());
    _operations = task.catchError((Object _) {});
    return task;
  }

  Future<void> initialize() {
    if (_initialized) return refresh();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    try {
      _projectId = await gateway.initialize();
      if (_disposed) return;
      await gateway.setAutoInit(false);
      _subscriptions.addAll([
        gateway.registrations.listen(
          _registrationChanged,
          onError: _streamError,
        ),
        gateway.foreground.listen((hint) {
          if (enabled &&
              _currentScope != null &&
              hint.recipientId == session.user?.id) {
            if (hint.destination == NotificationDestination.profile) {
              unawaited(open(hint));
            } else {
              _banners.add(hint);
            }
          }
        }, onError: _streamError),
        gateway.opened.listen(
          (hint) => unawaited(open(hint)),
          onError: _streamError,
        ),
      ]);
      final initial = await gateway.initialMessage();
      if (initial != null) {
        if (initial.destination == NotificationDestination.profile) {
          await open(initial);
        } else {
          _remember(initial);
        }
      }
      _initialized = true;
      await refresh();
    } catch (_) {
      status =
          'Thông báo chưa sẵn sàng. Kiểm tra kết nối mạng rồi thử lại sau.';
      enabled = false;
      _changed();
    }
  }

  void _streamError(Object error) {
    enabled = false;
    status = 'Kết nối thông báo bị gián đoạn. Chạm thử lại trong tài khoản.';
    _changed();
  }

  void _sessionChanged() {
    if (session.user == null) _suspended = false;
    if (!_disposed && _initialized && _scope != _currentScope) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (!_initialized) return initialize();
    final scope = _currentScope;
    if (_scope != scope) {
      _scope = scope;
      _generation++;
      enabled = optedIn = false;
      navigation = null;
      _deviceId = _boundFid = null;
    }
    final generation = _generation;
    await _serial(() async {
      if (_disposed || generation != _generation) return;
      try {
        if (scope == null) {
          await _deactivate();
          status = 'Đăng nhập tài khoản đã được duyệt để bật thông báo.';
        } else {
          final consent = await consentStore.read(scope);
          if (!_current(generation, scope)) return;
          optedIn = consent;
          if (consent) {
            await _activate(generation, scope, askPermission: false);
          } else {
            await _deactivate();
            status = 'Chưa bật thông báo trên thiết bị này.';
          }
        }
      } catch (_) {
        enabled = false;
        try {
          await _deactivate();
        } catch (_) {
          // cleanupIncomplete exposes failure and allows an explicit retry.
        }
        status =
            'Chưa kết nối được thông báo. Chấm công vẫn sử dụng bình thường.';
      } finally {
        _changed();
      }
    });
    if (scope != null && _current(generation, scope)) await _openPending();
  }

  Future<void> enable() async {
    if (!_initialized) await initialize();
    final scope = _currentScope;
    if (!_initialized || scope == null) return;
    _scope = scope;
    final generation = ++_generation;
    optedIn = true;
    enabled = false;
    working = true;
    _changed();
    await _serial(() async {
      try {
        await consentStore.write(scope, true);
        if (_current(generation, scope)) {
          await _activate(generation, scope, askPermission: true);
        }
      } catch (_) {
        if (_current(generation, scope)) {
          enabled = false;
          try {
            await _deactivate();
          } catch (_) {
            // Retain the retry state instead of reporting successful cleanup.
          }
          status =
              'Chưa bật được thông báo. Kiểm tra kết nối mạng rồi thử lại.';
        }
      } finally {
        if (generation == _generation) working = false;
        _changed();
      }
    });
  }

  Future<void> _activate(
    int generation,
    String scope, {
    required bool askPermission,
  }) async {
    final value = await session.api.get('/notifications/status');
    if (!_current(generation, scope) || !optedIn) return;
    if (value is! Map ||
        value['enabled'] != true ||
        value['provider'] != 'fcm' ||
        value['firebaseProjectId'] != _projectId) {
      await _deactivate();
      status = 'Thông báo đang tạm ngừng. Vui lòng thử lại sau.';
      return;
    }
    final allowed = askPermission
        ? await gateway.requestPermission()
        : await gateway.hasPermission();
    if (!_current(generation, scope) || !optedIn) return;
    if (!allowed) {
      await _deactivate();
      status = 'Chưa có quyền thông báo. Bạn có thể cho phép trong cài đặt Android rồi thử lại.';
      return;
    }
    status = 'Đang kết nối thông báo…';
    _changed();
    await gateway.setAutoInit(true);
    if (!_current(generation, scope) || !optedIn) return;
    final fid = await gateway.register();
    if (_current(generation, scope) && optedIn) {
      await _bind(fid, generation, scope);
    }
  }

  void _registrationChanged(String fid) {
    final scope = _currentScope, generation = _generation;
    if (scope == null || !optedIn || fid.isEmpty) return;
    unawaited(
      _serial(() async {
        if (!_current(generation, scope) || !optedIn || fid == _boundFid) {
          return;
        }
        try {
          await _bind(fid, generation, scope);
        } catch (_) {
          if (_current(generation, scope)) {
            enabled = false;
            status =
                'Chưa kết nối được thông báo trên thiết bị này. Chạm thử lại.';
            _changed();
          }
        }
      }),
    );
  }

  Future<void> _bind(String fid, int generation, String scope) async {
    if (fid == _boundFid && enabled) return;
    final recipient = session.user!.id;
    final result = await session.api.post('/notification-devices', {
      'installationId': fid,
      'firebaseProjectId': _projectId,
      'platform': 'android',
    });
    if (result is! Map ||
        result['recipientId'] != recipient ||
        result['installationId'] != fid ||
        result['id'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(result['id'] as String)) {
      throw StateError('Invalid notification registration response');
    }
    // Keep the id for a queued opt-out DELETE, even if its intent invalidated
    // this response. Never keep another account's binding on a new session.
    if (scope == _currentScope) {
      _deviceId = result['id'] as String;
      _boundFid = fid;
    }
    if (!_current(generation, scope) || !optedIn) return;
    enabled = true;
    status = 'Đã bật. Nhận cập nhật ca làm, đơn điều chỉnh công và bàn giao.';
    _changed();
  }

  Future<void> disable() async {
    final scope = _currentScope;
    ++_generation;
    enabled = optedIn = false;
    working = true;
    navigation = null;
    _changed();
    await _serial(() async {
      try {
        if (scope != null) await consentStore.write(scope, false);
        await _deactivate(deleteBindingScope: scope);
        status = 'Đã tắt thông báo trên thiết bị này.';
      } catch (_) {
        status = 'Đã ngừng nhận thông báo trong ứng dụng. Kết nối mạng rồi bấm tắt lại để hoàn tất.';
      } finally {
        working = false;
        _changed();
      }
    });
  }

  Future<void> _deactivate({String? deleteBindingScope}) async {
    enabled = false;
    // Attempt all cleanup steps even if one native/network operation fails.
    Object? failure;
    try {
      await gateway.setAutoInit(false);
    } catch (error) {
      failure = error;
    }
    try {
      await gateway.unregister();
    } catch (error) {
      failure ??= error;
    }
    final id = _deviceId;
    if (id != null &&
        deleteBindingScope != null &&
        deleteBindingScope == _currentScope) {
      try {
        await session.api.delete('/notification-devices/$id');
        _deviceId = _boundFid = null;
      } catch (error) {
        failure ??= error;
      }
    }
    cleanupIncomplete = failure != null;
    if (failure != null) throw failure;
  }

  /// Called before session.logout(). Server logout revokes all devices belonging
  /// to that refresh session, including a POST already in flight.
  void suspendForLogout() {
    _suspended = true;
    _generation++;
    enabled = optedIn = false;
    navigation = null;
    _changed();
    if (_initialized) {
      unawaited(
        _serial(() async {
          try {
            await _deactivate();
          } catch (_) {
            /* Server logout also revokes. */
          }
        }),
      );
    }
  }

  void _remember(PushHint hint) {
    // One latest route hint per recipient is enough: every destination loads
    // its complete authorized list, so events/details are never lost here.
    if (_pending.length >= 8 && !_pending.containsKey(hint.recipientId)) {
      _pending.remove(_pending.keys.first);
    }
    _pending[hint.recipientId] = hint;
  }

  Future<void> open(PushHint hint) async {
    if (hint.destination == NotificationDestination.profile) {
      if (_currentScope != null && hint.recipientId == session.user?.id) {
        await session.syncProfile();
      }
      return;
    }
    _remember(hint);
    await _openPending();
  }

  Future<void> _openPending() async {
    final scope = _currentScope, user = session.user;
    if (scope == null || user == null) return;
    final hint = _pending[user.id];
    if (hint == null) return;
    final generation = _generation;
    try {
      final resource = switch (hint.destination) {
        NotificationDestination.home => 'shifts',
        NotificationDestination.corrections => 'corrections',
        NotificationDestination.handovers => 'handovers',
        NotificationDestination.profile => 'me',
      };
      await session.api.get('/$resource');
      if (!_current(generation, scope) ||
          session.user?.id != hint.recipientId) {
        return;
      }
      if (!identical(_pending[user.id], hint)) return;
      _pending.remove(user.id);
      navigation = NotificationNavigation(hint, ++_revision);
      _changed();
    } catch (_) {
      if (_current(generation, scope)) {
        status = 'Chưa tải được cập nhật. Mở lại thông báo khi có mạng.';
        _changed();
      }
    }
  }

  void consumeNavigation(NotificationNavigation value) {
    if (identical(navigation, value)) navigation = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    session.removeListener(_sessionChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_banners.close());
    super.dispose();
  }
}
