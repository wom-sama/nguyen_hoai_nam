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
  bool restoring = false, busy = false;
  String? error;
  int _epoch = 0;
  Future<bool>? _refreshTask;

  Future<void> restore() async {
    restoring = true;
    error = null;
    notifyListeners();
    try {
      final saved = await store.read();
      if (!api.isConfigured && saved?.baseUrl.isNotEmpty == true) {
        api.configure(saved!.baseUrl);
      }
      if (!api.isConfigured) return;
      if (saved != null &&
          saved.baseUrl.isNotEmpty &&
          ApiClient.validateUrl(saved.baseUrl) != api.baseUrl) {
        await _dropTokens();
        return;
      }
      api.accessToken = saved?.accessToken;
      if (api.accessToken == null && saved?.refreshToken != null) {
        if (!await _refreshAccess()) return;
      }
      if (api.accessToken != null) {
        user = AppUser.fromJson(await api.get('/me') as Json);
      }
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) await _dropTokens();
      error = e.message;
    } on FormatException {
      error = 'Phiên lưu trên thiết bị không hợp lệ. Vui lòng đăng nhập lại.';
      await _dropTokens();
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<bool> _run(Future<void> Function(int epoch) action) async {
    if (busy) return false;
    busy = true;
    error = null;
    final epoch = _epoch;
    notifyListeners();
    try {
      await action(epoch);
      return epoch == _epoch;
    } on ApiException catch (e) {
      if (epoch == _epoch) error = e.message;
      return false;
    } on FormatException {
      if (epoch == _epoch) {
        error = 'Máy chủ trả dữ liệu chưa hợp lệ. Vui lòng thử lại.';
      }
      return false;
    } catch (e) {
      if (epoch == _epoch) {
        error = 'Chưa hoàn tất được thao tác. Vui lòng thử lại.';
      }
      return false;
    } finally {
      if (epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _begin(String path, Json body) => _run((epoch) async {
    final value = await api.post(path, body, authenticated: false) as Json;
    if (epoch == _epoch) challenge = AuthChallenge.fromJson(value);
  });

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
    if (epoch != _epoch) return;
    final access = value['accessToken'] as String;
    final refresh = value['refreshToken'] as String;
    final nextUser = value['user'] == null
        ? null
        : AppUser.fromJson(value['user'] as Json);
    await store.write(
      StoredSession(
        baseUrl: api.baseUrl,
        accessToken: access,
        refreshToken: refresh,
      ),
    );
    if (epoch != _epoch) return;
    api.accessToken = access;
    if (nextUser != null) user = nextUser;
    challenge = null;
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
    if (epoch == _epoch) challenge = AuthChallenge.fromJson(value);
  });

  Future<bool> _refreshAccess() async {
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
    final saved = await store.read();
    if (saved?.refreshToken == null) {
      await _dropTokens();
      return false;
    }
    try {
      final value = await api.post('/auth/refresh', {
        'refreshToken': saved!.refreshToken,
      }, authenticated: false) as Json;
      await _accept(value, epoch);
      return epoch == _epoch;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _dropTokens();
        notifyListeners();
        return false;
      }
      rethrow;
    }
  }

  Future<bool> refreshProfile() => _run((epoch) async {
    final value = await api.get('/me') as Json;
    if (epoch == _epoch) user = AppUser.fromJson(value);
  });

  Future<void> _dropTokens() async {
    user = null;
    challenge = null;
    api.accessToken = null;
    await store.write(StoredSession(baseUrl: api.baseUrl));
  }

  Future<void> logout() async {
    _epoch++;
    busy = true;
    notifyListeners();
    String? remoteError;
    try {
      final saved = await store.read();
      if (saved?.refreshToken != null) {
        await api.post('/auth/logout', {
          'refreshToken': saved!.refreshToken,
        }, authenticated: false);
      }
    } on ApiException {
      remoteError = 'Đã đóng phiên trên thiết bị này. Chưa liên hệ được máy chủ để thu hồi phiên từ xa.';
    } finally {
      await _dropTokens();
      error = remoteError;
      busy = false;
      notifyListeners();
    }
  }

  void cancelChallenge() {
    _epoch++;
    challenge = null;
    error = null;
    busy = false;
    notifyListeners();
  }
}
