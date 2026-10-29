import 'package:geolocator/geolocator.dart';

import 'api_client.dart';

Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const ApiException(
      'LOCATION_OFF',
      'Dịch vụ vị trí đang tắt. Vui lòng bật vị trí rồi thử lại.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const ApiException(
      'LOCATION_PERMISSION',
      'Cần quyền vị trí để chấm công hoặc chia sẻ vị trí.',
    );
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
  } catch (e) {
    throw const ApiException(
      'LOCATION_UNAVAILABLE',
      'Chưa lấy được vị trí đủ chính xác. Hãy kiểm tra GPS hoặc vị trí của giả lập.',
    );
  }
}
