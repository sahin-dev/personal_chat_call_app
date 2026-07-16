import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? accessToken;

  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final json = await _request(
      'POST',
      '/auth/register',
      body: {'name': name, 'email': email, 'password': password},
      authenticated: false,
    );
    final session = AuthSession.fromJson(json);
    accessToken = session.accessToken;
    return session;
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final json = await _request(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final session = AuthSession.fromJson(json);
    accessToken = session.accessToken;
    return session;
  }

  Future<AppUser> me() async {
    final json = await _request('GET', '/auth/me');
    return AppUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<List<AppUser>> searchUsers(String query) async {
    final encodedQuery = Uri.encodeQueryComponent(query);
    final json = await _request('GET', '/users?query=$encodedQuery');
    return (json as List<dynamic>)
        .map((item) => AppUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatSummary>> chats() async {
    final json = await _request('GET', '/chats');
    return (json as List<dynamic>)
        .map((item) => ChatSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatSummary> createDirectChat(String userId) async {
    final json = await _request(
      'POST',
      '/chats/direct',
      body: {'userId': userId},
    );
    return ChatSummary.fromJson(json);
  }

  Future<List<ChatMessage>> messages(String chatId) async {
    final json = await _request('GET', '/chats/$chatId/messages');
    return (json as List<dynamic>)
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendText(String chatId, String text) async {
    final json = await _request(
      'POST',
      '/chats/$chatId/messages',
      body: {'type': 'TEXT', 'text': text},
    );
    return ChatMessage.fromJson(json);
  }

  Future<ChatMessage> sendFileMessage(
    String chatId,
    String fileId, {
    String? caption,
  }) async {
    final json = await _request(
      'POST',
      '/chats/$chatId/messages',
      body: {
        'type': 'FILE',
        'fileId': fileId,
        if (caption?.trim().isNotEmpty == true) 'text': caption!.trim(),
      },
    );
    return ChatMessage.fromJson(json);
  }

  Future<ChatMessage> deleteMessage(String messageId) async {
    final json = await _request('DELETE', '/messages/$messageId');
    return ChatMessage.fromJson(json);
  }

  Future<void> markChatRead(String chatId) async {
    await _request('POST', '/chats/$chatId/read');
  }

  Future<SharedFile> uploadFile(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/files/upload');
    final request = _ProgressMultipartRequest('POST', uri, onProgress)
      ..headers.addAll(_headers(jsonContent: false))
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final response = await _client.send(request);
    final body = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(body);
    }

    return SharedFile.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    if (authenticated && accessToken == null) {
      throw ApiException('Missing access token');
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final request = http.Request(method, uri)
      ..headers.addAll(_headers())
      ..body = body == null ? '' : jsonEncode(body);
    final response = await _client.send(request);
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(responseBody);
    }

    return responseBody.isEmpty ? null : jsonDecode(responseBody);
  }

  Map<String, String> _headers({bool jsonContent = true}) {
    return {
      if (jsonContent) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }
}

class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(super.method, super.url, this.onProgress);

  final void Function(double progress)? onProgress;

  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    final total = contentLength;
    var uploaded = 0;
    return http.ByteStream(
      stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, sink) {
            uploaded += chunk.length;
            if (total > 0) {
              onProgress?.call((uploaded / total).clamp(0, 1));
            }
            sink.add(chunk);
          },
        ),
      ),
    );
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
