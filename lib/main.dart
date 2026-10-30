import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/session.dart';
import 'ui/theme.dart';
import 'ui/ledger.dart';
import 'ui/first_run_guide.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/biometric_setup.dart';
import 'features/settings/appearance_controller.dart';
import 'features/home/home_screen.dart';
import 'features/handovers/handovers_screen.dart';
import 'features/translation/translation_screen.dart';
import 'features/manage/resources_screen.dart';
import 'features/account/account_screen.dart';
import 'features/notifications/messaging_gateway.dart';
import 'features/notifications/notification_controller.dart';
import 'features/notifications/notification_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('vi');
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Be Vietnam Pro',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Lora',
    ], await rootBundle.loadString('assets/fonts/Lora-OFL.txt'));
  });
  final api = ApiClient(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://nguyen-hoai-nam-2380601398-api.onrender.com',
    ),
  );
  final session = SessionController(api: api);
  final firstRun = FirstRunController();
  await firstRun.load();
  final notifications = NotificationController(
    session: session,
    gateway: FirebaseMessagingGateway(),
  );
  runApp(
    AttendanceApp(
      session: session,
      notifications: notifications,
      firstRun: firstRun,
      enableAccountSettings: true,
    ),
  );
  unawaited(session.restore());
  unawaited(notifications.initialize());
}

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({
    super.key,
    required this.session,
    this.notifications,
    this.firstRun,
    this.enableAccountSettings = false,
  });
  final SessionController session;
  final NotificationController? notifications;
  final FirstRunController? firstRun;
  final bool enableAccountSettings;
  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  final appearance = AppearanceController();
  String? _appearanceScope;
  @override
  void dispose() {
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: widget.session),
      ChangeNotifierProvider.value(value: appearance),
      ListenableProvider<NotificationController?>.value(
        value: widget.notifications,
      ),
    ],
    child: Consumer2<SessionController, AppearanceController>(
      builder: (context, current, settings, child) {
        final account = current.user;
        final scope = account == null || !account.isActive
            ? null
            : '${account.id}:${account.profileVersion}';
        if (widget.enableAccountSettings && scope != _appearanceScope) {
          _appearanceScope = scope;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _appearanceScope != scope) return;
            if (scope == null) {
              appearance.reset();
            } else {
              unawaited(
                appearance.load(
                  api: current.api,
                  userId: account!.id,
                  force: true,
                ),
              );
            }
          });
        }
        return MaterialApp(
          key: ValueKey(
            '${current.user?.id}|${current.user?.role}|${current.user?.branchId}|${current.user?.status}',
          ),
          title: 'Nguyễn Hoài Nam',
          debugShowCheckedModeBanner: false,
          theme: settings.themeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: settings.textScaler),
            child: child!,
          ),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: NotificationHost(
            controller: widget.notifications,
            child: widget.firstRun == null
                ? _AuthGate(enforceBiometrics: widget.enableAccountSettings)
                : FirstRunGate(
                    controller: widget.firstRun!,
                    child: _AuthGate(
                      enforceBiometrics: widget.enableAccountSettings,
                    ),
                  ),
          ),
        );
      },
    ),
  );
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({this.enforceBiometrics = false});
  final bool enforceBiometrics;
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  Timer? _profilePoll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startProfilePoll();
  }

  void _syncProfile() {
    if (mounted) unawaited(context.read<SessionController>().syncProfile());
  }

  void _startProfilePoll({bool immediate = false}) {
    _profilePoll?.cancel();
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _profilePoll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _syncProfile(),
    );
    if (immediate) _syncProfile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startProfilePoll(immediate: true);
    } else {
      _profilePoll?.cancel();
      _profilePoll = null;
    }
  }

  @override
  void dispose() {
    _profilePoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    if (session.restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.api.isConfigured) return const ServiceUnavailableScreen();
    if (session.user != null) {
      if (!session.user!.isActive) return const PendingAccountScreen();
      final user = session.user!;
      final shell = _AppShell(
        key: ValueKey('${user.id}|${user.role}|${user.branchId}'),
      );
      return widget.enforceBiometrics
          ? BiometricSetupGate(key: ValueKey(user.id), child: shell)
          : shell;
    }
    if (session.restoreRetryable) return const SessionRestoreRetryScreen();
    if (session.challenge != null) return const OtpScreen();
    return const AuthScreen();
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell({super.key});
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _index = 0;
  final _visited = <int>{};
  final _translationKey = GlobalKey<TranslationScreenState>();
  int _homeRevision = 0, _handoverRevision = 0;
  int? _scheduledNotification;

  @override
  void initState() {
    super.initState();
    _index = context.read<SessionController>().user!.canManage ? 3 : 0;
    _visited.add(_index);
  }

  Future<void> _openNotification(
    NotificationController controller,
    NotificationNavigation navigation,
  ) async {
    _scheduledNotification = null;
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        context.read<SessionController>().user?.id !=
            navigation.hint.recipientId) {
      return;
    }
    controller.consumeNavigation(navigation);
    if (_index == 2) {
      await (_translationKey.currentState?.pause() ?? Future.value());
    }
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        context.read<SessionController>().user?.id !=
            navigation.hint.recipientId) {
      return;
    }
    if (navigation.hint.destination == NotificationDestination.corrections) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const ResourceScreen(resource: 'corrections'),
        ),
      );
      return;
    }
    setState(() {
      _index = navigation.hint.destination == NotificationDestination.home
          ? 0
          : 1;
      _visited.add(_index);
      if (_index == 0) {
        _homeRevision++;
      } else {
        _handoverRevision++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final managing = context.watch<SessionController>().user!.canManage;
    final notifications = context.watch<NotificationController?>();
    final navigation = notifications?.navigation;
    if (navigation != null && _scheduledNotification != navigation.revision) {
      _scheduledNotification = navigation.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openNotification(notifications!, navigation));
      });
    }
    final pages = <Widget>[
      HomeScreen(
        active: _index == 0 && ModalRoute.of(context)?.isCurrent == true,
        refreshRevision: _homeRevision,
      ),
      HandoversScreen(key: ValueKey('handovers-$_handoverRevision')),
      TranslationScreen(key: _translationKey),
      if (managing) const ManagementScreen(),
      const AccountScreen(),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.schedule_outlined),
        selectedIcon: Icon(Icons.schedule),
        label: 'Ca làm',
      ),
      const NavigationDestination(
        icon: Icon(Icons.checklist_outlined),
        selectedIcon: Icon(Icons.checklist),
        label: 'Bàn giao',
      ),
      const NavigationDestination(
        icon: Icon(Icons.translate_outlined),
        selectedIcon: Icon(Icons.translate),
        label: 'Dịch',
      ),
      if (managing)
        const NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view_rounded),
          label: 'Quản lý',
        ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Tài khoản',
      ),
    ];
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < pages.length; i++)
            _visited.contains(i)
                ? TabEntrance(
                    key: ValueKey(i),
                    active: i == _index,
                    child: pages[i],
                  )
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          destinations: destinations,
          onDestinationSelected: (index) {
            if (_index == 2 && index != 2) {
              unawaited(
                _translationKey.currentState?.pause() ?? Future.value(),
              );
            }
            setState(() {
              _visited.add(index);
              _index = index;
            });
          },
        ),
      ),
    );
  }
}
