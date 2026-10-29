import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

enum NotificationDestination { home, corrections, handovers }

/// Push data is only a routing hint. Details always come from an authorized API.
class PushHint {
  const PushHint({required this.recipientId, required this.destination});
  final String recipientId;
  final NotificationDestination destination;

  static PushHint? parse(Map<String, dynamic> data) {
    final recipient = data['recipientId'];
    if (recipient is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(recipient)) {
      return null;
    }
    final destination = switch (data['eventType']) {
      'shift_assigned' => NotificationDestination.home,
      'correction_reviewed' => NotificationDestination.corrections,
      'handover_submitted' => NotificationDestination.handovers,
      _ => null,
    };
    return destination == null
        ? null
        : PushHint(recipientId: recipient, destination: destination);
  }
}

abstract interface class MessagingGateway {
  Future<String> initialize();
  Stream<String> get registrations;
  Stream<PushHint> get foreground;
  Stream<PushHint> get opened;
  Future<PushHint?> initialMessage();
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> setAutoInit(bool enabled);
  Future<String> register();
  Future<void> unregister();
}

/// Background notification display belongs to FCM/Android. No account data or
/// authenticated API is touched by this isolate.
@pragma('vm:entry-point')
Future<void> attendanceMessageBackground(RemoteMessage message) async {}

class FirebaseMessagingGateway implements MessagingGateway {
  FirebaseMessaging? _messaging;
  FirebaseMessaging get _sdk => _messaging!;

  @override
  Future<String> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('Thông báo hiện hỗ trợ bản Android.');
    }
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp()
        : Firebase.app();
    _messaging = FirebaseMessaging.instance;
    if (!await _sdk.isSupported()) {
      throw StateError('Thiết bị chưa hỗ trợ dịch vụ thông báo Google.');
    }
    FirebaseMessaging.onBackgroundMessage(attendanceMessageBackground);
    return app.options.projectId;
  }

  Stream<PushHint> _hints(Stream<RemoteMessage> source) => source
      .map((message) => PushHint.parse(message.data))
      .where((hint) => hint != null)
      .cast<PushHint>();

  @override
  Stream<String> get registrations => _sdk.onRegistered;
  @override
  Stream<PushHint> get foreground => _hints(FirebaseMessaging.onMessage);
  @override
  Stream<PushHint> get opened => _hints(FirebaseMessaging.onMessageOpenedApp);
  @override
  Future<PushHint?> initialMessage() async {
    final message = await _sdk.getInitialMessage();
    return message == null ? null : PushHint.parse(message.data);
  }

  bool _allowed(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  @override
  Future<bool> hasPermission() async =>
      _allowed(await _sdk.getNotificationSettings());
  @override
  Future<bool> requestPermission() async => _allowed(
    await _sdk.requestPermission(alert: true, badge: false, sound: true),
  );
  @override
  Future<void> setAutoInit(bool enabled) => _sdk.setAutoInitEnabled(enabled);

  @override
  Future<String> register() async {
    // Subscribe before register: an already registered installation may emit
    // immediately. The current SDK returns FID via this stream, not getToken().
    final event = Completer<String>();
    final subscription = registrations.listen(
      (fid) {
        if (!event.isCompleted && fid.isNotEmpty) event.complete(fid);
      },
      onError: (Object error, StackTrace stack) {
        if (!event.isCompleted) event.completeError(error, stack);
      },
    );
    final timer = Timer(const Duration(seconds: 30), () {
      if (!event.isCompleted) {
        event.completeError(
          TimeoutException('Đăng ký thông báo quá thời gian.'),
        );
      }
    });
    try {
      final results = await Future.wait<Object?>([
        _sdk.register(),
        event.future,
      ], eagerError: true);
      return results[1]! as String;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  @override
  Future<void> unregister() => _sdk.unregister();
}
