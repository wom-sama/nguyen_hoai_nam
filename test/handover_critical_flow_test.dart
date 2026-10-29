import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:nguyen_hoai_nam/core/api_client.dart';
import 'package:nguyen_hoai_nam/core/models.dart';
import 'package:nguyen_hoai_nam/core/session.dart';
import 'package:nguyen_hoai_nam/features/handovers/handover_composer.dart';
import 'package:nguyen_hoai_nam/features/handovers/handover_detail.dart';
import 'package:nguyen_hoai_nam/ui/theme.dart';

const factId = '2b7d511c-a688-4fc5-b4a5-80973f888e52';
Json fixture({int version = 7, String status = 'submitted'}) => {
  'id': 'handover-test',
  'version': version,
  'status': status,
  'createdBy': 'author-test',
  'recipientId': 'recipient-test',
  'shiftId': 'shift-test',
  'shiftTitle': 'Ca đêm',
  'updatedAt': '2026-10-29T16:00:00Z',
  'originalText': 'Bàn giao 12 thẻ.',
  'translatedText': 'Hand over 12 cards.',
  'sourceLanguage': 'vi',
  'targetLanguage': 'en',
  'items': [
    {
      'id': 'item-a',
      'text': 'Bàn giao 12 thẻ.',
      'translatedText': 'Hand over 12 cards.',
      'state': 'understood',
    },
  ],
  'criticalFacts': [
    {'id': factId, 'kind': 'quantity', 'label': 'Số thẻ', 'value': '12'},
  ],
  'criticalFactConfirmation': null,
};

http.Response data(dynamic value) => http.Response(
  jsonEncode({'data': value}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response failure(String code, String message, int status) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': message},
  }),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<SessionController> pump(
  WidgetTester tester,
  http.Client transport, {
  bool author = false,
  Widget? screen,
}) async {
  tester.view.physicalSize = const Size(320, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session =
      SessionController(
          api: ApiClient(
            baseUrl: 'https://api.example.com',
            transport: transport,
          ),
        )
        ..user = AppUser(
          id: author ? 'author-test' : 'recipient-test',
          fullName: 'Kiểm thử',
          username: 'test',
          email: 'test@example.com',
          role: 'employee',
          status: 'active',
          branchId: 'branch-test',
        );
  addTearDown(() {
    session.dispose();
    session.api.close();
  });
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        theme: appTheme(),
        home: screen ?? const HandoverDetailScreen(id: 'handover-test'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final font = FontLoader('BeVietnamPro');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
    }
    await font.load();
    final lora = FontLoader('Lora')
      ..addFont(rootBundle.load('assets/fonts/Lora-Variable.ttf'));
    await lora.load();
  });

  testWidgets(
    'wrong typed fact stays editable; no mutation until explicit retry; proof is read-only',
    (tester) async {
      var record = fixture();
      final patches = <Json>[];
      await pump(
        tester,
        MockClient((request) async {
          if (request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Json;
            patches.add(body);
            if ((body['factAnswers'] as List).single['value'] != '12') {
              return failure(
                'FACT_ANSWER_MISMATCH',
                'Dữ kiện chưa khớp. Hãy đối chiếu và nhập lại.',
                422,
              );
            }
            record = {
              ...record,
              ...body,
              'version': 8,
              'criticalFactConfirmation': {
                'verifiedBy': 'recipient-test',
                'verifiedAt': '2026-10-29T16:05:00Z',
                'version': 8,
                'answers': [
                  {'factId': factId, 'value': '12'},
                ],
              },
            };
          }
          return data(record);
        }),
      );
      final answer = find.byKey(const ValueKey('fact-answer-$factId'));
      final finish = find.widgetWithText(
        FilledButton,
        'Xác nhận đã hiểu toàn bộ',
      );
      await tester.ensureVisible(answer);
      await tester.enterText(answer, '13');
      await tester.pumpAndSettle();
      expect(patches, isEmpty);
      await tap(tester, finish);
      expect(patches.length, 1);
      expect(
        find.text('Dữ kiện chưa khớp. Hãy đối chiếu và nhập lại.'),
        findsWidgets,
      );
      expect(tester.widget<TextFormField>(answer).controller!.text, '13');
      await tester.enterText(answer, '12');
      await tester.pumpAndSettle();
      expect(patches.length, 1);
      await tap(tester, finish);
      expect(patches.last['version'], 7);
      expect(find.byKey(const ValueKey('fact-answer-$factId')), findsNothing);
      expect(find.text('Đã đối chiếu · phiên bản 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'stale answer locks further requests, keeps input until explicit reload, then clears it',
    (tester) async {
      var gets = 0, patches = 0;
      await pump(
        tester,
        MockClient((request) async {
          if (request.method == 'PATCH') {
            patches++;
            return failure(
              'VERSION_CONFLICT',
              'Phiếu đã thay đổi. Hãy tải lại.',
              409,
            );
          }
          gets++;
          return data(fixture(version: gets == 1 ? 7 : 9));
        }),
      );
      final answer = find.byKey(const ValueKey('fact-answer-$factId'));
      final finish = find.widgetWithText(
        FilledButton,
        'Xác nhận đã hiểu toàn bộ',
      );
      await tester.ensureVisible(answer);
      await tester.enterText(answer, '12');
      await tester.pumpAndSettle();
      await tap(tester, finish);
      expect(patches, 1);
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);
      expect(tester.widget<TextFormField>(answer).controller!.text, '12');
      await tap(tester, find.text('Tải phiếu mới nhất trước khi tiếp tục'));
      await tap(tester, find.widgetWithText(FilledButton, 'Tải lại'));
      expect(gets, 2);
      expect(patches, 1);
      expect(tester.widget<TextFormField>(answer).controller!.text, isEmpty);
      expect(find.text('Đang trả lời phiên bản 9'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'author can amend acknowledged handover, with proof reset warning',
    (tester) async {
      final record = fixture(status: 'acknowledged');
      await pump(
        tester,
        MockClient((request) async {
          if (request.url.path.endsWith('/shifts')) {
            return data([
              {
                'id': 'shift-test',
                'employeeId': 'author-test',
                'title': 'Ca đêm',
              },
            ]);
          }
          if (request.url.path.endsWith('/handover-recipients')) {
            return data([
              {'id': 'recipient-test', 'fullName': 'Đồng nghiệp'},
            ]);
          }
          return data(record);
        }),
        author: true,
        screen: HandoverComposer(existing: record),
      );
      expect(
        find.byKey(const ValueKey('critical-fact-value-$factId')),
        findsOneWidget,
      );
      expect(find.textContaining('hủy xác nhận'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Lưu và gửi bản cập nhật'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'composer only appends canonical facts to both paragraphs after explicit choice',
    (tester) async {
      final record = {
        ...fixture(status: 'draft'),
        'originalText': 'Bàn giao thẻ.',
        'translatedText': 'Hand over cards.',
        'criticalFacts': [
          {
            'id': factId,
            'kind': 'quantity',
            'label': 'Số thẻ',
            'value': '0012,000',
          },
        ],
      };
      final patches = <Json>[];
      await pump(
        tester,
        MockClient((request) async {
          if (request.url.path.endsWith('/shifts')) {
            return data([
              {
                'id': 'shift-test',
                'employeeId': 'author-test',
                'title': 'Ca đêm',
              },
            ]);
          }
          if (request.url.path.endsWith('/handover-recipients')) {
            return data([
              {'id': 'recipient-test', 'fullName': 'Đồng nghiệp'},
            ]);
          }
          if (request.method == 'PATCH') {
            patches.add(jsonDecode(request.body) as Json);
          }
          return data(record);
        }),
        author: true,
        screen: HandoverComposer(existing: record),
      );
      final paragraphs = find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            [
              'Bàn giao thẻ.',
              'Hand over cards.',
            ].contains(widget.controller?.text),
      );
      expect(paragraphs, findsNWidgets(2));
      expect(patches, isEmpty);
      expect(find.text('Giá trị chuẩn: 12'), findsOneWidget);
      await tap(
        tester,
        find.widgetWithText(TextButton, 'Thêm dữ kiện vào hai đoạn'),
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextFormField &&
              widget.controller!.text.contains(
                'Thông tin trọng yếu: Số thẻ: 12.',
              ),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextFormField &&
              widget.controller!.text.contains('Critical facts: Số thẻ: 12.'),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 4));
      await tap(tester, find.widgetWithText(OutlinedButton, 'Lưu bản nháp'));
      expect(patches.single['criticalFacts'], [
        {'id': factId, 'kind': 'quantity', 'label': 'Số thẻ', 'value': '12'},
      ]);
      expect(patches.single['status'], 'draft');
      expect(patches.single.containsKey('criticalFactConfirmation'), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
