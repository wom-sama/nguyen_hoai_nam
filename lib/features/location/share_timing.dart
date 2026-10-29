int? renewalMinutes(DateTime consentExpiresAt, DateTime now) {
  final seconds = consentExpiresAt.difference(now).inSeconds;
  if (seconds < 60) return null;
  return (seconds ~/ 60).clamp(1, 15);
}
