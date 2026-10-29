import '../../core/models.dart';

const criticalFactKinds = {
  'equipment': 'Mã thiết bị',
  'quantity': 'Số lượng',
  'deadline': 'Thời hạn',
};

class HandoverCriticalFact {
  const HandoverCriticalFact({
    required this.id,
    required this.kind,
    required this.label,
    required this.value,
  });

  final String id, kind, label, value;

  factory HandoverCriticalFact.fromJson(Json data) => HandoverCriticalFact(
    id: data['id'] as String,
    kind: data['kind'] as String,
    label: data['label'] as String,
    value: data['value'] as String,
  );

  Json toJson() => {
    'id': id,
    'kind': kind,
    'label': label.trim(),
    'value': canonicalCriticalFactValue(kind, value),
  };
}

List<HandoverCriticalFact> handoverCriticalFacts(Json record) =>
    ((record['criticalFacts'] as List?) ?? const [])
        .map((row) => HandoverCriticalFact.fromJson(Json.from(row as Map)))
        .toList();

// The editor accepts a deliberately small ASCII format. Full-width keyboard
// characters are supported here; complete NFKC matching remains server-owned.
String _keyboardText(String value) =>
    String.fromCharCodes(
          value.runes.map(
            (rune) => rune >= 0xff01 && rune <= 0xff5e
                ? rune - 0xfee0
                : rune == 0x3000
                ? 0x20
                : rune,
          ),
        )
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase()
        .replaceAll(RegExp('[\u2010-\u2015\u2212\ufe58\ufe63]'), '-')
        .replaceAll(RegExp(r'\s*-\s*'), '-');

String canonicalCriticalFactValue(String kind, String value) {
  final text = _keyboardText(value);
  if (value.trim().isEmpty || value.trim().length > 80) {
    throw const FormatException('Giá trị dữ kiện cần từ 1–80 ký tự.');
  }
  switch (kind) {
    case 'equipment':
      if (text.length < 2 ||
          text.length > 40 ||
          !RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$').hasMatch(text)) {
        throw const FormatException(
          'Mã gồm 2–40 chữ/số ASCII, nối bằng - hoặc _. Ví dụ EQ-12.',
        );
      }
      return text;
    case 'quantity':
      if (!RegExp(r'^[0-9]{1,9}(?:[.,][0-9]{1,3})?$').hasMatch(text)) {
        throw const FormatException(
          'Dùng tối đa 9 chữ số và 3 số lẻ; dấu , hoặc . là dấu thập phân, không ngăn hàng nghìn.',
        );
      }
      final parts = text.replaceAll(',', '.').split('.');
      final integer = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final fraction = parts.length == 2
          ? parts[1].replaceFirst(RegExp(r'0+$'), '')
          : '';
      return fraction.isEmpty ? integer : '$integer.$fraction';
    case 'deadline':
      final match = RegExp(r'^(?:(\d{4})-(\d{2})-(\d{2}) )?(\d{2}):(\d{2})$')
          .firstMatch(text);
      if (match != null) {
        final hour = int.parse(match[4]!), minute = int.parse(match[5]!);
        var valid = hour < 24 && minute < 60;
        if (match[1] != null) {
          final year = int.parse(match[1]!),
              month = int.parse(match[2]!),
              day = int.parse(match[3]!);
          final date = DateTime.utc(year, month, day);
          valid =
              valid &&
              year >= 1900 &&
              year <= 2199 &&
              date.year == year &&
              date.month == month &&
              date.day == day;
        }
        if (valid) return text;
      }
      throw const FormatException(
        'Dùng HH:mm hoặc YYYY-MM-DD HH:mm, giờ 24h và ngày có thật. Ví dụ 2026-10-30 01:30.',
      );
    default:
      throw const FormatException(
        'Chọn loại mã thiết bị, số lượng hoặc thời hạn.',
      );
  }
}

final _identifierChar = RegExp(r'[\p{L}\p{N}_:\-]', unicode: true);
bool _bounded(String text, RegExpMatch match) =>
    (match.start == 0 ||
        !_identifierChar.hasMatch(
          text.substring(match.start - 1, match.start),
        )) &&
    (match.end == text.length ||
        !_identifierChar.hasMatch(text.substring(match.end, match.end + 1)));

/// An editor hint, not an authentication or semantic guarantee. The server
/// performs the authoritative complete NFKC/token check in its transaction.
bool criticalFactIsAnchored(HandoverCriticalFact fact, String input) {
  String canonical;
  try {
    canonical = canonicalCriticalFactValue(fact.kind, fact.value);
  } on FormatException {
    return false;
  }
  final text = _keyboardText(input);
  final pattern = switch (fact.kind) {
    'equipment' => RegExp(r'[a-z0-9]+(?:[-_][a-z0-9]+)*'),
    'quantity' => RegExp(r'[0-9]+(?:[.,][0-9]+)?'),
    _ => RegExp(r'(?:\d{4}-\d{2}-\d{2} )?\d{2}:\d{2}'),
  };
  for (final match in pattern.allMatches(text)) {
    if (!_bounded(text, match)) continue;
    try {
      if (canonicalCriticalFactValue(fact.kind, match.group(0)!) == canonical) {
        return true;
      }
    } on FormatException {
      // A larger invalid token must never become a matching substring.
    }
  }
  return false;
}

List<Json> criticalFactsPayload(
  List<HandoverCriticalFact> facts, {
  required bool required,
}) {
  if (facts.length > 3 || (required && facts.isEmpty)) {
    throw const FormatException(
      'Cần chọn 1–3 dữ kiện trọng yếu trước khi gửi. Bản nháp có thể chưa có dữ kiện.',
    );
  }
  final ids = <String>{}, signatures = <String>{};
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  return facts.map((fact) {
    final value = fact.toJson();
    if (!uuid.hasMatch(fact.id) ||
        !ids.add(fact.id) ||
        !signatures.add('${fact.kind}:${value['value']}')) {
      throw const FormatException(
        'Mỗi dữ kiện cần mã riêng và không được lặp cùng loại/giá trị.',
      );
    }
    if (fact.label.trim().isEmpty || fact.label.trim().length > 80) {
      throw const FormatException(
        'Đặt nhãn 1–80 ký tự để người nhận biết cần nhập lại điều gì.',
      );
    }
    return value;
  }).toList();
}
