import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import 'theme.dart';
import 'paper_backdrop.dart';

class GoogleTranslationAttribution extends StatelessWidget {
  const GoogleTranslationAttribution({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Image.asset(
      'assets/google_translation_attribution.png',
      height: 18,
      semanticLabel: 'Powered by Google Translate',
      fit: BoxFit.contain,
    ),
  );
}

class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const Positioned.fill(child: PaperBackdrop()),
      SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, bounds) {
            final body = ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                math.max(20, (bounds.maxWidth - 760) / 2),
                20,
                math.max(20, (bounds.maxWidth - 760) / 2),
                28,
              ),
              children: children,
            );
            return onRefresh == null
                ? body
                : RefreshIndicator(onRefresh: onRefresh!, child: body);
          },
        ),
      ),
    ],
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? eyebrow, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              eyebrow!,
              style: const TextStyle(
                color: AppColors.pink,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            ?action,
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 14,
                height: 1.65,
              ),
            ),
          ),
      ],
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.isError = false});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isError ? const Color(0xFFFBE9E7) : AppColors.palePink,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.info_outline,
          size: 20,
          color: isError ? const Color(0xFF9A3427) : AppColors.pink,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: isError ? const Color(0xFF7C2C24) : AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      children: [
        Icon(icon, size: 34, color: AppColors.pink),
        const SizedBox(height: 14),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 14), child: action!),
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.value, {super.key});
  final String value;
  static String label(String value) => switch (value) {
    'active' => 'Đang hoạt động',
    'pending' => 'Chờ duyệt',
    'suspended' => 'Tạm khóa',
    'admin' => 'Quản trị',
    'manager' => 'Quản lý',
    'employee' => 'Nhân viên',
    'scheduled' => 'Đã xếp ca',
    'in_progress' => 'Đang làm',
    'missing_check_out' => 'Thiếu giờ ra',
    'completed' => 'Hoàn tất',
    'approved' => 'Đã duyệt',
    'rejected' => 'Từ chối',
    'draft' => 'Bản nháp',
    'submitted' => 'Chờ bàn giao',
    'acknowledged' => 'Đã xác nhận',
    'open' => 'Chưa xác nhận',
    'understood' => 'Đã hiểu',
    'clarify' => 'Cần làm rõ',
    _ => 'Chưa xác định',
  };
  @override
  Widget build(BuildContext context) {
    final good = [
      'active',
      'completed',
      'approved',
      'acknowledged',
      'understood',
    ].contains(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: good ? AppColors.lightGreen : AppColors.palePink,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label(value),
        style: TextStyle(
          color: good ? AppColors.green : AppColors.pink,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 106,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
    this.keepDataWhileLoading = false,
  });
  final Future<T> future;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  final bool keepDataWhileLoading;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (keepDataWhileLoading && snap.hasData && !snap.hasError) {
        return builder(snap.data as T);
      }
      if (snap.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(36),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snap.hasError) {
        return Column(
          children: [
            Notice(errorMessage(snap.error!), isError: true),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        );
      }
      return builder(snap.data as T);
    },
  );
}

String errorMessage(Object e) => e is ApiException
    ? e.message
    : 'Chưa hoàn tất được thao tác. Vui lòng thử lại.';
void showMessage(BuildContext context, String value) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
void showFailure(BuildContext context, Object error) =>
    showMessage(context, errorMessage(error));
String timeText(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? '—' : DateFormat('HH:mm').format(date.toLocal());
}

String dateText(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? '—' : DateFormat('dd/MM/yyyy').format(date.toLocal());
}

bool isSameLocalDay(dynamic value, DateTime day) {
  final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return parsed != null &&
      parsed.year == day.year &&
      parsed.month == day.month &&
      parsed.day == day.day;
}

Future<bool> confirmDelete(BuildContext context, String label) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa dữ liệu?'),
        content: Text(
          'Bạn muốn xóa $label? Thao tác này sẽ cập nhật dữ liệu dùng chung.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    ) ??
    false;
