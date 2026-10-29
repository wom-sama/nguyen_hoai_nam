import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/theme.dart';
import '../../ui/ledger.dart';
import 'handover_composer.dart';
import 'handover_detail.dart';
import 'handover_models.dart';
import 'handover_widgets.dart';

export 'handover_composer.dart' show HandoverComposer;
export 'handover_models.dart' show HandoverDraft;

class HandoversScreen extends StatefulWidget {
  const HandoversScreen({super.key});
  @override
  State<HandoversScreen> createState() => _HandoversScreenState();
}

class _HandoversScreenState extends State<HandoversScreen> {
  late Future<List<List<Json>>> _future;
  String _box = 'incoming';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<SessionController>().api;
    _future = Future.wait(
      ['/handovers', '/handover-recipients', '/shifts'].map(
        (path) => api
            .get(path)
            .then(
              (value) => (value as List)
                  .map((row) => Map<String, dynamic>.from(row as Map))
                  .toList(),
            ),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await _future;
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _create() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const HandoverComposer()),
    );
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;
    return AppPage(
      onRefresh: _refresh,
      children: [
        const LedgerHeading(kicker: 'SỔ CA / BÀN GIAO', title: 'Bàn giao'),
        FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.edit_note),
          label: const Text('Tạo bàn giao'),
        ),
        const SizedBox(height: 22),
        AsyncPanel<List<List<Json>>>(
          future: _future,
          onRetry: () => setState(_load),
          builder: (data) {
            final rows = data[0];
            final people = <String, String>{
              user.id: user.fullName,
              for (final person in data[1])
                person['id'] as String: person['fullName'] as String,
            };
            final shifts = <String, Json>{
              for (final shift in data[2]) shift['id'] as String: shift,
            };
            final incoming = rows
                .where((row) => row['recipientId'] == user.id)
                .toList();
            final outgoing = rows
                .where((row) => row['createdBy'] == user.id)
                .toList();
            final watching = rows
                .where(
                  (row) =>
                      row['recipientId'] != user.id &&
                      row['createdBy'] != user.id,
                )
                .toList();
            final selected = switch (_box) {
              'outgoing' => outgoing,
              'team' => watching,
              _ => incoming,
            };
            final waiting = incoming
                .where((row) => row['status'] == 'submitted')
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (waiting > 0) Notice('$waiting phiếu chờ xác nhận đã hiểu.'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text('Nhận (${incoming.length})'),
                      selected: _box == 'incoming',
                      onSelected: (_) => setState(() => _box = 'incoming'),
                    ),
                    ChoiceChip(
                      label: Text('Tôi gửi (${outgoing.length})'),
                      selected: _box == 'outgoing',
                      onSelected: (_) => setState(() => _box = 'outgoing'),
                    ),
                    if (user.canManage)
                      ChoiceChip(
                        label: Text('Theo dõi (${watching.length})'),
                        selected: _box == 'team',
                        onSelected: (_) => setState(() => _box = 'team'),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (selected.isEmpty)
                  EmptyState(
                    title: switch (_box) {
                      'outgoing' => 'Chưa tạo bàn giao',
                      'team' => 'Chưa có phiếu cần theo dõi',
                      _ => 'Chưa nhận bàn giao',
                    },
                    message: _box == 'outgoing'
                        ? 'Tạo phiếu từ ca làm của bạn.'
                        : 'Phiếu trong phạm vi của bạn sẽ xuất hiện ở đây.',
                    icon: Icons.forum_outlined,
                  ),
                for (final record in selected)
                  _recordCard(record, user, people, shifts),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _recordCard(
    Json record,
    AppUser user,
    Map<String, String> people,
    Map<String, Json> shifts,
  ) {
    final items = handoverItems(record), status = record['status'] as String;
    final understood = items.where((item) => item.state == 'understood').length;
    final clarify = items.where((item) => item.state == 'clarify').length;
    final original = (record['originalText'] as String)
        .trim()
        .split('\n')
        .first;
    final party = record['createdBy'] == user.id
        ? 'Gửi ${handoverPerson(record, 'recipientId', people, user.id)}'
        : 'Từ ${handoverPerson(record, 'createdBy', people, user.id)}';
    return LedgerSheet(
      label: 'PHIẾU BÀN GIAO',
      reference: 'BẢN ${record['version']}',
      footer: status == 'acknowledged'
          ? const Align(
              alignment: Alignment.centerRight,
              child: ConfirmationStamp(label: 'ĐÃ XÁC NHẬN HIỂU'),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () async {
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => HandoverDetailScreen(
                id: record['id'] as String,
                people: people,
                shifts: shifts,
              ),
            ),
          );
          if (mounted) await _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusPill(status),
                  Text(
                    '${dateText(record['updatedAt'])} · ${timeText(record['updatedAt'])}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                original,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                party,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              Text(
                handoverShift(record, shifts),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$understood/${items.length} việc đã hiểu${clarify > 0 ? ' · $clarify cần làm rõ' : ''}',
                      style: const TextStyle(
                        color: AppColors.pink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${record['sourceLanguage'].toString().toUpperCase()} → ${record['targetLanguage'].toString().toUpperCase()}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: AppColors.pink,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
