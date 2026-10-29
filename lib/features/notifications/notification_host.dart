import 'dart:async';

import 'package:flutter/material.dart';

import 'messaging_gateway.dart';
import 'notification_controller.dart';

class NotificationHost extends StatefulWidget {
  const NotificationHost({
    super.key,
    required this.controller,
    required this.child,
  });
  final NotificationController? controller;
  final Widget child;
  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost>
    with WidgetsBindingObserver {
  StreamSubscription<PushHint>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  void _listen() {
    _subscription = widget.controller?.banners.listen((hint) {
      if (!mounted) return;
      final controller = widget.controller;
      if (controller == null ||
          !controller.enabled ||
          controller.session.user?.id != hint.recipientId) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentMaterialBanner();
      messenger.showMaterialBanner(
        MaterialBanner(
          leading: const Icon(Icons.notifications_outlined),
          content: const Text('Bạn có cập nhật mới. Mở ứng dụng để xem.'),
          actions: [
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: const Text('Đóng'),
            ),
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                unawaited(controller.open(hint));
              },
              child: const Text('Xem'),
            ),
          ],
        ),
      );
    });
  }

  @override
  void didUpdateWidget(NotificationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller?.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
