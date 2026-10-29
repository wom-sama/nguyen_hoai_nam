typedef Json = Map<String, dynamic>;

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.role,
    required this.status,
    this.branchId,
  });
  final String id, fullName, username, email, role, status;
  final String? branchId;
  bool get isActive => status == 'active';
  bool get isAdmin => role == 'admin' && isActive;
  bool get canManage => isActive && (role == 'admin' || role == 'manager');
  String get roleLabel => switch (role) {
    'admin' => 'Quản trị viên',
    'manager' => 'Quản lý',
    _ => 'Nhân viên',
  };
  factory AppUser.fromJson(Json j) => AppUser(
    id: j['id'] as String,
    fullName: j['fullName'] as String,
    username: j['username'] as String,
    email: j['email'] as String,
    role: j['role'] as String,
    status: j['status'] as String,
    branchId: j['branchId'] as String?,
  );
}

class AuthChallenge {
  const AuthChallenge({
    required this.id,
    required this.maskedEmail,
    required this.expiresAt,
    required this.retryAfterSeconds,
    required this.purpose,
  });
  final String id, maskedEmail, purpose;
  final DateTime expiresAt;
  final int retryAfterSeconds;
  factory AuthChallenge.fromJson(Json j) => AuthChallenge(
    id: j['challengeId'] as String,
    maskedEmail: j['maskedEmail'] as String,
    expiresAt: DateTime.parse(j['expiresAt'] as String),
    retryAfterSeconds: (j['retryAfterSeconds'] as num?)?.toInt() ?? 60,
    purpose: j['purpose'] as String? ?? 'login',
  );
}

class StoredSession {
  const StoredSession({this.baseUrl = '', this.accessToken, this.refreshToken});
  final String baseUrl;
  final String? accessToken, refreshToken;
}
