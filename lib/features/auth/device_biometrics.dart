import 'dart:convert';
import 'dart:math';

import 'package:biometric_signature/biometric_signature.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';

/// Biometric-protected signatures, never local booleans as authentication proof.
/// Each account/server owns an independent Keystore alias. The only stored data
/// is registration metadata and a public key; private keys stay in the OS.
class DeviceBiometrics {
  DeviceBiometrics({
    BiometricSignature? biometric,
    FlutterSecureStorage? storage,
    Future<String?> Function(String key)? readMetadata,
    Future<void> Function(String key, String value)? writeMetadata,
    Future<void> Function(String key)? deleteMetadata,
  }) : _biometric = biometric ?? BiometricSignature(),
       _storage = storage ?? const FlutterSecureStorage() {
    _read = readMetadata ?? ((key) => _storage.read(key: key));
    _write =
        writeMetadata ??
        ((key, value) => _storage.write(key: key, value: value));
    _delete = deleteMetadata ?? ((key) => _storage.delete(key: key));
  }

  final BiometricSignature _biometric;
  final FlutterSecureStorage _storage;
  late final Future<String?> Function(String key) _read;
  late final Future<void> Function(String key, String value) _write;
  late final Future<void> Function(String key) _delete;
  bool _busy = false;
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  String _username(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9_.]{2,31}$').hasMatch(normalized)) {
      throw const ApiException(
        'USERNAME_INVALID',
        'Nhập tên đăng nhập trước khi dùng vân tay.',
      );
    }
    return normalized;
  }

  String _recordKey(String username) =>
      'hn.fingerprint.v1.${sha256.convert(utf8.encode(username))}';
  String _alias(String server, String username) =>
      'hnfp_${sha256.convert(utf8.encode('$server\n$username'))}';
  String _newDeviceId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final text = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const ApiException(
        'BIOMETRIC_BUSY',
        'Một yêu cầu vân tay đang được xử lý.',
      );
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  Future<bool> isSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final state = await _biometric.biometricAuthAvailable(
        biometricStrength: BiometricStrength.strong,
      );
      return state.canAuthenticate == true &&
          state.hasEnrolledBiometrics == true &&
          (state.availableBiometrics?.contains(BiometricType.fingerprint) ??
              false);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  bool _validKey(KeyInfo info) =>
      info.exists == true &&
      info.isValid == true &&
      info.requiresAuthentication == true &&
      info.allowsDeviceCredentials == false &&
      info.invalidatedByBiometricEnrollment == true;

  Future<Json?> _registration(String username) async {
    final text = await _read(_recordKey(username));
    if (text == null) return null;
    try {
      final row = jsonDecode(text);
      if (row is! Map<String, dynamic> ||
          row['username'] != username ||
          row['deviceId'] is! String ||
          !_uuidPattern.hasMatch(row['deviceId'] as String) ||
          row['server'] is! String ||
          row['keyAlias'] != _alias(row['server'] as String, username) ||
          row['publicKey'] is! String) {
        return null;
      }
      return row;
    } on FormatException {
      return null;
    }
  }

  Future<bool> hasRegistration(String username) async {
    final normalized = _username(username),
        row = await _registration(_username(username));
    if (row == null ||
        row['registered'] != true ||
        row['username'] != normalized) {
      return false;
    }
    final info = await _biometric.getKeyInfo(
      keyAlias: row['keyAlias'] as String,
      checkValidity: true,
      keyFormat: KeyFormat.pem,
    );
    return _validKey(info) && info.publicKey == row['publicKey'];
  }

  /// Setup readiness includes the live server binding, not only cached metadata.
  Future<bool> isRegistered(ApiClient api, String username) async {
    final normalized = _username(username);
    if (!await hasRegistration(normalized)) return false;
    final row = await _registration(normalized);
    if (row == null || row['server'] != api.baseUrl) return false;
    final status = await api.get(
      '/fingerprint/status',
      query: {'deviceId': row['deviceId'] as String},
    );
    return status is Map &&
        status['username'] == normalized &&
        status['registered'] == true;
  }

  Future<void> enroll(ApiClient api, String username) => _exclusive(() async {
    final normalized = _username(username);
    if (!await isSupported()) {
      throw const ApiException(
        'BIOMETRIC_UNSUPPORTED',
        'Thiết bị chưa có vân tay đủ điều kiện. Hãy cài khóa màn hình và đăng ký vân tay trong cài đặt Android.',
      );
    }
    final existing = await _registration(normalized);
    final deviceId = existing?['server'] == api.baseUrl
        ? existing!['deviceId'] as String
        : _newDeviceId();
    final status = await api.get(
      '/fingerprint/status',
      query: {'deviceId': deviceId},
    );
    if (status is! Map || status['canEnroll'] != true) {
      throw const ApiException(
        'FINGERPRINT_REAUTH_REQUIRED',
        'Hãy đăng nhập lại bằng mật khẩu và OTP trong 15 phút trước khi đăng ký vân tay.',
      );
    }
    if (status['username'] != normalized) {
      throw const ApiException(
        'FINGERPRINT_ACCOUNT_MISMATCH',
        'Tên đăng nhập không khớp tài khoản hiện tại.',
      );
    }
    final alias = _alias(api.baseUrl, normalized);
    var info = await _biometric.getKeyInfo(
      keyAlias: alias,
      checkValidity: true,
      keyFormat: KeyFormat.pem,
    );
    if (info.exists == true && info.isValid != true) {
      // Fresh password+OTP was checked before removing this account's invalid key.
      if (!await _biometric.deleteKeys(keyAlias: alias)) {
        throw const ApiException(
          'BIOMETRIC_KEY',
          'Chưa thay được khóa vân tay đã hết hiệu lực. Hãy thử lại.',
        );
      }
      info = KeyInfo(exists: false);
    }
    if (info.exists != true) {
      final created = await _biometric.createKeys(
        keyAlias: alias,
        keyFormat: KeyFormat.pem,
        promptMessage: 'Xác nhận vân tay để liên kết thiết bị',
        config: CreateKeysConfig(
          signatureType: SignatureType.rsa,
          requireAuthentication: true,
          enforceBiometric: true,
          useDeviceCredentials: false,
          setInvalidatedByBiometricEnrollment: true,
          enableDecryption: false,
          failIfExists: true,
          cancelButtonText: 'Hủy',
        ),
      );
      _checkResult(created.code);
      info = await _biometric.getKeyInfo(
        keyAlias: alias,
        checkValidity: true,
        keyFormat: KeyFormat.pem,
      );
    }
    final publicKey = info.publicKey;
    if (!_validKey(info) || publicKey == null || publicKey.trim().isEmpty) {
      throw const ApiException(
        'BIOMETRIC_KEY',
        'Khóa thiết bị không đáp ứng chính sách vân tay. Hãy hủy liên kết và đăng ký lại.',
      );
    }
    final row = <String, dynamic>{
      'username': normalized,
      'server': api.baseUrl,
      'deviceId': deviceId,
      'keyAlias': alias,
      'publicKey': publicKey,
      'registered': false,
    };
    // Retain pending metadata if a network response is lost. A retry reuses the
    // same key and device ID instead of breaking a binding the server may have saved.
    await _write(_recordKey(normalized), jsonEncode(row));
    final registered = await api.post('/fingerprint/enroll', {
      'deviceId': deviceId,
      'publicKey': publicKey,
      'deviceName': 'Điện thoại Android',
    });
    if (registered is! Map ||
        registered['id'] is! String ||
        !_uuidPattern.hasMatch(registered['id'] as String)) {
      throw const ApiException(
        'SERVER_RESPONSE',
        'Chưa xác nhận được liên kết vân tay. Hãy thử lại.',
      );
    }
    row['bindingId'] = registered['id'];
    row['registered'] = true;
    await _write(_recordKey(normalized), jsonEncode(row));
  });

  Future<Json> login(ApiClient api, String username) => _exclusive(() async {
    final normalized = _username(username),
        row = await _registration(_username(username));
    if (row == null ||
        row['registered'] != true ||
        row['server'] != api.baseUrl) {
      throw const ApiException(
        'FINGERPRINT_NOT_ENROLLED',
        'Tài khoản chưa liên kết vân tay trên thiết bị này. Hãy đăng nhập bằng mật khẩu và OTP trước.',
      );
    }
    if (!await isSupported()) {
      throw const ApiException(
        'BIOMETRIC_UNSUPPORTED',
        'Chưa dùng được vân tay trên thiết bị này.',
      );
    }
    final alias = row['keyAlias'] as String;
    final info = await _biometric.getKeyInfo(
      keyAlias: alias,
      checkValidity: true,
      keyFormat: KeyFormat.pem,
    );
    if (!_validKey(info) || info.publicKey != row['publicKey']) {
      throw const ApiException(
        'BIOMETRIC_KEY',
        'Vân tay hoặc khóa thiết bị đã thay đổi. Hãy đăng nhập bằng mật khẩu và OTP để đăng ký lại.',
      );
    }
    final challenge = await api.post('/auth/fingerprint/challenge', {
      'username': normalized,
      'deviceId': row['deviceId'],
    }, authenticated: false);
    final challengeId = challenge is Map ? challenge['challengeId'] : null;
    final payload = challenge is Map ? challenge['payload'] : null;
    final expires = challenge is Map && challenge['expiresAt'] is String
        ? DateTime.tryParse(challenge['expiresAt'] as String)
        : null;
    final remaining = expires?.difference(DateTime.now());
    if (challengeId is! String ||
        !_uuidPattern.hasMatch(challengeId) ||
        payload is! String ||
        payload.length > 2048 ||
        !payload.startsWith('HN-FINGERPRINT-V1\n') ||
        !payload.split('\n').contains(challengeId) ||
        !payload.split('\n').contains(row['deviceId']) ||
        remaining == null ||
        remaining <= Duration.zero ||
        remaining > const Duration(minutes: 3)) {
      throw const ApiException(
        'SERVER_RESPONSE',
        'Thử thách vân tay không hợp lệ hoặc đã hết hạn. Hãy thử lại.',
      );
    }
    final signed = await _biometric.createSignature(
      payload: payload,
      keyAlias: alias,
      promptMessage: 'Xác nhận vân tay để đăng nhập',
      signatureFormat: SignatureFormat.base64,
      config: CreateSignatureConfig(
        allowDeviceCredentials: false,
        cancelButtonText: 'Hủy',
      ),
    );
    _checkResult(signed.code);
    if (signed.authenticationType != AuthenticationType.biometric ||
        signed.signature == null ||
        signed.signature!.isEmpty) {
      throw const ApiException(
        'BIOMETRIC_PROOF',
        'Chưa nhận được chữ ký xác thực bằng sinh trắc học.',
      );
    }
    final session = await api.post('/auth/fingerprint/verify', {
      'username': normalized,
      'deviceId': row['deviceId'],
      'challengeId': challengeId,
      'signature': signed.signature,
    }, authenticated: false);
    if (session is! Map ||
        session['accessToken'] is! String ||
        session['refreshToken'] is! String ||
        session['user'] is! Map ||
        (session['user'] as Map)['username'] != normalized) {
      throw const ApiException(
        'SERVER_RESPONSE',
        'Máy chủ chưa cấp phiên đăng nhập hợp lệ.',
      );
    }
    return Map<String, dynamic>.from(session);
  });

  Future<void> revoke(ApiClient api, String username) => _exclusive(() async {
    final normalized = _username(username),
        row = await _registration(_username(username));
    if (row == null) return;
    if (row['server'] != api.baseUrl) {
      throw const ApiException(
        'FINGERPRINT_SERVER',
        'Liên kết vân tay thuộc máy chủ khác.',
      );
    }
    final status = await api.get(
      '/fingerprint/status',
      query: {'deviceId': row['deviceId'] as String},
    );
    if (status is! Map || status['username'] != normalized) {
      throw const ApiException(
        'FINGERPRINT_ACCOUNT_MISMATCH',
        'Tên đăng nhập không khớp tài khoản hiện tại.',
      );
    }
    final binding = status['device'];
    if (status['registered'] == true &&
        binding is Map &&
        binding['id'] is String &&
        _uuidPattern.hasMatch(binding['id'] as String)) {
      await api.delete('/fingerprint/devices/${binding['id']}');
    }
    // Server revocation comes first. A local-only deletion must never claim that
    // the server binding has been revoked when the network operation failed.
    if (!await _biometric.deleteKeys(keyAlias: row['keyAlias'] as String)) {
      throw const ApiException(
        'BIOMETRIC_KEY',
        'Máy chủ đã hủy liên kết. Chưa xóa được khóa cục bộ; hãy thử lại.',
      );
    }
    await _delete(_recordKey(normalized));
  });

  void _checkResult(BiometricError? code) {
    if (code == BiometricError.success) return;
    if (code == BiometricError.userCanceled ||
        code == BiometricError.systemCanceled) {
      throw const ApiException(
        'BIOMETRIC_CANCELED',
        'Đã hủy xác thực vân tay.',
      );
    }
    if (code == BiometricError.lockedOut ||
        code == BiometricError.lockedOutPermanent) {
      throw const ApiException(
        'BIOMETRIC_LOCKED',
        'Vân tay đang bị khóa. Hãy dùng mật khẩu và OTP hoặc mở khóa Android rồi thử lại.',
      );
    }
    if (code == BiometricError.keyInvalidated ||
        code == BiometricError.keyNotFound) {
      throw const ApiException(
        'BIOMETRIC_KEY',
        'Khóa vân tay không còn hợp lệ. Hãy đăng nhập bằng mật khẩu và OTP để đăng ký lại.',
      );
    }
    throw const ApiException(
      'BIOMETRIC_FAILED',
      'Chưa xác thực được vân tay. Vui lòng thử lại hoặc dùng mật khẩu và OTP.',
    );
  }
}
