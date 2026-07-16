import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'call_service.dart';
import 'models.dart';
import 'socket_service.dart';

class AppState extends ChangeNotifier {
  AppState() {
    callService = CallService(socketService);
    restoreSession();
  }

  final api = ApiClient();
  final socketService = SocketService();
  final storage = const FlutterSecureStorage();
  late final CallService callService;

  AppUser? currentUser;
  List<ChatSummary> chats = [];
  List<AppUser> userResults = [];
  Set<String> onlineUserIds = {};
  List<ChatMessage> activeMessages = [];
  ChatSummary? activeChat;
  Map<String, dynamic>? incomingCall;
  String? activeCallId;
  String? activePeerId;
  bool activeCallHasVideo = false;
  bool loading = false;
  bool searchingUsers = false;
  bool sessionInitialized = false;
  String? error;
  String _activeSearchQuery = '';

  bool get isAuthenticated => currentUser != null && api.accessToken != null;

  bool isUserOnline(String? userId) =>
      userId != null && onlineUserIds.contains(userId);

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    try {
      final token = await storage.read(key: 'accessToken');
      if (token == null) return;
      api.accessToken = token;
      currentUser = await api.me();
      _connectSocket(token);
      chats = await api.chats();
      _sortChats();
    } catch (_) {
      await storage.delete(key: 'accessToken');
      socketService.disconnect();
      api.accessToken = null;
      currentUser = null;
    } finally {
      sessionInitialized = true;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    await _run(() async {
      final session = await api.login(email: email, password: password);
      await _saveSession(session);
      await refreshChats();
    });
  }

  Future<void> register(String name, String email, String password) async {
    await _run(() async {
      final session = await api.register(
        name: name,
        email: email,
        password: password,
      );
      await _saveSession(session);
      await refreshChats();
    });
  }

  Future<void> logout() async {
    await storage.delete(key: 'accessToken');
    socketService.disconnect();
    api.accessToken = null;
    currentUser = null;
    chats = [];
    userResults = [];
    onlineUserIds = {};
    activeMessages = [];
    activeChat = null;
    incomingCall = null;
    activeCallId = null;
    activePeerId = null;
    await callService.end();
    notifyListeners();
  }

  Future<void> refreshChats() async {
    chats = await api.chats();
    _sortChats();
    notifyListeners();
  }

  Future<void> searchUsers(String query) async {
    final normalized = query.trim();
    _activeSearchQuery = normalized;
    if (normalized.isEmpty) {
      userResults = [];
      searchingUsers = false;
      notifyListeners();
      return;
    }

    searchingUsers = true;
    notifyListeners();
    try {
      final results = await api.searchUsers(normalized);
      if (_activeSearchQuery == normalized) userResults = results;
    } catch (e) {
      if (_activeSearchQuery == normalized) error = e.toString();
    } finally {
      if (_activeSearchQuery == normalized) searchingUsers = false;
      notifyListeners();
    }
  }

  Future<void> openDirectChat(AppUser user) async {
    activeChat = await api.createDirectChat(user.id);
    await openChat(activeChat!);
    await refreshChats();
  }

  Future<void> openChat(ChatSummary chat) async {
    activeChat = chat;
    activeMessages = await api.messages(chat.id);
    _setUnreadCount(chat.id, 0);
    socketService.joinChat(chat.id);
    socketService.markChatRead(chat.id);
    notifyListeners();
    unawaited(api.markChatRead(chat.id).catchError((Object _) {}));
  }

  void sendText(String text) {
    final chat = activeChat;
    if (chat == null || text.trim().isEmpty) return;
    final clientId = const Uuid().v4();
    _addOptimisticMessage(
      ChatMessage(
        id: clientId,
        chatId: chat.id,
        senderId: currentUser!.id,
        type: MessageKind.text,
        text: text.trim(),
        createdAt: DateTime.now(),
        localStatus: MessageReceiptStatus.sending,
      ),
    );
    socketService.sendMessage(
      chatId: chat.id,
      type: MessageKind.text,
      text: text.trim(),
      clientId: clientId,
      onAcknowledged: (message) => _upsertMessage(message, clientId),
      onFailed: (_) => _markMessageFailed(clientId),
    );
  }

  Future<bool> sendFile(File file, {String? caption}) async {
    final chat = activeChat;
    if (chat == null) return false;
    final clientId = const Uuid().v4();
    final fileName = file.uri.pathSegments.last;
    _addOptimisticMessage(
      ChatMessage(
        id: clientId,
        chatId: chat.id,
        senderId: currentUser!.id,
        type: MessageKind.file,
        text: caption?.trim().isEmpty == true ? null : caption?.trim(),
        file: SharedFile(
          id: clientId,
          originalName: fileName,
          mimeType: _localMimeType(fileName),
          size: await file.length(),
          url: '',
          localPath: file.path,
        ),
        createdAt: DateTime.now(),
        localStatus: MessageReceiptStatus.sending,
        uploadProgress: 0,
      ),
    );
    try {
      var lastProgress = 0.0;
      final uploaded = await api.uploadFile(
        file,
        onProgress: (progress) {
          if (progress < 1 && progress - lastProgress < 0.01) return;
          lastProgress = progress;
          _updateUploadProgress(clientId, progress);
        },
      );
      socketService.sendMessage(
        chatId: chat.id,
        type: MessageKind.file,
        text: caption?.trim().isEmpty == true ? null : caption?.trim(),
        fileId: uploaded.id,
        clientId: clientId,
        onAcknowledged: (message) => _upsertMessage(message, clientId),
        onFailed: (_) => _markMessageFailed(clientId),
      );
      return true;
    } catch (e) {
      error = e.toString();
      _markMessageFailed(clientId);
      return false;
    }
  }

  void deleteMessage(String messageId) {
    socketService.deleteMessage(messageId);
  }

  Future<void> startCall(AppUser receiver, {required bool video}) async {
    await _runCallSafely(() async {
      await _ensureCallPermissions(video: video);
      final callId = const Uuid().v4();
      activeCallId = callId;
      activePeerId = receiver.id;
      activeCallHasVideo = video;
      await callService.initializeRenderers();
      await callService.startLocalMedia(video: video);
      await callService.createPeerConnection(
        receiverId: receiver.id,
        callId: callId,
      );
      socketService.inviteCall(
        receiverId: receiver.id,
        callId: callId,
        video: video,
      );
      notifyListeners();
    });
  }

  Future<void> acceptIncomingCall() async {
    await _runCallSafely(() async {
      final call = incomingCall;
      final caller = incomingCaller;
      final callId = incomingCallId;
      if (call == null || caller == null || callId == null) return;
      final video = call['type'] == 'VIDEO';

      await _ensureCallPermissions(video: video);
      activeCallId = callId;
      activePeerId = caller.id;
      activeCallHasVideo = video;
      incomingCall = null;
      await callService.initializeRenderers();
      await callService.startLocalMedia(video: video);
      await callService.createPeerConnection(
        receiverId: caller.id,
        callId: callId,
      );
      socketService.acceptCall(callerId: caller.id, callId: callId);
      notifyListeners();
    });
  }

  void rejectIncomingCall() {
    final caller = incomingCaller;
    final callId = incomingCallId;
    if (caller == null || callId == null) return;
    socketService.rejectCall(
      callerId: caller.id,
      callId: callId,
    );
    incomingCall = null;
    notifyListeners();
  }

  Future<void> endCall() async {
    final peerId = activePeerId;
    final callId = activeCallId;
    if (peerId != null && callId != null) {
      socketService.endCall(receiverId: peerId, callId: callId);
    }
    activeCallId = null;
    activePeerId = null;
    await callService.end();
    notifyListeners();
  }

  Future<void> _saveSession(AuthSession session) async {
    currentUser = session.user;
    api.accessToken = session.accessToken;
    await storage.write(key: 'accessToken', value: session.accessToken);
    _connectSocket(session.accessToken);
    notifyListeners();
  }

  void _connectSocket(String token) {
    socketService.connect(
      token: token,
      onMessage: _upsertMessage,
      onMessageDeleted: _applyDeletedMessage,
      onMessageReceipts: _applyMessageReceipts,
      onPresenceSync: (userIds) {
        onlineUserIds = userIds;
        notifyListeners();
      },
      onUserOnline: (userId) {
        onlineUserIds = {...onlineUserIds, userId};
        notifyListeners();
      },
      onUserOffline: (userId) {
        onlineUserIds = {...onlineUserIds}..remove(userId);
        notifyListeners();
      },
      onConnectionChanged: (connected) {
        if (connected) {
          unawaited(refreshChats());
        } else {
          onlineUserIds = {};
        }
        notifyListeners();
      },
      onIncomingCall: (payload) {
        _runCallSafely(() async {
          incomingCall = payload;
          notifyListeners();
        });
      },
      onCallAccepted: (payload) async {
        await _runCallSafely(() async {
          final peerId = activePeerId;
          final callId = activeCallId;
          if (peerId == null || callId == null) return;
          final offer = await callService.createOffer();
          socketService.sendOffer(
            receiverId: peerId,
            callId: callId,
            offer: offer,
          );
        });
      },
      onCallRejected: (_) => endCall(),
      onCallEnded: (_) => endCall(),
      onWebRtcOffer: (payload) async {
        await _runCallSafely(() async {
          final senderId = payload['senderId'] as String;
          final callId = payload['callId'] as String;
          await callService.receiveOffer(
            Map<String, dynamic>.from(payload['offer'] as Map),
          );
          final answer = await callService.createAnswer();
          socketService.sendAnswer(
            receiverId: senderId,
            callId: callId,
            answer: answer,
          );
        });
      },
      onWebRtcAnswer: (payload) {
        _runCallSafely(() async {
          await callService.receiveAnswer(
            Map<String, dynamic>.from(payload['answer'] as Map),
          );
        });
      },
      onIceCandidate: (payload) {
        _runCallSafely(() async {
          await callService.addIceCandidate(
            Map<String, dynamic>.from(payload['candidate'] as Map),
          );
        });
      },
    );
  }

  AppUser? get incomingCaller {
    final rawCaller = incomingCall?['caller'];
    if (rawCaller is! Map) return null;
    final caller = Map<String, dynamic>.from(rawCaller);
    final id = caller['id'];
    final name = caller['name'];
    final email = caller['email'];
    if (id is! String || name is! String || email is! String) return null;
    return AppUser(id: id, name: name, email: email);
  }

  String? get incomingCallId {
    final callId = incomingCall?['callId'];
    return callId is String ? callId : null;
  }

  Future<void> _runCallSafely(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      error = e.toString();
      await callService.end();
      activeCallId = null;
      activePeerId = null;
      incomingCall = null;
      notifyListeners();
    }
  }

  void _upsertMessage(ChatMessage message, [String? clientId]) {
    final isMine = message.senderId == currentUser?.id;
    final isActive = activeChat?.id == message.chatId;
    if (isActive) {
      activeMessages = [
        ...activeMessages.where(
          (item) => item.id != message.id && item.id != clientId,
        ),
        message,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final chatIndex = chats.indexWhere((chat) => chat.id == message.chatId);
    if (chatIndex == -1) {
      refreshChats();
      return;
    }

    final currentChat = chats[chatIndex];
    final unreadCount = !isMine && !isActive
        ? currentChat.unreadCount + 1
        : isActive
            ? 0
            : currentChat.unreadCount;
    final updatedChat = currentChat.copyWith(
      lastMessage: message,
      unreadCount: unreadCount,
    );
    chats = [
      updatedChat,
      ...chats.where((chat) => chat.id != message.chatId),
    ];
    if (isActive) {
      activeChat = updatedChat;
      if (!isMine) socketService.markChatRead(message.chatId);
    }
    notifyListeners();
  }

  void _addOptimisticMessage(ChatMessage message) {
    activeMessages = [...activeMessages, message]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final chatIndex = chats.indexWhere((chat) => chat.id == message.chatId);
    if (chatIndex != -1) {
      final updatedChat = chats[chatIndex].copyWith(lastMessage: message);
      chats = [
        updatedChat,
        ...chats.where((chat) => chat.id != message.chatId),
      ];
      activeChat = updatedChat;
    }
    notifyListeners();
  }

  void _markMessageFailed(String clientId) {
    activeMessages = activeMessages
        .map(
          (message) => message.id == clientId
              ? message.withLocalStatus(MessageReceiptStatus.failed)
              : message,
        )
        .toList();
    chats = chats.map((chat) {
      final lastMessage = chat.lastMessage;
      if (lastMessage?.id != clientId) return chat;
      return chat.copyWith(
        lastMessage: lastMessage!.withLocalStatus(MessageReceiptStatus.failed),
      );
    }).toList();
    notifyListeners();
  }

  void _updateUploadProgress(String clientId, double progress) {
    activeMessages = activeMessages
        .map(
          (message) => message.id == clientId
              ? message.withUploadProgress(progress)
              : message,
        )
        .toList();
    chats = chats.map((chat) {
      final lastMessage = chat.lastMessage;
      if (lastMessage?.id != clientId) return chat;
      return chat.copyWith(
        lastMessage: lastMessage!.withUploadProgress(progress),
      );
    }).toList();
    notifyListeners();
  }

  void _applyDeletedMessage(ChatMessage message) {
    if (activeChat?.id == message.chatId) {
      activeMessages = [
        ...activeMessages.where((item) => item.id != message.id),
        message,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final chatIndex = chats.indexWhere((chat) => chat.id == message.chatId);
    if (chatIndex != -1 && chats[chatIndex].lastMessage?.id == message.id) {
      chats[chatIndex] = chats[chatIndex].copyWith(lastMessage: message);
    }
    notifyListeners();
  }

  void _applyMessageReceipts(
    List<String> messageIds,
    String userId,
    MessageReceiptStatus status,
  ) {
    if (messageIds.isEmpty) return;
    final ids = messageIds.toSet();
    activeMessages = activeMessages
        .map(
          (message) => ids.contains(message.id)
              ? message.withReceiptStatus(userId, status)
              : message,
        )
        .toList();
    chats = chats.map((chat) {
      final message = chat.lastMessage;
      if (message == null || !ids.contains(message.id)) return chat;
      return chat.copyWith(
        lastMessage: message.withReceiptStatus(userId, status),
      );
    }).toList();
    if (activeChat?.lastMessage case final message?) {
      if (ids.contains(message.id)) {
        activeChat = activeChat?.copyWith(
          lastMessage: message.withReceiptStatus(userId, status),
        );
      }
    }
    notifyListeners();
  }

  void _setUnreadCount(String chatId, int count) {
    chats = chats
        .map((chat) =>
            chat.id == chatId ? chat.copyWith(unreadCount: count) : chat)
        .toList();
    if (activeChat?.id == chatId) {
      activeChat = activeChat?.copyWith(unreadCount: count);
    }
  }

  void _sortChats() {
    chats.sort((a, b) {
      final aTime =
          a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  Future<void> _ensureCallPermissions({required bool video}) async {
    final permissions = [Permission.microphone, if (video) Permission.camera];
    final statuses = await permissions.request();
    if (statuses.values.any((status) => !status.isGranted)) {
      throw ApiException('Camera or microphone permission was denied');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

String _localMimeType(String fileName) {
  final extension = fileName.toLowerCase().split('.').last;
  if (const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'}
      .contains(extension)) {
    return 'image/$extension';
  }
  if (extension == 'pdf') return 'application/pdf';
  if (const {'mp3', 'wav', 'aac', 'm4a', 'ogg'}.contains(extension)) {
    return 'audio/$extension';
  }
  if (const {'mp4', 'mov', 'avi', 'mkv', 'webm'}.contains(extension)) {
    return 'video/$extension';
  }
  return 'application/octet-stream';
}
