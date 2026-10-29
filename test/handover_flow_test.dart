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
import 'package:nguyen_hoai_nam/features/handovers/handover_detail.dart';
import 'package:nguyen_hoai_nam/ui/theme.dart';

Json recordFixture() => {
  'id': 'handover-test',
  'version': 7,
  'status': 'submitted',
  'createdBy': 'sender-test',
  'recipientId': 'receiver-test',
  'createdByName': 'Người bàn giao kiểm thử',
  'recipientName': 'Người nhận kiểm thử',
  'shiftId': 'shift-test',
  'shiftTitle': 'Ca chiều kiểm thử',
  'shiftStartsAt': '2026-10-29T06:00:00Z',
  'updatedAt': '2026-10-29T05:45:00Z',
  'originalText': 'Bàn giao 12 thẻ trước 17:00. Kiểm tra cửa sau.',
  'translatedText': 'Hand over 12 cards before 17:00. Check the back door.',
  'sourceLanguage': 'vi',
  'targetLanguage': 'en',
  'criticalFacts': [
    {
      'id': '2b7d511c-a688-4fc5-b4a5-80973f888e52',
      'kind': 'quantity',
      'label': 'Số thẻ',
      'value': '12',
    },
  ],
  'criticalFactConfirmation': null,
  'items': [
    {
      'id': 'item-a',
      'text': 'Bàn giao 12 thẻ trước 17:00.',
      'translatedText': 'Hand over 12 cards before 17:00.',
      'state': 'open',
    },
    {
      'id': 'item-b',
      'text': 'Kiểm tra cửa sau.',
      'translatedText': 'Check the back door.',
      'state': 'open',
    },
  ],
};

Future<void> pumpHandover(
  WidgetTester tester,
  SessionController session,
) async {
  tester.view.physicalSize = const Size(320, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        theme: appTheme(),
        home: const HandoverDetailScreen(id: 'handover-test'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

SessionController handoverSession(
  http.Client transport, {
  bool observer = false,
}) =>
    SessionController(
        api: ApiClient(
          baseUrl: 'https://api.example.com',
          transport: transport,
        ),
      )
      ..user = AppUser(
        id: observer ? 'manager-test' : 'receiver-test',
        fullName: 'Người nhận kiểm thử',
        username: 'test-user',
        email: 'test@example.com',
        role: observer ? 'manager' : 'employee',
        status: 'active',
        branchId: 'branch-test',
      );

void main() {
  setUpAll(() async {
    final fonts = FontLoader('BeVietnamPro');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'));
    }
    await fonts.load();
  });

  testWidgets(
    'recipient saves partial understanding, then finalizes only after every item is understood',
    (tester) async {
      var record = recordFixture();
      final patches = <Json>[];
      final session = handoverSession(
        MockClient((request) async {
          if (request.method == 'PATCH') {
            final body = jsonDecode(request.body) as Json;
            patches.add(body);
            record = {
              ...record,
              ...body,
              'version': (record['version'] as int) + 1,
            };
          }
          return http.Response(
            jsonEncode({'data': record}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await pumpHandover(tester, session);
      final finish = find.widgetWithText(
        FilledButton,
        'Xác nhận đã hiểu toàn bộ',
      );
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);
      final understood = find.widgetWithText(ChoiceChip, 'Đã hiểu');
      final clarify = find.widgetWithText(ChoiceChip, 'Cần làm rõ');
      await tapVisible(tester, understood.first);
      await tapVisible(tester, clarify.last);
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);
      final save = find.widgetWithText(OutlinedButton, 'Lưu tiến độ đọc hiểu');
      await tapVisible(tester, save);
      expect(patches.single['version'], 7);
      expect(patches.single['status'], 'submitted');
      expect(
        (patches.single['items'] as List).map((item) => item['state']).toList(),
        ['understood', 'clarify'],
      );
      expect(
        (patches.single['items'] as List).first['text'],
        'Bàn giao 12 thẻ trước 17:00.',
      );
      await tapVisible(tester, understood.last);
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);
      final answer = find.byKey(
        const ValueKey('fact-answer-2b7d511c-a688-4fc5-b4a5-80973f888e52'),
      );
      await tester.ensureVisible(answer);
      await tester.enterText(answer, '12');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
      await tapVisible(tester, finish);
      expect(patches.last['version'], 8);
      expect(patches.last['status'], 'acknowledged');
      expect(patches.last['factAnswers'], [
        {'factId': '2b7d511c-a688-4fc5-b4a5-80973f888e52', 'value': '12'},
      ]);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );

  testWidgets(
    'a manager observing another person’s handover has no edit or confirmation controls',
    (tester) async {
      var mutations = 0;
      final session = handoverSession(
        MockClient((request) async {
          if (request.method != 'GET') mutations++;
          return http.Response(
            jsonEncode({'data': recordFixture()}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        observer: true,
      );
      await pumpHandover(tester, session);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'Chỉnh sửa nội dung'),
        findsNothing,
      );
      expect(
        find.widgetWithText(FilledButton, 'Xác nhận đã hiểu toàn bộ'),
        findsNothing,
      );
      expect(mutations, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      session.api.close();
    },
  );
}
