import 'dart:async';

import 'package:http/http.dart' as http;

import 'config.dart';

class BackendPingService {
  BackendPingService._();

  static final instance = BackendPingService._();

  static const _interval = Duration(seconds: 10);
  static const _timeout = Duration(seconds: 8);

  final http.Client _client = http.Client();
  Timer? _timer;
  bool _isPingInFlight = false;

  void start() {
    _timer ??= Timer.periodic(_interval, (_) {
      _ping();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ping() async {
    if (_isPingInFlight) return;

    _isPingInFlight = true;
    try {
      await _client.get(Uri.parse(AppConfig.apiBaseUrl)).timeout(_timeout);
    } catch (_) {
      // Keep the scheduler alive even when the backend is sleeping or offline.
    } finally {
      _isPingInFlight = false;
    }
  }
}
