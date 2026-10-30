import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../ui/theme.dart';
import 'settings_image.dart';

class AppearancePreferences {
  const AppearancePreferences({
    this.fontScale = 1,
    this.textColor = '#402D37',
    this.primaryColor = '#AA496C',
    this.backgroundBase64,
  });
  final double fontScale;
  final String textColor, primaryColor;
  final String? backgroundBase64;
  factory AppearancePreferences.fromJson(Json value) => AppearancePreferences(
    fontScale: (value['fontScale'] as num?)?.toDouble() ?? 1,
    textColor: value['textColor'] as String? ?? '#402D37',
    primaryColor: value['primaryColor'] as String? ?? '#AA496C',
    backgroundBase64: value['backgroundBase64'] as String?,
  );
  Json toJson() => {
    'fontScale': fontScale,
    'textColor': textColor.toUpperCase(),
    'primaryColor': primaryColor.toUpperCase(),
    'backgroundBase64': backgroundBase64,
  };
  static Color color(String hex) =>
      Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

class AccountProfile {
  const AccountProfile({
    required this.fullName,
    required this.username,
    required this.email,
    this.phone = '',
    this.address = '',
    this.avatarBase64,
    this.appearance = const AppearancePreferences(),
    this.profileVersion = 0,
  });
  final String fullName, username, email, phone, address;
  final String? avatarBase64;
  final AppearancePreferences appearance;
  final int profileVersion;
  factory AccountProfile.fromJson(Json value) => AccountProfile(
    fullName: value['fullName'] as String,
    username: value['username'] as String,
    email: value['email'] as String,
    phone: value['phone'] as String? ?? '',
    address: value['address'] as String? ?? '',
    avatarBase64: value['avatarBase64'] as String?,
    appearance: AppearancePreferences.fromJson(
      Map<String, dynamic>.from(value['appearance'] as Map? ?? {}),
    ),
    profileVersion: (value['profileVersion'] as num?)?.toInt() ?? 0,
  );
}

/// One account's saved profile and appearance. Draft controls stay in the screen.
class AppearanceController extends ChangeNotifier {
  ApiClient? _api;
  String? userId;
  AccountProfile? profile;
  Uint8List? backgroundBytes, avatarBytes;
  String? error;
  bool loading = false, saving = false;
  int _epoch = 0;
  bool _disposed = false;
  Future<void>? _loadTask;
  AppearancePreferences get preferences =>
      profile?.appearance ?? const AppearancePreferences();
  ThemeData get themeData => appTheme(
    textColor: AppearancePreferences.color(preferences.textColor),
    primaryColor: AppearancePreferences.color(preferences.primaryColor),
    backgroundImage: backgroundBytes,
  );
  TextScaler get textScaler => TextScaler.linear(preferences.fontScale);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void reset() {
    ++_epoch;
    _api = null;
    userId = null;
    profile = null;
    backgroundBytes = avatarBytes = null;
    error = null;
    loading = saving = false;
    _loadTask = null;
    _changed();
  }

  Future<void> load({
    required ApiClient api,
    required String userId,
    bool force = false,
  }) {
    if (_disposed) return Future.value();
    if (this.userId != userId || !identical(_api, api)) {
      reset();
      this.userId = userId;
      _api = api;
    }
    if (_loadTask != null) return _loadTask!;
    if (saving) return Future.value();
    if (profile != null && !force) return Future.value();
    final epoch = _epoch;
    loading = true;
    error = null;
    _changed();
    final task = _read(api, epoch);
    _loadTask = task;
    return task;
  }

  Future<void> _apply(Json value, int epoch) async {
    final next = AccountProfile.fromJson(value);
    final background = next.appearance.backgroundBase64;
    final avatar = next.avatarBase64;
    var nextBackground = backgroundBytes, nextAvatar = avatarBytes;
    if (background != profile?.appearance.backgroundBase64) {
      nextBackground = background == null
          ? null
          : base64Decode(
              await prepareSettingsImage(
                base64Decode(background),
                avatar: false,
              ),
            );
    }
    if (avatar != profile?.avatarBase64) {
      nextAvatar = avatar == null
          ? null
          : base64Decode(
              await prepareSettingsImage(base64Decode(avatar), avatar: true),
            );
    }
    if (!_current(epoch)) return;
    backgroundBytes = nextBackground;
    avatarBytes = nextAvatar;
    profile = next;
  }

  Future<void> _read(ApiClient api, int epoch) async {
    try {
      final data = await api.get('/me/profile');
      if (_current(epoch)) {
        await _apply(Map<String, dynamic>.from(data as Map), epoch);
      }
    } catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (_current(epoch)) {
        loading = false;
        _loadTask = null;
        _changed();
      }
    }
  }

  Future<bool> saveProfile({
    required String fullName,
    required String phone,
    required String address,
    required String? avatarBase64,
  }) => _save('/me/profile', {
    'fullName': fullName.trim(),
    'phone': phone.trim(),
    'address': address.trim(),
    'avatarBase64': avatarBase64,
  });
  Future<bool> saveAppearance(AppearancePreferences value) =>
      _save('/me/appearance', value.toJson());
  Future<bool> _save(String path, Json body) async {
    final api = _api;
    if (_disposed || api == null || userId == null || saving || loading) {
      return false;
    }
    final epoch = _epoch;
    saving = true;
    error = null;
    _changed();
    try {
      final result = await api.patch(path, body);
      if (!_current(epoch)) return false;
      await _apply(Map<String, dynamic>.from(result as Map), epoch);
      return _current(epoch);
    } catch (failure) {
      if (_current(epoch)) error = _message(failure);
      return false;
    } finally {
      if (_current(epoch)) {
        saving = false;
        _changed();
      }
    }
  }

  String _message(Object failure) => failure is ApiException
      ? failure.message
      : 'Chưa tải hoặc lưu được cài đặt. Vui lòng thử lại.';
  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}
