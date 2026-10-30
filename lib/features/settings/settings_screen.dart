import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../ui/components.dart';
import 'appearance_controller.dart';
import 'email_change_screen.dart';
import 'settings_image.dart';

class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});
  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load({bool force = false}) async {
    final session = context.read<SessionController>();
    final user = session.user;
    if (user == null) return;
    await context.read<AppearanceController>().load(
      api: session.api,
      userId: user.id,
      force: force,
    );
  }

  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppearanceController>();
    final admin = context.watch<SessionController>().user?.isAdmin == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: settings.profile == null
          ? settings.error != null
                ? AppPage(
                    children: [
                      Notice(settings.error!, isError: true),
                      OutlinedButton(
                        onPressed: () => _load(force: true),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator())
          : AppPage(
              onRefresh: () => _load(force: true),
              children: [
                Surface(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Hồ sơ cá nhân'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(const ProfileSettingsScreen()),
                      ),
                      ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: const Text('Giao diện'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(const AppearanceSettingsScreen()),
                      ),
                      ListTile(
                        leading: const Icon(Icons.alternate_email),
                        title: const Text('Đổi email'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(const EmailChangeScreen()),
                      ),
                      if (admin)
                        ListTile(
                          leading: const Icon(Icons.mark_email_read_outlined),
                          title: const Text('Duyệt đổi email'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(const EmailChangeReviewScreen()),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});
  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _phone, _address;
  String? _avatar;
  Uint8List? _avatarBytes;
  bool _picking = false;
  @override
  void initState() {
    super.initState();
    final settings = context.read<AppearanceController>();
    final profile = settings.profile!;
    _name = TextEditingController(text: profile.fullName);
    _phone = TextEditingController(text: profile.phone);
    _address = TextEditingController(text: profile.address);
    _avatar = profile.avatarBase64;
    _avatarBytes = settings.avatarBytes;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() => _picking = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 65,
        requestFullMetadata: false,
      );
      if (image == null || !mounted) return;
      final encoded = await prepareSettingsImage(
        await image.readAsBytes(),
        avatar: true,
      );
      if (mounted) {
        setState(() {
          _avatar = encoded;
          _avatarBytes = base64Decode(encoded);
        });
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final settings = context.read<AppearanceController>();
    final session = context.read<SessionController>();
    final saved = await settings.saveProfile(
      fullName: _name.text,
      phone: _phone.text,
      address: _address.text,
      avatarBase64: _avatar,
    );
    if (saved) unawaited(session.syncProfile());
    if (mounted && saved) showMessage(context, 'Đã lưu hồ sơ.');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppearanceController>();
    final profile = settings.profile;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final busy = settings.saving || _picking;
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ cá nhân')),
      body: AppPage(
        children: [
          if (settings.error != null) Notice(settings.error!, isError: true),
          Surface(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 44,
                      backgroundImage: _avatarBytes == null
                          ? null
                          : MemoryImage(_avatarBytes!),
                      child: _avatarBytes == null
                          ? const Icon(Icons.person_outline, size: 40)
                          : null,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: busy ? null : _pickAvatar,
                        child: Text(
                          _picking ? 'Đang xử lý…' : 'Chọn ảnh đại diện',
                        ),
                      ),
                      if (_avatar != null)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  _avatar = null;
                                  _avatarBytes = null;
                                }),
                          child: const Text('Xóa ảnh'),
                        ),
                    ],
                  ),
                  TextFormField(
                    controller: _name,
                    enabled: !busy,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Họ và tên'),
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? 'Nhập họ và tên từ 2 ký tự.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: profile.username,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập',
                      suffixIcon: Icon(Icons.lock_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: profile.email,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      suffixIcon: Icon(Icons.lock_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phone,
                    enabled: !busy,
                    keyboardType: TextInputType.phone,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _address,
                    enabled: !busy,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Địa chỉ'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(settings.saving ? 'Đang lưu…' : 'Lưu hồ sơ'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});
  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _text, _primary;
  late double _scale;
  String? _background;
  Uint8List? _backgroundBytes;
  bool _picking = false;
  @override
  void initState() {
    super.initState();
    final controller = context.read<AppearanceController>();
    final current = controller.preferences;
    _scale = current.fontScale;
    _text = TextEditingController(text: current.textColor);
    _primary = TextEditingController(text: current.primaryColor);
    _background = current.backgroundBase64;
    _backgroundBytes = controller.backgroundBytes;
  }

  @override
  void dispose() {
    _text.dispose();
    _primary.dispose();
    super.dispose();
  }

  String? _validateColor(String? value, {bool text = false}) {
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value ?? '')) {
      return 'Nhập màu theo dạng #RRGGBB.';
    }
    if (text &&
        1.05 / (AppearancePreferences.color(value!).computeLuminance() + .05) <
            4.5) {
      return 'Chọn màu chữ đậm hơn để dễ đọc trên nền sáng.';
    }
    return null;
  }

  Future<void> _pickBackground() async {
    setState(() => _picking = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 65,
        requestFullMetadata: false,
      );
      if (image == null || !mounted) return;
      final encoded = await prepareSettingsImage(
        await image.readAsBytes(),
        avatar: false,
      );
      if (mounted) {
        setState(() {
          _background = encoded;
          _backgroundBytes = base64Decode(encoded);
        });
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final saved = await context.read<AppearanceController>().saveAppearance(
      AppearancePreferences(
        fontScale: _scale,
        textColor: _text.text,
        primaryColor: _primary.text,
        backgroundBase64: _background,
      ),
    );
    if (mounted && saved) {
      showMessage(context, 'Đã lưu giao diện cho tài khoản này.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppearanceController>();
    final busy = controller.saving || _picking;
    return Scaffold(
      appBar: AppBar(title: const Text('Giao diện')),
      body: AppPage(
        children: [
          if (controller.error != null)
            Notice(controller.error!, isError: true),
          Surface(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cỡ chữ · ${(_scale * 100).round()}%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Slider(
                    value: _scale,
                    min: .8,
                    max: 1.6,
                    divisions: 8,
                    label: '${(_scale * 100).round()}%',
                    onChanged: busy ? null : (v) => setState(() => _scale = v),
                  ),
                  Text(
                    'Ca làm hôm nay',
                    textScaler: TextScaler.linear(_scale),
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _text,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Màu chữ (#RRGGBB)',
                    ),
                    validator: (v) => _validateColor(v, text: true),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _primary,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Màu chính (#RRGGBB)',
                    ),
                    validator: _validateColor,
                  ),
                  const SizedBox(height: 20),
                  if (_backgroundBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _backgroundBytes!,
                        height: 130,
                        fit: BoxFit.cover,
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _pickBackground,
                    icon: const Icon(Icons.wallpaper),
                    label: Text(_picking ? 'Đang xử lý ảnh…' : 'Chọn ảnh nền'),
                  ),
                  if (_background != null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              _background = null;
                              _backgroundBytes = null;
                            }),
                      child: const Text('Xóa ảnh nền'),
                    ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _scale = 1;
                            _text.text = '#402D37';
                            _primary.text = '#AA496C';
                            _background = null;
                            _backgroundBytes = null;
                          }),
                    child: const Text('Khôi phục mặc định'),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(
                      controller.saving ? 'Đang lưu…' : 'Lưu giao diện',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
