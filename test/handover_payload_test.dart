import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/handovers/handover_models.dart';

const item = HandoverItem(
  id: '95a16b54-f9c2-4dc7-9a1f-70d3f635182f',
  text: 'Bàn giao 12 thẻ trước 17:00.',
  translatedText: 'Hand over 12 cards before 17:00.',
  state: 'understood',
);
const fact = HandoverCriticalFact(
  id: '2b7d511c-a688-4fc5-b4a5-80973f888e52',
  kind: 'quantity',
  label: 'Số thẻ',
  value: '12',
);

Map<String, dynamic> payload({bool submit = true, int? version}) =>
    composeHandoverPayload(
      shiftId: 'shift-id',
      recipientId: 'recipient-id',
      originalText: '  Bàn giao 12 thẻ trước 17:00.  ',
      translatedText: 'Hand over 12 cards before 17:00.',
      sourceLanguage: 'vi',
      targetLanguage: 'en',
      items: const [item],
      criticalFacts: const [fact],
      submit: submit,
      version: version,
    );

void main() {
  test('author updates reset acknowledgements and preserve explicit bilingual pairs', () {
    final value = payload(version: 3);
    expect(value['version'], 3);
    expect(value.containsKey('shiftId'), false);
    expect(value['originalText'], 'Bàn giao 12 thẻ trước 17:00.');
    expect(value['items'], [
      {...item.toJson(), 'state': 'open'},
    ]);
    expect(value['status'], 'submitted');
  });

  test(
    'new drafts retain the selected shift and never synthesize checklist items',
    () {
      final value = payload(submit: false);
      expect(value['shiftId'], 'shift-id');
      expect(value.containsKey('version'), false);
      expect(value['status'], 'draft');
      expect(
        () => composeHandoverPayload(
          shiftId: 'shift-id',
          recipientId: 'recipient-id',
          originalText: 'Nội dung gốc',
          translatedText: 'Original text',
          sourceLanguage: 'vi',
          targetLanguage: 'en',
          items: [],
          submit: true,
        ),
        throwsFormatException,
      );
    },
  );

  test('sending requires translations and distinct supported languages', () {
    for (final target in ['vi', 'fr']) {
      expect(
        () => composeHandoverPayload(
          shiftId: 'shift-id',
          recipientId: 'recipient-id',
          originalText: 'Nội dung gốc',
          translatedText: '',
          sourceLanguage: 'vi',
          targetLanguage: target,
          items: const [item],
          submit: true,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => composeHandoverPayload(
        shiftId: 'shift-id',
        recipientId: 'recipient-id',
        originalText: 'Nội dung gốc',
        translatedText: 'Original text',
        sourceLanguage: 'vi',
        targetLanguage: 'en',
        items: [HandoverItem(id: item.id, text: item.text, translatedText: '')],
        submit: true,
      ),
      throwsFormatException,
    );
  });

  test('recipient can save partial understanding without changing original content', () {
    final record = {
      'version': 4,
      'status': 'submitted',
      'criticalFacts': [fact.toJson()],
      'items': [item.toJson(state: 'open')],
    };
    final value = composeAcknowledgement(record, {
      item.id: 'clarify',
    }, finalize: false);
    expect(value, {
      'version': 4,
      'status': 'submitted',
      'items': [
        {...item.toJson(), 'state': 'clarify'},
      ],
    });
    expect((record['items'] as List).first['state'], 'open');
  });

  test('recipient cannot finalize while any item needs clarification', () {
    final record = {
      'version': 4,
      'status': 'submitted',
      'criticalFacts': [fact.toJson()],
      'items': [item.toJson(state: 'clarify')],
    };
    expect(
      () => composeAcknowledgement(record, {}, finalize: true),
      throwsFormatException,
    );
    expect(
      composeAcknowledgement(
        record,
        {item.id: 'understood'},
        finalize: true,
        factAnswers: {fact.id: '12'},
      )['status'],
      'acknowledged',
    );
  });

  test('acknowledgement refuses stale item ids, invalid states and non-submitted records', () {
    final record = {
      'version': 4,
      'status': 'submitted',
      'items': [item.toJson(state: 'open')],
    };
    expect(
      () => composeAcknowledgement(record, {
        'unknown-id': 'understood',
      }, finalize: false),
      throwsFormatException,
    );
    expect(
      () => composeAcknowledgement(record, {
        item.id: 'approved',
      }, finalize: false),
      throwsFormatException,
    );
    expect(
      () => composeAcknowledgement(
        {...record, 'status': 'draft'},
        {},
        finalize: false,
      ),
      throwsFormatException,
    );
    expect(
      () => composeAcknowledgement(
        {...record, 'version': 0},
        {},
        finalize: false,
      ),
      throwsFormatException,
    );
  });

  test('new item identifiers are unique RFC4122 version-4 UUIDs', () {
    final ids = List.generate(30, (_) => newHandoverItemId());
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(ids.toSet().length, ids.length);
    expect(ids.every(uuid.hasMatch), true);
  });
}
