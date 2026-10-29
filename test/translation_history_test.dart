import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/handovers/handovers_screen.dart';
import 'package:nguyen_hoai_nam/features/translation/speech_engine.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_screen.dart';
import 'package:nguyen_hoai_nam/features/translation/translation_service.dart';
import 'package:nguyen_hoai_nam/ui/components.dart';
import 'package:nguyen_hoai_nam/ui/theme.dart';

/// Recognized segments are deliberate UI fixtures, not native ASR results.
class _FixtureSpeech extends ContinuousSpeechEngine {
  final input = StreamController<SpeechSegment>.broadcast();
  @override
  Stream<SpeechSegment> get segments => input.stream;

  void emit(int number) {
    final started = DateTime.utc(2026, 10, 29).add(Duration(seconds: number));
    input.add(
      SpeechSegment(
        id: '$number',
        text: 'Nội dung $number',
        languageCode: 'vi',
        startedAt: started,
        endedAt: started.add(const Duration(seconds: 1)),
        decodingMs: 10,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await input.close();
    await super.dispose();
  }
}

class _FixtureTranslator extends TranslationService {
  Completer<void>? blocked;
  @override
  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    await blocked?.future;
    return 'Bản dịch $text';
  }
}

class _HistoryFixture {
  final engine = _FixtureSpeech();
  final translator = _FixtureTranslator();
  late final session =
      SessionController(
          api: ApiClient(
            baseUrl: 'https://api.example.com',
            transport: MockClient(
              (_) async => http.Response(
                jsonEncode({'data': []}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
            ),
          ),
        )
        ..user = const AppUser(
          id: 'history-user',
          fullName: 'Người kiểm thử',
          username: 'history-user',
          email: 'history@example.com',
          role: 'employee',
          status: 'active',
          branchId: 'history-branch',
        );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: TranslationScreen(
              speechEngine: engine,
              translationService: translator,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, find.text('Giọng nói'));
  }

  Future<void> add(WidgetTester tester, int number) async {
    engine.emit(number);
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    if (translator.blocked case final waiting? when !waiting.isCompleted) {
      waiting.complete();
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    session.dispose();
    session.api.close();
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

List<String> allocatedHistoryCards(WidgetTester tester) => tester
    .widget<AppPage>(find.byType(AppPage).first)
    .children
    .map((widget) => widget.key)
    .whereType<ValueKey<String>>()
    .map((key) => key.value)
    .where((value) => value.startsWith('voice-line-'))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  setUpAll(() async {
    await initializeDateFormatting('vi');
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'retains forty transcript pairs while allocating at most ten result cards per frame',
    (tester) async {
      final fixture = _HistoryFixture();
      await fixture.pump(tester);
      for (var number = 1; number <= 40; number++) {
        await fixture.add(tester, number);
      }
      final cards = allocatedHistoryCards(tester);
      debugPrint(
        'History workload=40 retained segments, allocated result cards=${cards.length}',
      );
      expect(cards.length, lessThanOrEqualTo(10));
      expect(cards, contains('voice-line-40'));
      expect(cards, isNot(contains('voice-line-1')));
      await tap(tester, find.text('Sao chép toàn bộ phiên'));
      for (var number = 1; number <= 40; number++) {
        expect(
          clipboard,
          contains('Nội dung $number\nBản dịch Nội dung $number'),
        );
      }
      expect(
        clipboard!.indexOf('Nội dung 1\n'),
        lessThan(clipboard!.indexOf('Nội dung 40\n')),
      );
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'browsing older segments stays anchored when new speech arrives and can return to latest',
    (tester) async {
      final fixture = _HistoryFixture();
      await fixture.pump(tester);
      for (var number = 1; number <= 25; number++) {
        await fixture.add(tester, number);
      }
      await tap(tester, find.text('Đoạn cũ hơn'));
      final olderCards = allocatedHistoryCards(tester);
      expect(olderCards, contains('voice-line-15'));
      expect(olderCards, contains('voice-line-6'));
      await fixture.add(tester, 26);
      await fixture.add(tester, 27);
      expect(allocatedHistoryCards(tester), olderCards);
      await tap(tester, find.text('Về đoạn mới nhất'));
      expect(allocatedHistoryCards(tester), contains('voice-line-27'));
      expect(allocatedHistoryCards(tester), isNot(contains('voice-line-6')));
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'an older page keeps per-segment copy and the original bilingual handover pair',
    (tester) async {
      final fixture = _HistoryFixture();
      await fixture.pump(tester);
      for (var number = 1; number <= 11; number++) {
        await fixture.add(tester, number);
      }
      await tap(tester, find.text('Đoạn cũ hơn'));
      final oldCard = find.byKey(const ValueKey('voice-line-1'));
      await tap(
        tester,
        find.descendant(
          of: oldCard,
          matching: find.byTooltip('Sao chép bản dịch'),
        ),
      );
      expect(clipboard, 'Bản dịch Nội dung 1');
      await tap(
        tester,
        find.descendant(of: oldCard, matching: find.text('Tạo bàn giao')),
      );
      final draft = tester
          .widget<HandoverComposer>(find.byType(HandoverComposer))
          .initial!;
      expect(draft.originalText, 'Nội dung 1');
      expect(draft.translatedText, 'Bản dịch Nội dung 1');
      expect(draft.sourceLanguage, 'vi');
      expect(draft.targetLanguage, 'en');
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'translation overload keeps the incoming original available in the transcript',
    (tester) async {
      final fixture = _HistoryFixture();
      fixture.translator.blocked = Completer<void>();
      await fixture.pump(tester);
      for (var number = 1; number <= 13; number++) {
        await fixture.add(tester, number);
      }
      await tap(tester, find.text('Sao chép toàn bộ phiên'));
      expect(clipboard, contains('Nội dung 13'));
      expect(clipboard, contains('Nội dung 1'));
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );
}
