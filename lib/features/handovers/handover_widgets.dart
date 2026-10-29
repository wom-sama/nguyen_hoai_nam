import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import '../../ui/ledger.dart';
import '../../ui/theme.dart';
import 'handover_models.dart';

String handoverPerson(
  Json record,
  String field,
  Map<String, String> people,
  String ownId,
) {
  final id = record[field]?.toString();
  if (id == ownId) return 'Bạn';
  final nameField = field == 'createdBy' ? 'createdByName' : 'recipientName';
  final name = record[nameField]?.toString() ?? people[id];
  return name?.isNotEmpty == true ? name! : 'Đồng nghiệp chưa có tên hiển thị';
}

String handoverShift(Json record, Map<String, Json> shifts) =>
    record['shiftTitle']?.toString() ??
    shifts[record['shiftId']]?['title']?.toString() ??
    'Ca gắn với phiếu bàn giao';

class BilingualBlock extends StatelessWidget {
  const BilingualBlock({
    super.key,
    required this.original,
    required this.translated,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  final String original, translated, sourceLanguage, targetLanguage;

  Widget _part(
    BuildContext context,
    String language,
    String text, {
    bool translation = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        handoverLanguages[language] ?? language,
        style: TextStyle(
          color: translation ? AppColors.pink : AppColors.muted,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: .35,
        ),
      ),
      const SizedBox(height: 8),
      SelectableText(
        text.isEmpty ? 'Chưa có bản dịch.' : text,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: text.isEmpty ? AppColors.muted : AppColors.ink),
      ),
      if (translation && text.isNotEmpty) const GoogleTranslationAttribution(),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (bounds.maxWidth >= 560) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _part(context, sourceLanguage, original)),
            const SizedBox(width: 24),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 20),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppColors.line, width: 2),
                  ),
                ),
                child: _part(
                  context,
                  targetLanguage,
                  translated,
                  translation: true,
                ),
              ),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _part(context, sourceLanguage, original),
          const Divider(height: 28),
          _part(context, targetLanguage, translated, translation: true),
        ],
      );
    },
  );
}

class CriticalFactProof extends StatelessWidget {
  const CriticalFactProof({
    super.key,
    required this.record,
    this.people = const {},
    this.ownId = '',
  });
  final Json record;
  final Map<String, String> people;
  final String ownId;

  @override
  Widget build(BuildContext context) {
    final raw = record['criticalFactConfirmation'];
    if (raw is! Map) return const SizedBox.shrink();
    final proof = Json.from(raw);
    final by = proof['verifiedBy']?.toString();
    final who = by == ownId
        ? 'Bạn'
        : people[by] ??
              (by == record['recipientId']
                  ? record['recipientName']?.toString()
                  : null) ??
              'Người nhận';
    final facts = {
      for (final fact in handoverCriticalFacts(record)) fact.id: fact,
    };
    return LedgerSheet(
      label: 'BẰNG CHỨNG ĐỐI CHIẾU',
      reference: 'ĐÃ GHI NHẬN',
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Đã đối chiếu · phiên bản ${proof['version']}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: AppColors.green),
            ),
            const SizedBox(height: 12),
            Text(
              '$who · ${dateText(proof['verifiedAt'])} ${timeText(proof['verifiedAt'])}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const Divider(height: 26),
            for (final answer in (proof['answers'] as List? ?? const []))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check, size: 16, color: AppColors.green),
                    const SizedBox(width: 9),
                    Expanded(
                      child: SelectableText(
                        '${facts[answer['factId']]?.label ?? 'Dữ kiện'}: ${answer['value']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'Câu trả lời chuẩn được lưu cùng phiên bản. Bằng chứng này chỉ xác nhận dữ kiện đã khớp, không đánh giá ngữ nghĩa bản dịch.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.muted,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
