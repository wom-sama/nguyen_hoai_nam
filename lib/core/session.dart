import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'models.dart';

abstract interface class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession value);
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<StoredSession?> read() async {
    final raw = await _storage.read(key: 'attendance_session');
    if (raw == null) return null;
    final values = jsonDecode(raw) as Map<String, dynamic>;
    return StoredSession(
      baseUrl: values['server'] as String? ?? '',
      accessToken: values['access'] as String?,
      refreshToken: values['refresh'] as String?,
    );
  }

  @override
  Future<void> write(StoredSession value) async {
    await _storage.write(
      key: 'attendance_session',
      value: jsonEncode({
        'server': value.baseUrl,
        'access': value.accessToken,
        'refresh': value.refreshToken,
      }),
    );
  }
}

class SessionController extends ChangeNotifier {
  SessionController({required this.api, SessionStore? store})
    : store = store ?? SecureSessionStore() {
    api.onUnauthorized = _refreshAccess;
  }
  final ApiClient api;
  final SessionStore store;
  AppUser? user;
  AuthChallenge? challenge;
  String? challengeUsername;
  bool restoring = false, busy = false;
  bool restoreRetryable = false;
  String? error;
  String? profileSyncError;
  DateTime? profileSyncedAt;
  int _epoch = 0;
  Future<bool>? _refreshTask;
  Future<bool>? _profileTask;
  Future<void> _storeWrites = Future.value();
  bool _disposed = false;

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  int _advanceEpoch() {
    _epoch++;
    _refreshTask = null;
    _profileTask = null;
    profileSyncError = null;
    profileSyncedAt = null;
    restoring = false;
    restoreRetryable = false;
    return _epoch;
  }

  Future<StoredSession?> _readSession() async {
    await _storeWrites;
    return store.read();
  }

  Future<void> _persist(StoredSession value, int epoch) {
    final operation = _storeWrites.then((_) async {
      if (epoch == _epoch) await store.write(value);
    });
    // Each caller still receives its write failure; later writes remain usable.
    _storeWrites = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> restore() async {
    if (_disposed || restoring) return;
    final epoch = _epoch;
    var hasSavedTokens = false;
    restoring = true;
    restoreRetryable = false;
    error = null;
    _changed();
    try {
      final saved = await _readSession();
      if (!_current(epoch)) return;
      hasSavedTokens =
          saved?.accessToken != null || saved?.refreshToken != null;
      if (!api.isConfigured && saved?.baseUrl.isNotEmpty == true) {
        api.configure(saved!.baseUrl);
      }
      if (!api.isConfigured) return;
      if (saved != null &&
          saved.baseUrl.isNotEmpty &&
          ApiClient.validateUrl(saved.baseUrl) != api.baseUrl) {
        await _dropTokens(epoch);
        return;
      }
      api.accessToken = saved?.accessToken;
      if (api.accessToken == null && saved?.refreshToken != null) {
        if (!await _refreshAccess()) return;
      }
      if (!_current(epoch)) return;
      if (api.accessToken != null) {
        final value = await api.get('/me') as Json;
        if (_current(epoch)) {
          user = AppUser.fromJson(value);
          profileSyncedAt = DateTime.now();
        }
      }
    } on ApiException catch (e) {
      if (!_current(epoch)) return;
      error = e.message;
      if (e.status == 401 || e.status == 403) {
        await _dropTokens(epoch);
      } else {
        restoreRetryable = hasSavedTokens && user == null;
      }
    } on FormatException {
      if (!_current(epoch)) return;
      error = 'Phiên lưu trên thiết bị không hợp lệ. Vui lòng đăng nhập lại.';
      await _dropTokens(epoch);
    } finally {
      if (_current(epoch)) {
        restoring = false;
        _changed();
      }
    }
  }

  Future<bool> _run(Future<void> Function(int epoch) action) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    final epoch = _epoch;
    _changed();
    try {
      await action(epoch);
      return _current(epoch);
    } on ApiException catch (e) {
      if (_current(epoch)) error = e.message;
      return false;
    } on FormatException {
      if (_current(epoch)) {
        error = 'Máy chủ trả dữ liệu chưa hợp lệ. Vui lòng thử lại.';
      }
      return false;
    } catch (e) {
      if (_current(epoch)) {
        error = 'Chưa hoàn tất được thao tác. Vui lòng thử lại.';
      }
      return false;
    } finally {
      if (_current(epoch)) {
        busy = false;
        _changed();
      }
    }
  }

  Future<bool> _begin(String path, Json body) {
    if (busy || _disposed) return Future.value(false);
    _advanceEpoch();
    final username = body['username']?.toString().trim();
    challenge = null;
    challengeUsername = null;
    return _run((epoch) async {
      final value = await api.post(path, body, authenticated: false) as Json;
      if (_current(epoch)) {
        challenge = AuthChallenge.fromJson(value);
        challengeUsername = username;
      }
    });
  }

  Future<bool> login(String username, String password) => _begin(
    '/auth/login',
    {'username': username.trim(), 'password': password},
  );
  Future<bool> register(Json values) => _begin('/auth/register', values);
  Future<bool> faceLogin(String username, String imageBase64) => _begin(
    '/auth/face-login',
    {'username': username.trim(), 'imageBase64': imageBase64},
  );

  Future<void> _accept(Json value, int epoch) async {
    if (!_current(epoch)) return;
    final access = value['accessToken'] as String;
    final refresh = value['refreshToken'] as String;
    final nextUser = value['user'] == null
        ? null
        : AppUser.fromJson(value['user'] as Json);
    await _persist(
      StoredSession(
        baseUrl: api.baseUrl,
        accessToken: access,
        refreshToken: refresh,
      ),
      epoch,
    );
    if (!_current(epoch)) return;
    api.accessToken = access;
    if (nextUser != null) {
      user = nextUser;
      profileSyncedAt = DateTime.now();
      profileSyncError = null;
    }
    challenge = null;
    challengeUsername = null;
  }

  Future<bool> verifyOtp(String code) => _run((epoch) async {
    final current = challenge;
    if (current == null) {
      throw const ApiException('CHALLENGE_REQUIRED', 'Vui lòng đăng nhập lại.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const ApiException(
        'OTP_REQUIRED',
        'Vui lòng nhập đủ 6 chữ số của mã OTP.',
      );
    }
    final value = await api.post('/auth/verify-otp', {
      'challengeId': current.id,
      'code': code.trim(),
    }, authenticated: false) as Json;
    await _accept(value, epoch);
  });

  Future<bool> resendOtp() => _run((epoch) async {
    final current = challenge;
    if (current == null) return;
    final value = await api.post('/auth/resend-otp', {
      'challengeId': current.id,
    }, authenticated: false) as Json;
    if (_current(epoch)) challenge = AuthChallenge.fromJson(value);
  });

  Future<bool> _refreshAccess() async {
    if (_disposed) return false;
    final running = _refreshTask;
    if (running != null) return running;
    final task = _doRefresh();
    _refreshTask = task;
    try {
      return await task;
    } finally {
      if (identical(_refreshTask, task)) _refreshTask = null;
    }
  }

  Future<bool> _doRefresh() async {
    final epoch = _epoch;
    final saved = await _readSession();
    if (!_current(epoch)) return false;
    if (saved?.refreshToken == null) {
      await _dropTokens(epoch);
      return false;
    }
    try {
      final value = await api.post('/auth/refresh', {
        'refreshToken': saved!.refreshToken,
      }, authenticated: false) as Json;
      await _accept(value, epoch);
      return _current(epoch);
    } on ApiException catch (e) {
      if (!_current(epoch)) return false;
      if (e.status == 401 || e.status == 403) {
        final latest = await _readSession();
        if (!_current(epoch) || latest?.refreshToken != saved?.refreshToken) {
          return false;
        }
        await _dropTokens(epoch);
        return false;
      }
      rethrow;
    }
  }

  /// Silent foreground/notification sync. A network failure keeps the session.
  Future<bool> syncProfile() {
    if (_disposed || user == null || restoring || busy) {
      return Future.value(false);
    }
    return _fetchProfile();
  }

  Future<bool> refreshProfile() => _run((epoch) async {
    // An explicit refresh after a role/branch edit must read after any older poll.
    final older = _profileTask;
    if (older != null) {
      await older;
      if (!_current(epoch)) return;
      if (identical(_profileTask, older)) _profileTask = null;
    }
    if (!await _fetchProfile() && _current(epoch)) {
      throw ApiException(
        'PROFILE_SYNC',
        profileSyncError ?? 'Chưa cập nhật được tài khoản. Vui lòng thử lại.',
      );
    }
  });

  Future<bool> _fetchProfile() async {
    final running = _profileTask;
    if (running != null) return running;
    final id = user?.id;
    if (id == null || _disposed) return false;
    final task = _loadProfile(_epoch, id);
    _profileTask = task;
    try {
      return await task;
    } finally {
      if (identical(_profileTask, task)) _profileTask = null;
    }
  }

  Future<bool> _loadProfile(int epoch, String id) async {
    try {
      final value = await api.get('/me') as Json;
      if (!_current(epoch) || user?.id != id) return false;
      final next = AppUser.fromJson(value);
      if (next.id != id) throw const FormatException();
      user = next;
      profileSyncedAt = DateTime.now();
      profileSyncError = null;
      _changed();
      return true;
    } catch (failure) {
      if (_current(epoch) && user?.id == id) {
        profileSyncError = failure is ApiException
            ? failure.message
            : 'Chưa cập nhật được tài khoản. Vui lòng thử lại.';
        _changed();
      }
      return false;
    }
  }

  Future<void> _dropTokens(int expectedEpoch, {bool invalidate = true}) async {
    if (!_current(expectedEpoch)) return;
    final epoch = invalidate ? _advanceEpoch() : expectedEpoch;
    user = null;
    challenge = null;
    challengeUsername = null;
    api.accessToken = null;
    busy = false;
    try {
      await _persist(StoredSession(baseUrl: api.baseUrl), epoch);
    } catch (_) {
      if (_current(epoch)) {
        error = 'Chưa xóa được phiên lưu trên thiết bị. Vui lòng thử đăng xuất lại.';
      }
      rethrow;
    } finally {
      if (_current(epoch)) _changed();
    }
  }

  Future<void> logout() async {
    if (_disposed) return;
    final epoch = _advanceEpoch();
    busy = true;
    _changed();
    String? remoteError;
    try {
      final saved = await _readSession();
      if (!_current(epoch)) return;
      if (saved?.refreshToken != null) {
        await api.post('/auth/logout', {
          'refreshToken': saved!.refreshToken,
        }, authenticated: false);
      }
    } on ApiException {
      remoteError = 'Đã đóng phiên trên thiết bị này. Chưa liên hệ được máy chủ để thu hồi phiên từ xa.';
    } finally {
      if (_current(epoch)) {
        await _dropTokens(epoch, invalidate: false);
        if (_current(epoch)) {
          error = remoteError;
          busy = false;
          _changed();
        }
      }
    }
  }

  void cancelChallenge() {
    if (_disposed) return;
    final epoch = _advanceEpoch();
    challenge = null;
    challengeUsername = null;
    error = null;
    busy = false;
    if (user == null) {
      api.accessToken = null;
      unawaited(
        _persist(StoredSession(baseUrl: api.baseUrl), epoch).catchError((
          Object _,
        ) {
          if (_current(epoch)) {
            error =
                'Chưa xóa được phiên đã hủy trên thiết bị. Vui lòng thử lại.';
            _changed();
          }
        }),
      );
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
