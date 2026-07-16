import 'package:socket_io_client/socket_io_client.dart' as io;

import 'config.dart';
import 'models.dart';

typedef MessageHandler = void Function(ChatMessage message);
typedef NewMessageHandler = void Function(
  ChatMessage message,
  String? clientId,
);
typedef SendAcknowledgedHandler = void Function(ChatMessage message);
typedef SendFailedHandler = void Function(String reason);
typedef RawEventHandler = void Function(Map<String, dynamic> payload);
typedef PresenceSyncHandler = void Function(Set<String> userIds);
typedef UserPresenceHandler = void Function(String userId);
typedef ConnectionHandler = void Function(bool connected);
typedef MessageReceiptsHandler = void Function(
  List<String> messageIds,
  String userId,
  MessageReceiptStatus status,
);

class SocketService {
  io.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;

  void connect({
    required String token,
    NewMessageHandler? onMessage,
    MessageHandler? onMessageDeleted,
    MessageReceiptsHandler? onMessageReceipts,
    PresenceSyncHandler? onPresenceSync,
    UserPresenceHandler? onUserOnline,
    UserPresenceHandler? onUserOffline,
    ConnectionHandler? onConnectionChanged,
    RawEventHandler? onIncomingCall,
    RawEventHandler? onCallAccepted,
    RawEventHandler? onCallRejected,
    RawEventHandler? onCallEnded,
    RawEventHandler? onWebRtcOffer,
    RawEventHandler? onWebRtcAnswer,
    RawEventHandler? onIceCandidate,
  }) {
    disconnect();
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!
      ..on('connect', (_) => onConnectionChanged?.call(true))
      ..on('disconnect', (_) => onConnectionChanged?.call(false))
      ..on('message:new', (data) {
        final payload = Map<String, dynamic>.from(data as Map);
        onMessage?.call(
          ChatMessage.fromJson(payload['message'] as Map<String, dynamic>),
          payload['clientId'] as String?,
        );
      })
      ..on('message:deleted', (data) {
        final payload = Map<String, dynamic>.from(data as Map);
        onMessageDeleted?.call(
          ChatMessage.fromJson(payload['message'] as Map<String, dynamic>),
        );
      })
      ..on('messages:receipts', (data) {
        final payload = _map(data);
        final userId = payload['userId'];
        if (userId is! String) return;
        final messageIds = (payload['messageIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
        final status = switch (payload['status']) {
          'READ' => MessageReceiptStatus.seen,
          'DELIVERED' => MessageReceiptStatus.delivered,
          _ => MessageReceiptStatus.sent,
        };
        onMessageReceipts?.call(messageIds, userId, status);
      })
      ..on('presence:sync', (data) {
        final payload = _map(data);
        final userIds = (payload['userIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet();
        onPresenceSync?.call(userIds);
      })
      ..on('user:online', (data) {
        final userId = _map(data)['userId'];
        if (userId is String) onUserOnline?.call(userId);
      })
      ..on('user:offline', (data) {
        final userId = _map(data)['userId'];
        if (userId is String) onUserOffline?.call(userId);
      })
      ..on('call:invite', (data) => onIncomingCall?.call(_map(data)))
      ..on('call:accept', (data) => onCallAccepted?.call(_map(data)))
      ..on('call:reject', (data) => onCallRejected?.call(_map(data)))
      ..on('call:end', (data) => onCallEnded?.call(_map(data)))
      ..on('webrtc:offer', (data) => onWebRtcOffer?.call(_map(data)))
      ..on('webrtc:answer', (data) => onWebRtcAnswer?.call(_map(data)))
      ..on('webrtc:ice-candidate', (data) => onIceCandidate?.call(_map(data)))
      ..connect();
  }

  void joinChat(String chatId) {
    _socket?.emit('chat:join', {'chatId': chatId});
  }

  void sendMessage({
    required String chatId,
    required MessageKind type,
    String? text,
    String? fileId,
    String? clientId,
    SendAcknowledgedHandler? onAcknowledged,
    SendFailedHandler? onFailed,
  }) {
    final socket = _socket;
    if (socket == null) {
      onFailed?.call('Not connected');
      return;
    }
    socket.emitWithAck('message:send', {
      'chatId': chatId,
      'type': type == MessageKind.file ? 'FILE' : 'TEXT',
      if (text != null) 'text': text,
      if (fileId != null) 'fileId': fileId,
      if (clientId != null) 'clientId': clientId,
    }, ack: (dynamic response, [dynamic _]) {
      if (response is! Map) {
        onFailed?.call('Invalid server response');
        return;
      }
      final payload = Map<String, dynamic>.from(response);
      if (payload['ok'] != true || payload['message'] is! Map) {
        onFailed?.call(payload['message'] as String? ?? 'Message failed');
        return;
      }
      onAcknowledged?.call(
        ChatMessage.fromJson(
          Map<String, dynamic>.from(payload['message'] as Map),
        ),
      );
    });
  }

  void deleteMessage(String messageId) {
    _socket?.emit('message:delete', {'messageId': messageId});
  }

  void markChatRead(String chatId) {
    _socket?.emit('chat:read', {'chatId': chatId});
  }

  void startTyping(String chatId) {
    _socket?.emit('typing:start', {'chatId': chatId});
  }

  void stopTyping(String chatId) {
    _socket?.emit('typing:stop', {'chatId': chatId});
  }

  void inviteCall({
    required String receiverId,
    required String callId,
    required bool video,
  }) {
    _socket?.emit('call:invite', {
      'receiverId': receiverId,
      'callId': callId,
      'type': video ? 'VIDEO' : 'AUDIO',
    });
  }

  void acceptCall({required String callerId, required String callId}) {
    _socket?.emit('call:accept', {'callerId': callerId, 'callId': callId});
  }

  void rejectCall({required String callerId, required String callId}) {
    _socket?.emit('call:reject', {'callerId': callerId, 'callId': callId});
  }

  void endCall({required String receiverId, required String callId}) {
    _socket?.emit('call:end', {'receiverId': receiverId, 'callId': callId});
  }

  void sendOffer({
    required String receiverId,
    required String callId,
    required Map<String, dynamic> offer,
  }) {
    _socket?.emit('webrtc:offer', {
      'receiverId': receiverId,
      'callId': callId,
      'offer': offer,
    });
  }

  void sendAnswer({
    required String receiverId,
    required String callId,
    required Map<String, dynamic> answer,
  }) {
    _socket?.emit('webrtc:answer', {
      'receiverId': receiverId,
      'callId': callId,
      'answer': answer,
    });
  }

  void sendIceCandidate({
    required String receiverId,
    required String callId,
    required Map<String, dynamic> candidate,
  }) {
    _socket?.emit('webrtc:ice-candidate', {
      'receiverId': receiverId,
      'callId': callId,
      'candidate': candidate,
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  Map<String, dynamic> _map(dynamic data) {
    return Map<String, dynamic>.from(data as Map);
  }
}
