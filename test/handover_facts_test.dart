import 'package:flutter_test/flutter_test.dart';
import 'package:nguyen_hoai_nam/features/handovers/handover_models.dart';

const equipment = HandoverCriticalFact(
  id: '2b7d511c-a688-4fc5-b4a5-80973f888e52',
  kind: 'equipment',
  label: 'Máy cần kiểm tra',
  value: 'EQ-12',
);
const quantity = HandoverCriticalFact(
  id: '5ba77527-27d7-48a5-a52e-d8692819f3e8',
  kind: 'quantity',
  label: 'Số thẻ',
  value: '0012,000',
);
const deadline = HandoverCriticalFact(
  id: 'f43e4de3-cad3-4b13-aace-652b845c441a',
  kind: 'deadline',
  label: 'Hạn bàn giao',
  value: '2026-10-30 01:30',
);

Map<String, dynamic> factPayload({
  bool submit = true,
  List<HandoverCriticalFact> facts = const [equipment, quantity, deadline],
}) => composeHandoverPayload(
  shiftId: 'shift-test',
  recipientId: 'recipient-test',
  originalText: 'Kiểm tra EQ-12; bàn giao 12 thẻ trước 2026-10-30 01:30.',
  translatedText: 'Check EQ-12; hand over 12 cards before 2026-10-30 01:30.',
  sourceLanguage: 'vi',
  targetLanguage: 'en',
  items: const [
    HandoverItem(
      id: 'item-test',
      text: 'Kiểm tra thiết bị.',
      translatedText: 'Check the equipment.',
    ),
  ],
  criticalFacts: facts,
  submit: submit,
);

void main() {
  test(
    'typed canonical values are explicit and never treat commas as thousands',
    () {
      expect(canonicalCriticalFactValue('equipment', ' ＥＱ – １２ '), 'eq-12');
      expect(canonicalCriticalFactValue('equipment', 'EQ_12'), 'eq_12');
      expect(canonicalCriticalFactValue('quantity', '１２,５０'), '12.5');
      expect(canonicalCriticalFactValue('quantity', '0012.000'), '12');
      expect(canonicalCriticalFactValue('quantity', '1,000'), '1');
      expect(
        canonicalCriticalFactValue('deadline', '2028-02-29 01:30'),
        '2028-02-29 01:30',
      );
      for (final bad in ['-1', '1.2345', '1,000.0', '1000000000', '1e3']) {
        expect(
          () => canonicalCriticalFactValue('quantity', bad),
          throwsFormatException,
        );
      }
      for (final bad in [
        '2026-02-29 01:30',
        '24:00',
        '7:30',
        '17h30',
        '1899-01-01 01:30',
        '2200-01-01 01:30',
      ]) {
        expect(
          () => canonicalCriticalFactValue('deadline', bad),
          throwsFormatException,
        );
      }
    },
  );

  test('anchor hints distinguish whole codes, numbers and full deadlines', () {
    expect(criticalFactIsAnchored(quantity, 'Bàn giao 12 thẻ.'), isTrue);
    expect(criticalFactIsAnchored(quantity, 'Bàn giao 112 thẻ.'), isFalse);
    expect(criticalFactIsAnchored(quantity, 'Mã EQ12.'), isFalse);
    expect(criticalFactIsAnchored(quantity, 'Số lượng 12.5.'), isFalse);
    expect(criticalFactIsAnchored(quantity, 'Thời điểm 12:30.'), isFalse);
    expect(criticalFactIsAnchored(equipment, 'Check EQ-12.'), isTrue);
    expect(criticalFactIsAnchored(equipment, 'Check XEQ-12.'), isFalse);
    expect(criticalFactIsAnchored(quantity, '交接 12 个'), isTrue);
    expect(criticalFactIsAnchored(quantity, '交接12个'), isFalse);
    expect(criticalFactIsAnchored(deadline, 'Hạn 2026-10-30 01:30.'), isTrue);
    expect(criticalFactIsAnchored(deadline, 'Hạn 01:30.'), isFalse);
  });

  test('new submission has 1–3 unique typed facts; draft may remain empty', () {
    final value = factPayload();
    expect(value['criticalFacts'], [
      equipment.toJson(),
      {...quantity.toJson(), 'value': '12'},
      deadline.toJson(),
    ]);
    expect(factPayload(submit: false, facts: [])['criticalFacts'], isEmpty);
    expect(() => factPayload(facts: []), throwsFormatException);
    expect(
      () => factPayload(
        facts: [
          quantity,
          HandoverCriticalFact(
            id: equipment.id,
            kind: 'quantity',
            label: 'Lặp',
            value: '12',
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test('recipient answers attach only to final exact-version confirmation', () {
    final record = {
      'version': 7,
      'status': 'submitted',
      'criticalFacts': [
        equipment.toJson(),
        {...quantity.toJson(), 'value': '12'},
      ],
      'items': [
        const HandoverItem(
          id: 'item-a',
          text: 'Việc',
          translatedText: 'Task',
          state: 'understood',
        ).toJson(),
      ],
    };
    final answers = {equipment.id: 'EQ-12', quantity.id: '13'};
    final partial = composeAcknowledgement(
      record,
      {},
      finalize: false,
      factAnswers: answers,
    );
    expect(partial.containsKey('factAnswers'), false);
    final finalValue = composeAcknowledgement(
      record,
      {},
      finalize: true,
      factAnswers: answers,
    );
    expect(finalValue['version'], 7);
    // Even an incorrect answer reaches the server for authoritative comparison.
    expect(finalValue['factAnswers'], [
      {'factId': equipment.id, 'value': 'EQ-12'},
      {'factId': quantity.id, 'value': '13'},
    ]);
    expect(
      () => composeAcknowledgement(
        record,
        {},
        finalize: true,
        factAnswers: {equipment.id: 'EQ-12'},
      ),
      throwsFormatException,
    );
    expect(
      () => composeAcknowledgement(
        {...record, 'criticalFacts': []},
        {},
        finalize: true,
        factAnswers: {},
      ),
      throwsFormatException,
    );
  });
}
