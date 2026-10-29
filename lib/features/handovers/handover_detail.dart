import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/ledger.dart';
import '../../ui/theme.dart';
import 'handover_composer.dart';
import 'handover_models.dart';
import 'handover_widgets.dart';

class HandoverDetailScreen extends StatefulWidget {
  const HandoverDetailScreen({
    super.key,
    required this.id,
    this.people = const {},
    this.shifts = const {},
  });
  final String id;
  final Map<String, String> people;
  final Map<String, Json> shifts;

  @override
  State<HandoverDetailScreen> createState() => _HandoverDetailScreenState();
}

class _HandoverDetailScreenState extends State<HandoverDetailScreen> {
  late Future<Json> _future;
  final Map<String, String> _states = {};
  final Map<String, TextEditingController> _answers = {};
  bool _busy = false, _conflict = false, _allowPop = false;
  String? _error;
  String? _receipt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context
        .read<SessionController>()
        .api
        .get('/handovers/${widget.id}')
        .then((value) {
          final record = value as Json;
          if (mounted) _bindAnswers(record);
          return record;
        });
  }

  void _bindAnswers(Json record) {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    _answers.clear();
    for (final fact in handoverCriticalFacts(record)) {
      final controller = TextEditingController()..addListener(_answerChanged);
      _answers[fact.id] = controller;
    }
  }

  bool get _hasInput =>
      _states.isNotEmpty ||
      _answers.values.any((controller) => controller.text.isNotEmpty);

  void _answerChanged() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      if (!_conflict) _error = null;
      _receipt = null;
    });
  }

  @override
  void dispose() {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    if (_hasInput) {
      final reload =
          await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('Tải lại các việc bàn giao?'),
              content: const Text(
                'Lựa chọn chưa lưu và các giá trị đang nhập lại sẽ được xóa để đọc, đối chiếu phiếu mới nhất.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Giữ lựa chọn này'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Tải lại'),
                ),
              ],
            ),
          ) ??
          false;
      if (!reload || !mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _states.clear();
      _conflict = false;
      _error = null;
      _receipt = null;
      _load();
    });
    try {
      await _future;
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    final leave =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Bạn còn lựa chọn chưa lưu'),
            content: const Text(
              'Quay lại để lưu tiến độ đọc hiểu, hoặc rời phiếu và bỏ lựa chọn cùng dữ kiện đang nhập lại.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Quay lại lưu'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Rời phiếu'),
              ),
            ],
          ),
        ) ??
        false;
    if (!leave || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _acknowledge(Json record, bool finalize) async {
    if (_busy || _conflict) return;
    try {
      final payload = composeAcknowledgement(
        record,
        _states,
        finalize: finalize,
        factAnswers: _answers.map(
          (id, controller) => MapEntry(id, controller.text),
        ),
      );
      setState(() {
        _busy = true;
        _error = null;
      });
      final saved = await context.read<SessionController>().api.patch(
        '/handovers/${widget.id}',
        payload,
      ) as Json;
      if (!mounted) return;
      setState(() {
        _states.clear();
        _bindAnswers(saved);
        _receipt = finalize
            ? null
            : 'Đã lưu tiến độ. Hãy nhập lại dữ kiện khi xác nhận phiên bản ${saved['version']}.';
        _future = Future.value(saved);
      });
      showMessage(
        context,
        finalize
            ? 'Đã xác nhận hiểu đầy đủ nội dung bàn giao.'
            : 'Đã lưu tiến độ đọc hiểu để hai bên cùng theo dõi.',
      );
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = errorMessage(error);
          _conflict = error.status == 409;
        });
        showFailure(context, error);
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Json record) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => HandoverComposer(existing: record)),
    );
    if (changed == true && mounted) await _refresh();
  }

  Future<void> _delete() async {
    if (_busy ||
        !await confirmDelete(context, 'bản nháp bàn giao này') ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<SessionController>().api.delete(
        '/handovers/${widget.id}',
      );
      if (mounted) {
        showMessage(context, 'Đã xóa bản nháp.');
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;
    return PopScope<bool>(
      canPop: _allowPop || (!_hasInput && !_busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Phiếu bàn giao'),
          actions: [
            IconButton(
              tooltip: 'Lịch sử cập nhật',
              icon: const Icon(Icons.history),
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HandoverHistoryScreen(
                          id: widget.id,
                          people: widget.people,
                        ),
                      ),
                    ),
            ),
          ],
        ),
        body: AppPage(
          onRefresh: _refresh,
          children: [
            AsyncPanel<Json>(
              future: _future,
              onRetry: () => unawaited(_refresh()),
              builder: (record) {
                final items = handoverItems(record);
                final facts = handoverCriticalFacts(record);
                final creator = record['createdBy'] == user.id,
                    recipient = record['recipientId'] == user.id;
                final canConfirm =
                    recipient &&
                    record['status'] == 'submitted' &&
                    !_busy &&
                    !_conflict;
                final showAnswerFields =
                    recipient && record['status'] == 'submitted';
                final completeAnswers =
                    facts.isNotEmpty &&
                    facts.every(
                      (fact) =>
                          _answers[fact.id]?.text.trim().isNotEmpty ?? false,
                    );
                final understood = items
                    .where(
                      (item) =>
                          (_states[item.id] ?? item.state) == 'understood',
                    )
                    .length;
                final clarifying = items
                    .where(
                      (item) => (_states[item.id] ?? item.state) == 'clarify',
                    )
                    .length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PageHeading(
                      eyebrow: 'BÀN GIAO SONG NGỮ',
                      title: 'Nội dung bàn giao',
                    ),
                    if (_error != null) Notice(_error!, isError: true),
                    if (_receipt != null) Notice(_receipt!),
                    if (_conflict)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text(
                            'Tải phiếu mới nhất trước khi tiếp tục',
                          ),
                        ),
                      ),
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusPill(record['status'] as String),
                              Text(
                                '${record['sourceLanguage'].toString().toUpperCase()} → ${record['targetLanguage'].toString().toUpperCase()}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          InfoRow('Phiên bản', '${record['version']}'),
                          InfoRow(
                            'Người gửi',
                            handoverPerson(
                              record,
                              'createdBy',
                              widget.people,
                              user.id,
                            ),
                          ),
                          InfoRow(
                            'Người nhận',
                            handoverPerson(
                              record,
                              'recipientId',
                              widget.people,
                              user.id,
                            ),
                          ),
                          InfoRow(
                            'Ca làm',
                            handoverShift(record, widget.shifts),
                          ),
                          if (record['shiftStartsAt'] != null ||
                              widget.shifts[record['shiftId']] != null)
                            InfoRow(
                              'Ngày bắt đầu',
                              '${dateText(record['shiftStartsAt'] ?? widget.shifts[record['shiftId']]?['startsAt'])} · '
                                  '${timeText(record['shiftStartsAt'] ?? widget.shifts[record['shiftId']]?['startsAt'])}',
                            ),
                          InfoRow(
                            'Cập nhật',
                            '${dateText(record['updatedAt'])} · ${timeText(record['updatedAt'])}',
                          ),
                        ],
                      ),
                    ),
                    if (!creator && !recipient)
                      const Notice(
                        'Bạn chỉ theo dõi. Người nhận xác nhận; người gửi chỉnh sửa nội dung.',
                      ),
                    if (recipient && record['status'] == 'draft')
                      const Notice(
                        'Phiếu còn là bản nháp. Bạn chỉ xác nhận được sau khi phiếu được gửi.',
                      ),
                    if (record['status'] == 'acknowledged')
                      Notice(
                        record['criticalFactConfirmation'] is Map
                            ? 'Đã xác nhận các việc và nhập đúng dữ kiện. Người gửi cập nhật nội dung sẽ hủy xác nhận và bằng chứng cũ.'
                            : 'Phiếu cũ chưa có bằng chứng đối chiếu dữ kiện. Người gửi có thể bổ sung và gửi lại phiên bản mới.',
                      ),
                    Surface(
                      child: BilingualBlock(
                        original: record['originalText'] as String,
                        translated: record['translatedText'] as String,
                        sourceLanguage: record['sourceLanguage'] as String,
                        targetLanguage: record['targetLanguage'] as String,
                      ),
                    ),
                    const LedgerSection(
                      number: '01',
                      title: 'Dữ kiện trọng yếu',
                    ),
                    if (facts.isEmpty)
                      const Notice(
                        'Người gửi cần bổ sung 1–3 dữ kiện trước khi người nhận có thể xác nhận hoàn tất.',
                      ),
                    for (var index = 0; index < facts.length; index++)
                      _factRow(
                        record,
                        facts[index],
                        index,
                        answer: showAnswerFields,
                        enabled: canConfirm,
                      ),
                    if (showAnswerFields && facts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Đang trả lời phiên bản ${record['version']}',
                              style: const TextStyle(
                                color: AppColors.pink,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              'Đọc hai đoạn và nhập lại các giá trị quan trọng để xác nhận đúng nội dung của phiếu này. Hãy tự kiểm tra ý nghĩa bản dịch trước khi xác nhận.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (record['criticalFactConfirmation'] is Map)
                      CriticalFactProof(
                        record: record,
                        people: widget.people,
                        ownId: user.id,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Từng việc đã hiểu',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$understood/${items.length} việc đã hiểu${clarifying > 0 ? ' · $clarifying việc cần làm rõ' : ''}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: items.isEmpty ? 0 : understood / items.length,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(3),
                      color: AppColors.green,
                      backgroundColor: AppColors.line,
                      semanticsLabel:
                          'Đã hiểu $understood trên ${items.length} việc',
                    ),
                    const SizedBox(height: 20),
                    for (var index = 0; index < items.length; index++)
                      _itemCard(record, items[index], index, canConfirm),
                    if (showAnswerFields) ...[
                      const Notice(
                        'Chọn “Cần làm rõ” cho việc chưa chắc chắn. Bạn có thể lưu tiến độ rồi xác nhận sau.',
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || _conflict || _states.isEmpty
                            ? null
                            : () => _acknowledge(record, false),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Lưu tiến độ đọc hiểu'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                _conflict ||
                                understood != items.length ||
                                items.isEmpty ||
                                !completeAnswers
                            ? null
                            : () => _acknowledge(record, true),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.task_alt),
                        label: Text(
                          _busy ? 'Đang lưu…' : 'Xác nhận đã hiểu toàn bộ',
                        ),
                      ),
                    ],
                    if (creator) ...[
                      OutlinedButton.icon(
                        onPressed: _busy || _conflict
                            ? null
                            : () => _edit(record),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Chỉnh sửa nội dung'),
                      ),
                      if (record['status'] == 'draft') ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _busy || _conflict
                              ? null
                              : () => _edit(record),
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('Kiểm tra và gửi bàn giao'),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _busy || _conflict ? null : _delete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Xóa bản nháp'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _factRow(
    Json record,
    HandoverCriticalFact fact,
    int index, {
    required bool answer,
    required bool enabled,
  }) => LedgerSheet(
    label:
        '${(index + 1).toString().padLeft(2, '0')} · ${criticalFactKinds[fact.kind] ?? fact.kind}',
    reference: 'PHIÊN BẢN ${record['version']}',
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(fact.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(
            fact.value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: AppColors.pink),
          ),
          const SizedBox(height: 10),
          Text(
            'Bản gốc: ${criticalFactIsAnchored(fact, record['originalText'] as String) ? 'đã thấy giá trị' : 'cần đối chiếu'} · Bản dịch: ${criticalFactIsAnchored(fact, record['translatedText'] as String) ? 'đã thấy giá trị' : 'cần đối chiếu'}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              height: 1.7,
            ),
          ),
          if (answer) ...[
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey('fact-answer-${fact.id}'),
              controller: _answers[fact.id],
              enabled: enabled,
              maxLength: 80,
              keyboardType: fact.kind == 'quantity'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: 'Nhập lại: ${fact.label}',
                hintText: fact.kind == 'deadline'
                    ? 'HH:mm hoặc YYYY-MM-DD HH:mm'
                    : 'Tự nhập giá trị đã đọc',
              ),
            ),
            if (fact.kind == 'quantity')
              const Text(
                'Dấu , và . là dấu thập phân; không dùng dấu ngăn hàng nghìn.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  height: 1.6,
                ),
              ),
          ],
        ],
      ),
    ),
  );

  Widget _itemCard(Json record, HandoverItem item, int index, bool canConfirm) {
    final state = _states[item.id] ?? item.state;
    void choose(String next) {
      // The previous save receipt should not cover the next action on a small display.
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() {
        final value = state == next ? 'open' : next;
        if (value == item.state) {
          _states.remove(item.id);
        } else {
          _states[item.id] = value;
        }
      });
    }

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${index + 1}'.padLeft(2, '0'),
                style: const TextStyle(
                  color: AppColors.pink,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Việc ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusPill(state),
            ],
          ),
          const SizedBox(height: 18),
          BilingualBlock(
            original: item.text,
            translated: item.translatedText,
            sourceLanguage: record['sourceLanguage'] as String,
            targetLanguage: record['targetLanguage'] as String,
          ),
          if (canConfirm)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Đã hiểu'),
                    avatar: const Icon(Icons.check, size: 17),
                    selected: state == 'understood',
                    selectedColor: AppColors.lightGreen,
                    showCheckmark: false,
                    onSelected: (_) => choose('understood'),
                  ),
                  ChoiceChip(
                    label: const Text('Cần làm rõ'),
                    avatar: const Icon(Icons.help_outline, size: 17),
                    selected: state == 'clarify',
                    showCheckmark: false,
                    onSelected: (_) => choose('clarify'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class HandoverHistoryScreen extends StatefulWidget {
  const HandoverHistoryScreen({
    super.key,
    required this.id,
    this.people = const {},
  });
  final String id;
  final Map<String, String> people;
  @override
  State<HandoverHistoryScreen> createState() => _HandoverHistoryScreenState();
}

class _HandoverHistoryScreenState extends State<HandoverHistoryScreen> {
  late Future<List<Json>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context
        .read<SessionController>()
        .api
        .get('/handovers/${widget.id}/revisions')
        .then(
          (value) => (value as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử bàn giao')),
      body: AppPage(
        children: [
          const PageHeading(
            eyebrow: 'DẤU VẾT CẬP NHẬT',
            title: 'Các phiên bản bàn giao',
          ),
          AsyncPanel<List<Json>>(
            future: _future,
            onRetry: () => setState(_load),
            builder: (revisions) {
              if (revisions.isEmpty) {
                return const EmptyState(
                  title: 'Chưa có lịch sử',
                  message: 'Các phiên bản được lưu khi phiếu được tạo hoặc cập nhật.',
                );
              }
              return Column(
                children: revisions.reversed.map((revision) {
                  final raw = revision['snapshot'];
                  if (raw is! Map) {
                    return const Notice(
                      'Một phiên bản lưu chưa có định dạng đọc được.',
                      isError: true,
                    );
                  }
                  final snapshot = Map<String, dynamic>.from(raw);
                  final actor = revision['actorId'] == user.id
                      ? 'Bạn'
                      : revision['actorName']?.toString() ??
                            widget.people[revision['actorId']] ??
                            'Đồng nghiệp';
                  return Surface(
                    padding: EdgeInsets.zero,
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                      title: Text(
                        'Phiên bản ${revision['version']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        '${dateText(revision['createdAt'])} · ${timeText(revision['createdAt'])}\n$actor · ${StatusPill.label(snapshot['status'] as String)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      children: [
                        BilingualBlock(
                          original: snapshot['originalText'] as String,
                          translated: snapshot['translatedText'] as String,
                          sourceLanguage: snapshot['sourceLanguage'] as String,
                          targetLanguage: snapshot['targetLanguage'] as String,
                        ),
                        if (handoverCriticalFacts(snapshot).isNotEmpty) ...[
                          const Divider(height: 30),
                          Text(
                            'Dữ kiện của phiên bản ${revision['version']}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          for (final fact in handoverCriticalFacts(snapshot))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: SelectableText(
                                '${criticalFactKinds[fact.kind] ?? fact.kind} · ${fact.label}: ${fact.value}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                        if (snapshot['criticalFactConfirmation'] is Map) ...[
                          const SizedBox(height: 16),
                          CriticalFactProof(
                            record: snapshot,
                            people: widget.people,
                            ownId: user.id,
                          ),
                        ],
                        const Divider(height: 30),
                        for (final item in handoverItems(snapshot))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                StatusPill(item.state),
                                const SizedBox(height: 8),
                                SelectableText(
                                  item.text,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SelectableText(
                                  item.translatedText.isEmpty
                                      ? 'Chưa có bản dịch.'
                                      : item.translatedText,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                  ),
                                ),
                                if (item.translatedText.isNotEmpty)
                                  const GoogleTranslationAttribution(),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
