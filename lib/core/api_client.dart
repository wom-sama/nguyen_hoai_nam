import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.code, this.message, [this.status = 0]);
  final String code, message;
  final int status;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String baseUrl = '', http.Client? transport})
    : _transport = transport ?? http.Client() {
    if (baseUrl.isNotEmpty) configure(baseUrl);
  }
  final http.Client _transport;
  String _baseUrl = '';
  String? accessToken;
  Future<bool> Function()? onUnauthorized;
  String get baseUrl => _baseUrl;
  bool get isConfigured => _baseUrl.isNotEmpty;

  static String validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443)) {
      throw const ApiException(
        'INVALID_URL',
        'Cần địa chỉ máy chủ HTTPS công khai.',
      );
    }
    final host = uri.host.toLowerCase().replaceAll(RegExp(r'[\[\]]'), '');
    final address = InternetAddress.tryParse(host);
    final bytes = address?.rawAddress;
    final localV4 =
        bytes != null &&
        bytes.length == 4 &&
        (bytes[0] == 0 ||
            bytes[0] == 10 ||
            bytes[0] == 127 ||
            (bytes[0] == 169 && bytes[1] == 254) ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
            (bytes[0] == 192 && bytes[1] == 168));
    final localV6 =
        bytes != null &&
        bytes.length == 16 &&
        ((bytes[0] & 0xfe) == 0xfc ||
            (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80));
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        (!host.contains('.') && address == null) ||
        (address?.isLoopback ?? false) ||
        (address?.isLinkLocal ?? false) ||
        (address?.isMulticast ?? false) ||
        localV4 ||
        localV6) {
      throw const ApiException(
        'INVALID_URL',
        'API phải được deploy lên Internet, không dùng localhost hoặc mạng nội bộ.',
      );
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (!path.endsWith('/v1')) path += '/v1';
    return uri.replace(path: path).toString();
  }

  void configure(String value) => _baseUrl = validateUrl(value);
  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      request('GET', path, query: query);
  Future<dynamic> post(String path, Json body, {bool authenticated = true}) =>
      request('POST', path, body: body, authenticated: authenticated);
  Future<dynamic> patch(String path, Json body) =>
      request('PATCH', path, body: body);
  Future<dynamic> delete(String path) => request('DELETE', path);

  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    bool authenticated = true,
    bool retry = true,
  }) async {
    if (!isConfigured) {
      throw const ApiException(
        'NOT_CONFIGURED',
        'Cần kết nối máy chủ trước khi tiếp tục.',
      );
    }
    final uri = Uri.parse(_baseUrl + path).replace(queryParameters: query);
    final req = http.Request(method, uri)..followRedirects = false;
    req.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    });
    if (authenticated && accessToken != null) {
      req.headers['Authorization'] = 'Bearer ${accessToken!}';
    }
    if (body != null) req.body = jsonEncode(body);
    http.Response response;
    try {
      response = await http.Response.fromStream(await _transport.send(req))
          .timeout(const Duration(seconds: 70));
    } on TimeoutException {
      throw const ApiException(
        'TIMEOUT',
        'Máy chủ phản hồi chậm. Hãy thử lại trong ít phút.',
      );
    } on SocketException {
      throw const ApiException(
        'NETWORK',
        'Chưa kết nối được Internet. Hãy kiểm tra mạng và thử lại.',
      );
    } on http.ClientException {
      throw const ApiException(
        'NETWORK',
        'Không thể kết nối máy chủ. Hãy thử lại.',
      );
    }
    if (response.statusCode == 401 &&
        authenticated &&
        retry &&
        onUnauthorized != null &&
        await onUnauthorized!()) {
      return request(
        method,
        path,
        body: body,
        query: query,
        authenticated: authenticated,
        retry: false,
      );
    }
    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        'SERVER_RESPONSE',
        'Máy chủ chưa sẵn sàng hoặc phản hồi không hợp lệ.',
        response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded['error'] : null;
      final code = error is Map
          ? error['code']?.toString() ?? 'REQUEST_FAILED'
          : 'REQUEST_FAILED';
      final message = error is Map ? error['message']?.toString() : null;
      final userMessage = switch (code) {
        'DATABASE_UNAVAILABLE' =>
          'Dịch vụ tạm thời chưa sẵn sàng. Vui lòng thử lại sau.',
        'NOT_FOUND' => 'Không tìm thấy nội dung. Vui lòng tải lại.',
        'JSON_INVALID' => 'Chưa gửi được nội dung. Vui lòng thử lại.',
        'PUSH_DISABLED' || 'PUSH_PROJECT_MISMATCH' => 'Chưa bật được thông báo trên thiết bị này. Vui lòng liên hệ quản trị viên.',
        'CRITICAL_FACT_DUPLICATE' =>
          'Thông tin quan trọng bị trùng. Hãy giữ mỗi mục một lần.',
        'FACT_ANSWERS_INVALID' =>
          'Nhập lại đầy đủ các thông tin quan trọng, mỗi mục một lần.',
        _ => message ?? 'Chưa thực hiện được thao tác. Hãy thử lại.',
      };
      throw ApiException(code, userMessage, response.statusCode);
    }
    if (decoded == null) return null;
    if (decoded is! Map || !decoded.containsKey('data')) {
      throw const ApiException(
        'SERVER_RESPONSE',
        'Dữ liệu từ máy chủ không đúng định dạng.',
      );
    }
    return decoded['data'];
  }

  void close() => _transport.close();
}
