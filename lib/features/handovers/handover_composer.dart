import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/components.dart';
import '../../ui/ledger.dart';
import '../../ui/theme.dart';
import '../translation/translation_service.dart';
import 'handover_models.dart';

class HandoverComposer extends StatefulWidget {
  const HandoverComposer({super.key, this.initial, this.existing});
  final HandoverDraft? initial;
  final Json? existing;

  @override
  State<HandoverComposer> createState() => _HandoverComposerState();
}

class _ItemEditor {
  _ItemEditor({required this.id, String text = '', String translatedText = ''})
    : original = TextEditingController(text: text),
      translated = TextEditingController(text: translatedText);

  final String id;
  final TextEditingController original, translated;
  HandoverItem get value => HandoverItem(
    id: id,
    text: original.text,
    translatedText: translated.text,
  );
  void dispose() {
    original.dispose();
    translated.dispose();
  }
}

class _FactEditor {
  _FactEditor({
    required this.id,
    this.kind = 'equipment',
    String label = '',
    String value = '',
  }) : label = TextEditingController(text: label),
       value = TextEditingController(text: value);
  final String id;
  String kind;
  final TextEditingController label, value;
  HandoverCriticalFact get fact => HandoverCriticalFact(
    id: id,
    kind: kind,
    label: label.text,
    value: value.text,
  );
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _HandoverComposerState extends State<HandoverComposer> {
  final _form = GlobalKey<FormState>();
  final _translator = TranslationService();
  final _original = TextEditingController(),
      _translated = TextEditingController();
  final List<_ItemEditor> _items = [];
  final List<_FactEditor> _facts = [];
  late Future<List<List<Json>>> _choices;
  Json? _existing;
  String _source = 'vi', _target = 'en';
  String? _shiftId, _recipientId, _translating, _error;
  bool _saving = false,
      _dirty = false,
      _reviewed = false,
      _conflict = false,
      _allowPop = false;

  @override
  void initState() {
    super.initState();
    _populate(widget.existing, initial: widget.initial);
    _original.addListener(_touch);
    _translated.addListener(_touch);
    _loadChoices();
  }

  void _populate(Json? existing, {HandoverDraft? initial}) {
    _existing = existing;
    _source =
        existing?['sourceLanguage'] as String? ??
        initial?.sourceLanguage ??
        'vi';
    _target =
        existing?['targetLanguage'] as String? ??
        initial?.targetLanguage ??
        'en';
    _original.text =
        existing?['originalText'] as String? ?? initial?.originalText ?? '';
    _translated.text =
        existing?['translatedText'] as String? ?? initial?.translatedText ?? '';
    _shiftId = existing?['shiftId'] as String?;
    _recipientId = existing?['recipientId'] as String?;
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    if (existing != null) {
      for (final item in handoverItems(existing)) {
        _addEditor(
          _ItemEditor(
            id: item.id,
            text: item.text,
            translatedText: item.translatedText,
          ),
        );
      }
    }
    if (_items.isEmpty) _addEditor(_ItemEditor(id: newHandoverItemId()));
    for (final fact in _facts) {
      fact.dispose();
    }
    _facts.clear();
    if (existing != null) {
      for (final fact in handoverCriticalFacts(existing)) {
        _addFact(
          _FactEditor(
            id: fact.id,
            kind: fact.kind,
            label: fact.label,
            value: fact.value,
          ),
        );
      }
    }
    _dirty = initial != null && initial.originalText.isNotEmpty;
    _reviewed = false;
    _conflict = false;
    _error = null;
  }

  void _loadChoices() {
    final api = context.read<SessionController>().api;
    _choices = Future.wait(
      ['/shifts', '/handover-recipients'].map(
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

  void _addEditor(_ItemEditor item) {
    item.original.addListener(_touch);
    item.translated.addListener(_touch);
    _items.add(item);
  }

  void _addFact(_FactEditor fact) {
    fact.label.addListener(_touch);
    fact.value.addListener(_touch);
    _facts.add(fact);
  }

  void _touch() {
    if (!mounted || (_dirty && !_reviewed && _error == null)) return;
    setState(() {
      _dirty = true;
      _reviewed = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _original.dispose();
    _translated.dispose();
    for (final item in _items) {
      item.dispose();
    }
    for (final fact in _facts) {
      fact.dispose();
    }
    unawaited(_translator.dispose());
    super.dispose();
  }

  Future<void> _leave() async {
    if (_saving) return;
    final discard =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Giữ lại nội dung đang viết?'),
            content: const Text(
              'Phiếu chưa được lưu. Bạn có thể quay lại để lưu bản nháp trước khi rời màn hình.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Viết tiếp'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Bỏ thay đổi'),
              ),
            ],
          ),
        ) ??
        false;
    if (discard && mounted) _finish(false);
  }

  void _finish(bool changed) {
    setState(() {
      _allowPop = true;
      _dirty = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, changed);
    });
  }

  Future<void> _translateText({
    required String key,
    required TextEditingController original,
    required TextEditingController translated,
    _ItemEditor? item,
  }) async {
    if (_translating != null || _saving) return;
    final before = original.text, source = _source, target = _target;
    if (before.trim().isEmpty) {
      showMessage(context, 'Nhập nội dung gốc của mục này trước khi dịch.');
      return;
    }
    setState(() {
      _translating = key;
      _error = null;
    });
    try {
      final result = await _translator.translate(
        before,
        sourceLanguage: source,
        targetLanguage: target,
      );
      if (!mounted) return;
      if ((item != null && !_items.contains(item)) ||
          original.text != before ||
          _source != source ||
          _target != target) {
        showMessage(
          context,
          'Nội dung đã thay đổi trong khi dịch. Hãy dịch lại phần mới.',
        );
        return;
      }
      translated.text = result;
      _touch();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _translating = null);
    }
  }

  void _useWholeParagraph() {
    final text = _original.text.trim(), translated = _translated.text.trim();
    if (text.isEmpty || text.length > 1000 || translated.length > 2000) {
      showMessage(
        context,
        'Một việc cần tối đa 1.000 ký tự gốc và 2.000 ký tự dịch. Với đoạn dài, hãy thêm từng việc và dịch riêng.',
      );
      return;
    }
    setState(() {
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
      _addEditor(
        _ItemEditor(
          id: newHandoverItemId(),
          text: text,
          translatedText: translated,
        ),
      );
      _dirty = true;
      _reviewed = false;
    });
  }

  Future<void> _reloadExisting() async {
    if (_existing == null || _saving) return;
    final reload =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Tải phiên bản mới nhất?'),
            content: const Text(
              'Nội dung bạn đang nhập sẽ được thay bằng phiếu mới nhất. Bạn có thể hủy để giữ lại và đối chiếu nội dung trước.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Giữ nội dung này'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Tải lại phiếu'),
              ),
            ],
          ),
        ) ??
        false;
    if (!reload || !mounted) return;
    setState(() => _saving = true);
    try {
      final row = await context.read<SessionController>().api.get(
        '/handovers/${_existing!['id']}',
      ) as Json;
      if (!mounted) return;
      setState(() {
        _populate(row);
        _loadChoices();
      });
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save(bool submit) async {
    if (_saving || _translating != null || _conflict) return;
    FocusScope.of(context).unfocus();
    try {
      if (!(_form.currentState?.validate() ?? false)) return;
      final value = composeHandoverPayload(
        shiftId: _shiftId ?? '',
        recipientId: _recipientId ?? '',
        originalText: _original.text,
        translatedText: _translated.text,
        sourceLanguage: _source,
        targetLanguage: _target,
        items: _items.map((item) => item.value).toList(),
        criticalFacts: _facts.map((editor) => editor.fact).toList(),
        submit: submit,
        version: _existing?['version'] as int?,
      );
      if (submit && !_reviewed) {
        throw const FormatException(
          'Hãy đối chiếu bản gốc, bản dịch và các con số, rồi đánh dấu xác nhận trước khi gửi.',
        );
      }
      final missing = _facts
          .where(
            (editor) =>
                !criticalFactIsAnchored(editor.fact, _original.text) ||
                !criticalFactIsAnchored(editor.fact, _translated.text),
          )
          .toList();
      if (missing.isNotEmpty) {
        final proceed =
            await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: Text(
                  submit
                      ? 'Đối chiếu dữ kiện trước khi gửi'
                      : 'Lưu bản nháp còn cần đối chiếu?',
                ),
                content: Text(
                  'Chưa thấy đầy đủ ${missing.map((editor) => editor.label.text.trim()).join(', ')} trong cả hai đoạn. '
                  '${submit ? 'Các mã, số và thời hạn sẽ được kiểm tra trước khi gửi. Phiếu cần có đủ các giá trị này.' : 'Bản nháp được giữ để bạn bổ sung giá trị vào hai đoạn trước khi gửi.'} '
                  'Gợi ý chỉ hỗ trợ đối chiếu, không kiểm tra nghĩa của bản dịch.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Quay lại đối chiếu'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text(submit ? 'Kiểm tra và gửi' : 'Lưu nháp'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!proceed || !mounted) return;
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      final api = context.read<SessionController>().api;
      if (_existing == null) {
        await api.post('/handovers', value);
      } else {
        await api.patch('/handovers/${_existing!['id']}', value);
      }
      if (!mounted) return;
      showMessage(
        context,
        submit
            ? 'Đã gửi bàn giao để người nhận đọc và xác nhận.'
            : 'Đã lưu bản nháp bàn giao.',
      );
      _finish(true);
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
        showMessage(context, error.message);
      }
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _languageChoice(
    String label,
    String value,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: handoverLanguages.entries
        .map(
          (entry) => DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: _saving || _translating != null ? null : onChanged,
  );

  Widget _textField(
    TextEditingController controller,
    String label,
    int maxLength, {
    bool required = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_saving,
    minLines: 2,
    maxLines: 6,
    maxLength: maxLength,
    maxLengthEnforcement: MaxLengthEnforcement.none,
    decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
    validator: required
        ? (value) => value == null || value.trim().isEmpty
              ? 'Nhập nội dung trước khi lưu.'
              : null
        : null,
  );

  Widget _translateButton(
    String key,
    TextEditingController original,
    TextEditingController translated, {
    _ItemEditor? item,
  }) => TextButton.icon(
    onPressed: _saving || _translating != null
        ? null
        : () => _translateText(
            key: key,
            original: original,
            translated: translated,
            item: item,
          ),
    icon: _translating == key
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.translate, size: 18),
    label: Text(
      _translating == key ? 'Đang chuẩn bị bản dịch…' : 'Dịch bằng Google',
    ),
  );

  void _appendFacts() {
    try {
      final facts = criticalFactsPayload(
        _facts.map((editor) => editor.fact).toList(),
        required: true,
      );
      final values = facts
          .map((fact) => '${fact['label']}: ${fact['value']}')
          .join('; ');
      const titles = {
        'vi': 'Thông tin trọng yếu',
        'en': 'Critical facts',
        'zh': '关键数据',
      };
      final sourceLine = '${titles[_source]}: $values.';
      final targetLine = '${titles[_target]}: $values.';
      if (_original.text.length + sourceLine.length + 2 > 12000 ||
          _translated.text.length + targetLine.length + 2 > 24000) {
        throw const FormatException(
          'Đoạn văn đã quá dài để thêm dữ kiện. Hãy chỉnh lại nội dung trước.',
        );
      }
      _original.text = '${_original.text.trim()}\n\n$sourceLine'.trim();
      _translated.text = '${_translated.text.trim()}\n\n$targetLine'.trim();
      _touch();
      showMessage(
        context,
        'Đã thêm dòng dữ kiện vào cả hai đoạn theo lựa chọn của bạn. Hãy đọc lại trước khi gửi.',
      );
    } on FormatException catch (error) {
      showMessage(context, error.message);
    }
  }

  Widget _factFields(_FactEditor editor, int index) => LedgerSheet(
    key: ValueKey('critical-fact-${editor.id}'),
    label: 'DỮ KIỆN ${(index + 1).toString().padLeft(2, '0')}',
    reference: 'GIỮ NGUYÊN Ở HAI ĐOẠN',
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: editor.kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Loại dữ kiện'),
                  items: criticalFactKinds.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              editor.kind = value;
                              _dirty = true;
                              _reviewed = false;
                            });
                          }
                        },
                ),
              ),
              IconButton(
                tooltip: 'Bỏ dữ kiện ${index + 1}',
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _facts.remove(editor);
                        editor.dispose();
                        _dirty = true;
                        _reviewed = false;
                      }),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('critical-fact-label-${editor.id}'),
            controller: editor.label,
            enabled: !_saving,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Nhãn người nhận cần nhớ',
              hintText: 'Ví dụ: Máy cần kiểm tra',
            ),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? 'Đặt nhãn cho dữ kiện này.'
                : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('critical-fact-value-${editor.id}'),
            controller: editor.value,
            enabled: !_saving,
            maxLength: 80,
            keyboardType: editor.kind == 'quantity'
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: 'Giá trị phải giữ nguyên',
              hintText: switch (editor.kind) {
                'quantity' => '12 hoặc 12.5',
                'deadline' => '2026-10-30 01:30',
                _ => 'EQ-12',
              },
            ),
            validator: (value) {
              try {
                canonicalCriticalFactValue(editor.kind, value ?? '');
                return null;
              } on FormatException catch (error) {
                return error.message;
              }
            },
          ),
          Text(
            switch (editor.kind) {
              'quantity' => 'Dấu , và . đều là dấu thập phân. KHÔNG dùng dấu ngăn hàng nghìn: 1,000 sẽ thành 1.',
              'deadline' => 'Giờ 24h: HH:mm hoặc YYYY-MM-DD HH:mm. Ca qua đêm nên ghi đầy đủ ngày để tránh nhầm.',
              _ => 'Mã 2–40 chữ/số ASCII, dùng - hoặc _. EQ_12 và EQ-12 là hai mã khác nhau.',
            },
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.muted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: Listenable.merge([
              editor.value,
              _original,
              _translated,
            ]),
            builder: (context, _) {
              String? canonical;
              try {
                canonical = canonicalCriticalFactValue(
                  editor.kind,
                  editor.value.text,
                );
              } on FormatException {
                /* The field explains the accepted format. */
              }
              if (canonical == null) {
                return const Text(
                  'Nhập giá trị để đối chiếu với hai đoạn.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                );
              }
              final inSource = criticalFactIsAnchored(
                    editor.fact,
                    _original.text,
                  ),
                  inTarget = criticalFactIsAnchored(
                    editor.fact,
                    _translated.text,
                  );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    'Giá trị chuẩn: $canonical',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _anchorHint('Bản gốc', inSource),
                      _anchorHint('Bản dịch', inTarget),
                    ],
                  ),
                  if (!inSource || !inTarget)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Chưa thấy giá trị đầy đủ ở cả hai đoạn. Giữ nguyên mã, số và giờ; dùng khoảng trắng hoặc dấu phân cách, ví dụ “12 个”. Các giá trị sẽ được kiểm tra trước khi gửi.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.pink,
                          height: 1.6,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _anchorHint(String label, bool found) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        found ? Icons.check_circle_outline : Icons.info_outline,
        size: 16,
        color: found ? AppColors.green : AppColors.pink,
      ),
      const SizedBox(width: 5),
      Text(
        '$label: ${found ? 'đã thấy' : 'cần đối chiếu'}',
        style: const TextStyle(fontSize: 11),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().user!;
    final editable =
        user.isActive &&
        (_existing == null || _existing!['createdBy'] == user.id);
    return PopScope<bool>(
      canPop: _allowPop || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_existing == null ? 'Viết bàn giao' : 'Sửa bàn giao'),
        ),
        body: AppPage(
          children: [
            const PageHeading(
              eyebrow: 'GỐC & BẢN DỊCH',
              title: 'Soạn bàn giao',
            ),
            if (!editable)
              const Notice(
                'Bạn chỉ có quyền xem phiếu này. Hãy quay lại danh sách để mở trạng thái mới nhất.',
              ),
            if (editable)
              AsyncPanel<List<List<Json>>>(
                future: _choices,
                onRetry: () => setState(_loadChoices),
                builder: (choices) {
                  final shifts = choices[0]
                      .where((shift) => shift['employeeId'] == user.id)
                      .toList();
                  final recipients = choices[1];
                  if (_existing == null &&
                      (shifts.isEmpty || recipients.isEmpty)) {
                    return EmptyState(
                      title: 'Cần một ca và người nhận cùng chi nhánh',
                      message: 'Quản lý cần phân công ca cho bạn và duyệt ít nhất một đồng nghiệp trong cùng chi nhánh trước khi bàn giao.',
                      icon: Icons.people_outline,
                    );
                  }
                  return Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) Notice(_error!, isError: true),
                        if (_conflict)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _reloadExisting,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tải lại phiên bản mới nhất'),
                            ),
                          ),
                        if (_existing != null &&
                            _existing!['status'] != 'draft')
                          const Notice(
                            'Bản cập nhật sẽ hủy xác nhận và bằng chứng cũ. Người nhận phải đọc, nhập lại dữ kiện và xác nhận phiên bản mới.',
                          ),
                        Surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_existing == null)
                                DropdownButtonFormField<String>(
                                  initialValue:
                                      shifts.any(
                                        (shift) => shift['id'] == _shiftId,
                                      )
                                      ? _shiftId
                                      : null,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Ca của bạn',
                                  ),
                                  items: shifts
                                      .map(
                                        (shift) => DropdownMenuItem<String>(
                                          value: shift['id'] as String,
                                          child: Text(
                                            '${shift['title']} · ${dateText(shift['startsAt'])} ${timeText(shift['startsAt'])}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _saving
                                      ? null
                                      : (value) {
                                          _shiftId = value;
                                          _touch();
                                        },
                                  validator: (value) => value == null
                                      ? 'Chọn ca được gắn với phiếu.'
                                      : null,
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'Ca: ${shifts.where((shift) => shift['id'] == _shiftId).firstOrNull?['title'] ?? 'Ca đã gắn với phiếu'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<String>(
                                initialValue:
                                    recipients.any(
                                      (person) => person['id'] == _recipientId,
                                    )
                                    ? _recipientId
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Người nhận bàn giao',
                                ),
                                items: recipients
                                    .map(
                                      (person) => DropdownMenuItem<String>(
                                        value: person['id'] as String,
                                        child: Text(
                                          person['fullName'] as String,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        _recipientId = value;
                                        _touch();
                                      },
                                validator: (value) => value == null
                                    ? 'Chọn người nhận đang hoạt động.'
                                    : null,
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: _languageChoice('Bản gốc', _source, (
                                      value,
                                    ) {
                                      if (value != null) {
                                        setState(() {
                                          _source = value;
                                          _dirty = true;
                                          _reviewed = false;
                                          _error = null;
                                        });
                                      }
                                    }),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _languageChoice(
                                      'Bản dịch',
                                      _target,
                                      (value) {
                                        if (value != null) {
                                          setState(() {
                                            _target = value;
                                            _dirty = true;
                                            _reviewed = false;
                                            _error = null;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Nội dung bàn giao',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 16),
                              _textField(
                                _original,
                                handoverLanguages[_source] ?? 'Bản gốc',
                                12000,
                                required: true,
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: _translateButton(
                                  'paragraph',
                                  _original,
                                  _translated,
                                ),
                              ),
                              _textField(
                                _translated,
                                handoverLanguages[_target] ?? 'Bản dịch',
                                24000,
                              ),
                              if (_translated.text.trim().isNotEmpty)
                                const GoogleTranslationAttribution(),
                            ],
                          ),
                        ),
                        const LedgerSection(
                          number: '01',
                          title: 'Dữ kiện trọng yếu',
                        ),
                        const Text(
                          'Chọn 1–3 mã thiết bị, số lượng hoặc thời hạn quan trọng. Người nhận cần nhập lại các giá trị này trước khi hoàn tất.',
                          style: TextStyle(color: AppColors.muted, height: 1.7),
                        ),
                        const SizedBox(height: 16),
                        for (var index = 0; index < _facts.length; index++)
                          _factFields(_facts[index], index),
                        OutlinedButton.icon(
                          onPressed: _saving || _facts.length >= 3
                              ? null
                              : () => setState(() {
                                  _addFact(
                                    _FactEditor(id: newHandoverItemId()),
                                  );
                                  _dirty = true;
                                  _reviewed = false;
                                }),
                          icon: const Icon(Icons.add),
                          label: Text(
                            _facts.length >= 3
                                ? 'Đã đủ 3 dữ kiện'
                                : 'Thêm dữ kiện trọng yếu',
                          ),
                        ),
                        if (_facts.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: _saving || _translating != null
                                ? null
                                : _appendFacts,
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Thêm dữ kiện vào hai đoạn'),
                          ),
                          const Text(
                            'Chỉ khi bấm nút, dòng dữ kiện mới được thêm vào cả hai đoạn. Hãy kiểm tra nghĩa và giá trị trước khi gửi.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                              height: 1.6,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Từng việc cần được hiểu',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8, bottom: 16),
                          child: Text(
                            'Mỗi mục gồm một việc cụ thể và bản dịch tương ứng. Nội dung dài cần chia mục và dịch riêng để tránh ghép sai ý.',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ),
                        if (_items.every(
                          (item) =>
                              item.original.text.trim().isEmpty &&
                              item.translated.text.trim().isEmpty,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _useWholeParagraph,
                              icon: const Icon(Icons.segment),
                              label: const Text('Dùng toàn bộ đoạn làm 1 mục'),
                            ),
                          ),
                        for (var index = 0; index < _items.length; index++)
                          KeyedSubtree(
                            key: ValueKey(_items[index].id),
                            child: _itemFields(_items[index], index),
                          ),
                        OutlinedButton.icon(
                          onPressed: _saving || _items.length >= 40
                              ? null
                              : () => setState(() {
                                  _addEditor(
                                    _ItemEditor(id: newHandoverItemId()),
                                  );
                                  _dirty = true;
                                  _reviewed = false;
                                }),
                          icon: const Icon(Icons.add),
                          label: Text(
                            _items.length >= 40
                                ? 'Đã đủ 40 việc'
                                : 'Thêm một việc',
                          ),
                        ),
                        const SizedBox(height: 20),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _reviewed,
                          onChanged: _saving
                              ? null
                              : (value) =>
                                    setState(() => _reviewed = value ?? false),
                          title: const Text(
                            'Đã đối chiếu bản gốc, bản dịch và dữ kiện.',
                            style: TextStyle(fontSize: 13),
                          ),
                          subtitle: const Text(
                            'Tên riêng, số lượng và thời hạn cần được kiểm tra trước khi gửi.',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_existing == null ||
                            _existing!['status'] == 'draft')
                          OutlinedButton.icon(
                            onPressed:
                                _saving || _translating != null || _conflict
                                ? null
                                : () => _save(false),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Lưu bản nháp'),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed:
                              _saving || _translating != null || _conflict
                              ? null
                              : () => _save(true),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            _saving
                                ? 'Đang lưu…'
                                : _existing != null &&
                                      _existing!['status'] != 'draft'
                                ? 'Lưu và gửi bản cập nhật'
                                : 'Gửi bàn giao',
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _itemFields(_ItemEditor item, int index) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.palePink,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}'.padLeft(2, '0'),
                style: const TextStyle(
                  color: AppColors.pink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Việc cần bàn giao')),
            IconButton(
              tooltip: 'Bỏ mục ${index + 1}',
              icon: const Icon(Icons.close),
              onPressed: _saving || _translating != null
                  ? null
                  : () => setState(() {
                      _items.remove(item);
                      item.dispose();
                      _dirty = true;
                      _reviewed = false;
                    }),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _textField(
          item.original,
          handoverLanguages[_source] ?? 'Bản gốc',
          1000,
          required: true,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: _translateButton(
            item.id,
            item.original,
            item.translated,
            item: item,
          ),
        ),
        _textField(
          item.translated,
          handoverLanguages[_target] ?? 'Bản dịch',
          2000,
        ),
        if (item.translated.text.trim().isNotEmpty)
          const GoogleTranslationAttribution(),
      ],
    ),
  );
}
