class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://chat-call-backend-37bk.onrender.com',
  );

  static const socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: apiBaseUrl,
  );
  static String resolveFileUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      return '$apiBaseUrl${uri.path}';
    }
    return url;
  }
}
