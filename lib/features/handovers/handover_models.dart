import 'dart:math';

import '../../core/models.dart';
import 'critical_facts.dart';
export 'critical_facts.dart';

class HandoverDraft {
  const HandoverDraft({
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  final String originalText, translatedText, sourceLanguage, targetLanguage;
}

class HandoverItem {
  const HandoverItem({
    required this.id,
    required this.text,
    required this.translatedText,
    this.state = 'open',
  });

  final String id, text, translatedText, state;
  factory HandoverItem.fromJson(Json value) => HandoverItem(
    id: value['id'] as String,
    text: value['text'] as String,
    translatedText: value['translatedText'] as String,
    state: value['state'] as String? ?? 'open',
  );
  Json toJson({String? state}) => {
    'id': id,
    'text': text,
    'translatedText': translatedText,
    'state': state ?? this.state,
  };
}

const handoverLanguages = {
  'vi': 'Tiếng Việt',
  'en': 'Tiếng Anh',
  'zh': 'Tiếng Trung',
};

List<HandoverItem> handoverItems(Json record) => (record['items'] as List)
    .map(
      (value) => HandoverItem.fromJson(Map<String, dynamic>.from(value as Map)),
    )
    .toList();

Json composeHandoverPayload({
  required String shiftId,
  required String recipientId,
  required String originalText,
  required String translatedText,
  required String sourceLanguage,
  required String targetLanguage,
  required List<HandoverItem> items,
  List<HandoverCriticalFact> criticalFacts = const [],
  required bool submit,
  int? version,
}) {
  if (shiftId.trim().isEmpty || recipientId.trim().isEmpty) {
    throw const FormatException('Hãy chọn ca làm và người nhận bàn giao.');
  }
  if (!handoverLanguages.containsKey(sourceLanguage) ||
      !handoverLanguages.containsKey(targetLanguage) ||
      sourceLanguage == targetLanguage) {
    throw const FormatException(
      'Hãy chọn hai ngôn ngữ khác nhau: Việt, Anh hoặc Trung.',
    );
  }
  final original = originalText.trim(), translated = translatedText.trim();
  if (original.isEmpty ||
      original.length > 12000 ||
      translated.length > 24000) {
    throw const FormatException(
      'Nội dung gốc cần từ 1–12.000 ký tự; bản dịch tối đa 24.000 ký tự.',
    );
  }
  if (items.isEmpty ||
      items.length > 40 ||
      items.map((item) => item.id).toSet().length != items.length ||
      items.any(
        (item) =>
            item.id.isEmpty ||
            item.text.trim().isEmpty ||
            item.text.trim().length > 1000 ||
            item.translatedText.trim().length > 2000,
      )) {
    throw const FormatException(
      'Cần 1–40 việc rõ ràng; mỗi mục gốc tối đa 1.000 ký tự, bản dịch tối đa 2.000 ký tự.',
    );
  }
  if (submit &&
      (translated.isEmpty ||
          items.any((item) => item.translatedText.trim().isEmpty))) {
    throw const FormatException(
      'Hãy hoàn thiện bản dịch của nội dung và từng việc trước khi gửi.',
    );
  }
  if (version != null && version < 1) {
    throw const FormatException('Phiên bản bàn giao chưa hợp lệ. Hãy tải lại.');
  }
  final facts = criticalFactsPayload(criticalFacts, required: submit);
  return {
    if (version == null) 'shiftId': shiftId,
    'version': ?version,
    'recipientId': recipientId,
    'originalText': original,
    'translatedText': translated,
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'items': items
        .map(
          (item) => HandoverItem(
            id: item.id,
            text: item.text.trim(),
            translatedText: item.translatedText.trim(),
          ).toJson(),
        )
        .toList(),
    'status': submit ? 'submitted' : 'draft',
    'criticalFacts': facts,
  };
}

Json composeAcknowledgement(
  Json record,
  Map<String, String> states, {
  required bool finalize,
  Map<String, String> factAnswers = const {},
}) {
  final version = record['version'];
  if (record['status'] != 'submitted' || version is! int || version < 1) {
    throw const FormatException(
      'Chỉ xác nhận phiếu đã gửi. Hãy tải lại trạng thái mới nhất.',
    );
  }
  final items = handoverItems(record);
  final identifiers = items.map((item) => item.id).toSet();
  if (items.isEmpty ||
      identifiers.length != items.length ||
      states.keys.any((id) => !identifiers.contains(id)) ||
      states.values.any(
        (state) => !['open', 'understood', 'clarify'].contains(state),
      )) {
    throw const FormatException(
      'Danh sách việc đã thay đổi. Hãy tải lại trước khi xác nhận.',
    );
  }
  final updated = items
      .map((item) => item.toJson(state: states[item.id] ?? item.state))
      .toList();
  if (finalize && updated.any((item) => item['state'] != 'understood')) {
    throw const FormatException(
      'Cần hiểu rõ tất cả các việc trước khi hoàn tất bàn giao.',
    );
  }
  final facts = handoverCriticalFacts(record);
  if (finalize) {
    criticalFactsPayload(facts, required: true);
    if (factAnswers.length != facts.length ||
        facts.any((fact) => (factAnswers[fact.id]?.trim() ?? '').isEmpty) ||
        factAnswers.values.any((value) => value.trim().length > 80)) {
      throw const FormatException(
        'Nhập lại đủ dữ kiện trọng yếu của phiên bản này trước khi xác nhận.',
      );
    }
  }
  return {
    'version': version,
    'items': updated,
    'status': finalize ? 'acknowledged' : 'submitted',
    if (finalize)
      'factAnswers': facts
          .map(
            (fact) => {
              'factId': fact.id,
              'value': factAnswers[fact.id]!.trim(),
            },
          )
          .toList(),
  };
}

final _random = Random.secure();
String newHandoverItemId() {
  final bytes = List.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
