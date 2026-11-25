import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'call_service.dart';
import 'models.dart';
import 'push_notification_service.dart';
import 'socket_service.dart';

const _unset = Object();

class AppState {
  const AppState({
    this.currentUser,
    this.chats = const [],
    this.userResults = const [],
    this.onlineUserIds = const {},
    this.activeMessages = const [],
    this.activeChat,
    this.incomingCall,
    this.activeCallId,
    this.activePeerId,
    this.activeCallHasVideo = false,
    this.loading = false,
    this.searchingUsers = false,
    this.sessionInitialized = false,
    this.error,
  });

  final AppUser? currentUser;
  final List<ChatSummary> chats;
  final List<AppUser> userResults;
  final Set<String> onlineUserIds;
  final List<ChatMessage> activeMessages;
  final ChatSummary? activeChat;
  final Map<String, dynamic>? incomingCall;
  final String? activeCallId;
  final String? activePeerId;
  final bool activeCallHasVideo;
  final bool loading;
  final bool searchingUsers;
  final bool sessionInitialized;
  final String? error;

  bool get isAuthenticated => currentUser != null;

  bool isUserOnline(String? userId) =>
      userId != null && onlineUserIds.contains(userId);

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

  AppState copyWith({
    Object? currentUser = _unset,
    List<ChatSummary>? chats,
    List<AppUser>? userResults,
    Set<String>? onlineUserIds,
    List<ChatMessage>? activeMessages,
    Object? activeChat = _unset,
    Object? incomingCall = _unset,
    Object? activeCallId = _unset,
    Object? activePeerId = _unset,
    bool? activeCallHasVideo,
    bool? loading,
    bool? searchingUsers,
    bool? sessionInitialized,
    Object? error = _unset,
  }) {
    return AppState(
      currentUser: identical(currentUser, _unset)
          ? this.currentUser
          : currentUser as AppUser?,
      chats: chats ?? this.chats,
      userResults: userResults ?? this.userResults,
      onlineUserIds: onlineUserIds ?? this.onlineUserIds,
      activeMessages: activeMessages ?? this.activeMessages,
      activeChat:
          identical(activeChat, _unset) ? this.activeChat : activeChat as ChatSummary?,
      incomingCall: identical(incomingCall, _unset)
          ? this.incomingCall
          : incomingCall as Map<String, dynamic>?,
      activeCallId:
          identical(activeCallId, _unset) ? this.activeCallId : activeCallId as String?,
      activePeerId:
          identical(activePeerId, _unset) ? this.activePeerId : activePeerId as String?,
      activeCallHasVideo: activeCallHasVideo ?? this.activeCallHasVideo,
      loading: loading ?? this.loading,
      searchingUsers: searchingUsers ?? this.searchingUsers,
      sessionInitialized: sessionInitialized ?? this.sessionInitialized,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class AppCubit extends Cubit<AppState> {
  AppCubit() : super(const AppState()) {
    callService = CallService(socketService);
    restoreSession();
  }

  final api = ApiClient();
  final socketService = SocketService();
  final storage = const FlutterSecureStorage();
  late final CallService callService;

  String _activeSearchQuery = '';
  int _sessionEpoch = 0;

  void clearError() {
    if (state.error == null) return;
    _emit(state.copyWith(error: null));
  }

  Future<void> restoreSession() async {
    try {
      final token = await storage.read(key: 'accessToken');
      if (token == null) return;
      api.accessToken = token;
      final currentUser = await api.me();
      _emit(state.copyWith(currentUser: currentUser));
      unawaited(PushNotificationService.instance.registerDevice(api));
      _connectSocket(token);
      final chats = _sortedChats(await api.chats());
      _emit(state.copyWith(chats: chats));
    } catch (_) {
      await storage.delete(key: 'accessToken');
      socketService.disconnect();
      api.accessToken = null;
      _emit(state.copyWith(currentUser: null));
    } finally {
      _emit(state.copyWith(sessionInitialized: true));
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
    _sessionEpoch++;
    final logoutToken = api.accessToken;
    if (logoutToken != null) {
      unawaited(
        PushNotificationService.instance
            .unregisterDevice(api, logoutToken)
            .catchError((Object _) {}),
      );
    }
    socketService.disconnect();
    api.accessToken = null;
    _emit(
      state.copyWith(
        currentUser: null,
        chats: [],
        userResults: [],
        onlineUserIds: {},
        activeMessages: [],
        activeChat: null,
        incomingCall: null,
        activeCallId: null,
        activePeerId: null,
        activeCallHasVideo: false,
        loading: false,
        searchingUsers: false,
        error: null,
      ),
    );

    unawaited(storage.delete(key: 'accessToken'));
    unawaited(callService.end().catchError((Object _) {}));
  }

  Future<void> refreshChats() async {
    final chats = _sortedChats(await api.chats());
    _emit(state.copyWith(chats: chats));
  }

  Future<void> searchUsers(String query) async {
    final normalized = query.trim();
    _activeSearchQuery = normalized;
    if (normalized.isEmpty) {
      _emit(state.copyWith(userResults: [], searchingUsers: false));
      return;
    }

    _emit(state.copyWith(searchingUsers: true));
    try {
      final results = await api.searchUsers(normalized);
      if (_activeSearchQuery == normalized) {
        _emit(state.copyWith(userResults: results));
      }
    } catch (e) {
      if (_activeSearchQuery == normalized) {
        _emit(state.copyWith(error: e.toString()));
      }
    } finally {
      if (_activeSearchQuery == normalized) {
        _emit(state.copyWith(searchingUsers: false));
      }
    }
  }

  Future<void> openDirectChat(AppUser user) async {
    final chat = await api.createDirectChat(user.id);
    await openChat(chat);
    await refreshChats();
  }

  Future<void> openChat(ChatSummary chat) async {
    final messages = await api.messages(chat.id);
    final next = _setUnreadCountOn(
      state.copyWith(activeChat: chat, activeMessages: messages),
      chat.id,
      0,
    );
    _emit(next);
    socketService.joinChat(chat.id);
    socketService.markChatRead(chat.id);
    unawaited(api.markChatRead(chat.id).catchError((Object _) {}));
  }

  void sendText(String text) {
    final chat = state.activeChat;
    final currentUser = state.currentUser;
    if (chat == null || currentUser == null || text.trim().isEmpty) return;
    final clientId = const Uuid().v4();
    _addOptimisticMessage(
      ChatMessage(
        id: clientId,
        chatId: chat.id,
        senderId: currentUser.id,
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
    final chat = state.activeChat;
    final currentUser = state.currentUser;
    if (chat == null || currentUser == null) return false;
    final clientId = const Uuid().v4();
    final fileName = file.uri.pathSegments.last;
    _addOptimisticMessage(
      ChatMessage(
        id: clientId,
        chatId: chat.id,
        senderId: currentUser.id,
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
      _emit(state.copyWith(error: e.toString()));
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
      await callService.initializeRenderers();
      await callService.startLocalMedia(video: video);
      final iceServers = await _loadIceServers();
      await callService.createPeerConnection(
        receiverId: receiver.id,
        callId: callId,
        iceServers: iceServers,
      );
      socketService.inviteCall(
        receiverId: receiver.id,
        callId: callId,
        video: video,
      );
      _emit(
        state.copyWith(
          activeCallId: callId,
          activePeerId: receiver.id,
          activeCallHasVideo: video,
        ),
      );
    });
  }

  Future<void> acceptIncomingCall() async {
    await _runCallSafely(() async {
      final call = state.incomingCall;
      final caller = state.incomingCaller;
      final callId = state.incomingCallId;
      if (call == null || caller == null || callId == null) return;
      final video = call['type'] == 'VIDEO';

      await _ensureCallPermissions(video: video);
      await callService.initializeRenderers();
      await callService.startLocalMedia(video: video);
      final iceServers = await _loadIceServers();
      await callService.createPeerConnection(
        receiverId: caller.id,
        callId: callId,
        iceServers: iceServers,
      );
      socketService.acceptCall(callerId: caller.id, callId: callId);
      _emit(
        state.copyWith(
          activeCallId: callId,
          activePeerId: caller.id,
          activeCallHasVideo: video,
          incomingCall: null,
        ),
      );
    });
  }

  void rejectIncomingCall() {
    final caller = state.incomingCaller;
    final callId = state.incomingCallId;
    if (caller == null || callId == null) return;
    socketService.rejectCall(
      callerId: caller.id,
      callId: callId,
    );
    _emit(state.copyWith(incomingCall: null));
  }

  Future<void> endCall() async {
    final peerId = state.activePeerId;
    final callId = state.activeCallId;
    if (peerId != null && callId != null) {
      socketService.endCall(receiverId: peerId, callId: callId);
    }
    await callService.end();
    _emit(
      state.copyWith(
        activeCallId: null,
        activePeerId: null,
        activeCallHasVideo: false,
      ),
    );
  }

  Future<void> _saveSession(AuthSession session) async {
    _sessionEpoch++;
    api.accessToken = session.accessToken;
    await storage.write(key: 'accessToken', value: session.accessToken);
    _emit(state.copyWith(currentUser: session.user));
    unawaited(PushNotificationService.instance.registerDevice(api));
    _connectSocket(session.accessToken);
  }

  void _connectSocket(String token) {
    final sessionEpoch = _sessionEpoch;
    bool isCurrentSession() =>
        sessionEpoch == _sessionEpoch && api.accessToken == token;

    socketService.connect(
      token: token,
      onMessage: (message, clientId) {
        if (!isCurrentSession()) return;
        _upsertMessage(message, clientId);
      },
      onMessageDeleted: (message) {
        if (!isCurrentSession()) return;
        _applyDeletedMessage(message);
      },
      onMessageReceipts: (messageIds, userId, status) {
        if (!isCurrentSession()) return;
        _applyMessageReceipts(messageIds, userId, status);
      },
      onPresenceSync: (userIds) {
        if (!isCurrentSession()) return;
        _emit(state.copyWith(onlineUserIds: userIds));
      },
      onUserOnline: (userId) {
        if (!isCurrentSession()) return;
        _emit(state.copyWith(onlineUserIds: {...state.onlineUserIds, userId}));
      },
      onUserOffline: (userId) {
        if (!isCurrentSession()) return;
        _emit(
          state.copyWith(onlineUserIds: {...state.onlineUserIds}..remove(userId)),
        );
      },
      onConnectionChanged: (connected) {
        if (!isCurrentSession()) return;
        if (connected) {
          unawaited(refreshChats());
        } else {
          _emit(state.copyWith(onlineUserIds: {}));
        }
      },
      onIncomingCall: (payload) {
        if (!isCurrentSession()) return;
        _runCallSafely(() async {
          _emit(state.copyWith(incomingCall: payload));
        });
      },
      onCallAccepted: (payload) async {
        if (!isCurrentSession()) return;
        await _runCallSafely(() async {
          final peerId = state.activePeerId;
          final callId = state.activeCallId;
          if (peerId == null || callId == null) return;
          final offer = await callService.createOffer();
          socketService.sendOffer(
            receiverId: peerId,
            callId: callId,
            offer: offer,
          );
        });
      },
      onCallRejected: (_) {
        if (!isCurrentSession()) return;
        unawaited(endCall());
      },
      onCallEnded: (_) {
        if (!isCurrentSession()) return;
        unawaited(endCall());
      },
      onWebRtcOffer: (payload) async {
        if (!isCurrentSession()) return;
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
        if (!isCurrentSession()) return;
        _runCallSafely(() async {
          await callService.receiveAnswer(
            Map<String, dynamic>.from(payload['answer'] as Map),
          );
        });
      },
      onIceCandidate: (payload) {
        if (!isCurrentSession()) return;
        _runCallSafely(() async {
          await callService.addIceCandidate(
            Map<String, dynamic>.from(payload['candidate'] as Map),
          );
        });
      },
    );
  }

  Future<void> _runCallSafely(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      await callService.end();
      _emit(
        state.copyWith(
          error: e.toString(),
          activeCallId: null,
          activePeerId: null,
          activeCallHasVideo: false,
          incomingCall: null,
        ),
      );
    }
  }

  Future<List<IceServer>> _loadIceServers() async {
    try {
      return await api.iceServers();
    } catch (_) {
      return const [];
    }
  }

  void _upsertMessage(ChatMessage message, [String? clientId]) {
    final isMine = message.isFromUser(state.currentUser);
    final isActive = state.activeChat?.id == message.chatId;
    var nextMessages = state.activeMessages;
    if (isActive) {
      nextMessages = [
        ...state.activeMessages.where(
          (item) => item.id != message.id && item.id != clientId,
        ),
        message,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final chatIndex = state.chats.indexWhere((chat) => chat.id == message.chatId);
    if (chatIndex == -1) {
      if (isActive) _emit(state.copyWith(activeMessages: nextMessages));
      unawaited(refreshChats());
      return;
    }

    final currentChat = state.chats[chatIndex];
    final unreadCount = !isMine && !isActive
        ? currentChat.unreadCount + 1
        : isActive
            ? 0
            : currentChat.unreadCount;
    final updatedChat = currentChat.copyWith(
      lastMessage: message,
      unreadCount: unreadCount,
    );
    final nextChats = [
      updatedChat,
      ...state.chats.where((chat) => chat.id != message.chatId),
    ];
    _emit(
      state.copyWith(
        activeMessages: nextMessages,
        chats: nextChats,
        activeChat: isActive ? updatedChat : state.activeChat,
      ),
    );
    if (isActive && !isMine) socketService.markChatRead(message.chatId);
  }

  void _addOptimisticMessage(ChatMessage message) {
    final nextMessages = [...state.activeMessages, message]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final chatIndex = state.chats.indexWhere((chat) => chat.id == message.chatId);
    if (chatIndex == -1) {
      _emit(state.copyWith(activeMessages: nextMessages));
      return;
    }

    final updatedChat = state.chats[chatIndex].copyWith(lastMessage: message);
    final nextChats = [
      updatedChat,
      ...state.chats.where((chat) => chat.id != message.chatId),
    ];
    _emit(
      state.copyWith(
        activeMessages: nextMessages,
        chats: nextChats,
        activeChat: updatedChat,
      ),
    );
  }

  void _markMessageFailed(String clientId) {
    final nextMessages = state.activeMessages
        .map(
          (message) => message.id == clientId
              ? message.withLocalStatus(MessageReceiptStatus.failed)
              : message,
        )
        .toList();
    final nextChats = state.chats.map((chat) {
      final lastMessage = chat.lastMessage;
      if (lastMessage?.id != clientId) return chat;
      return chat.copyWith(
        lastMessage: lastMessage!.withLocalStatus(MessageReceiptStatus.failed),
      );
    }).toList();
    _emit(state.copyWith(activeMessages: nextMessages, chats: nextChats));
  }

  void _updateUploadProgress(String clientId, double progress) {
    final nextMessages = state.activeMessages
        .map(
          (message) => message.id == clientId
              ? message.withUploadProgress(progress)
              : message,
        )
        .toList();
    final nextChats = state.chats.map((chat) {
      final lastMessage = chat.lastMessage;
      if (lastMessage?.id != clientId) return chat;
      return chat.copyWith(
        lastMessage: lastMessage!.withUploadProgress(progress),
      );
    }).toList();
    _emit(state.copyWith(activeMessages: nextMessages, chats: nextChats));
  }

  void _applyDeletedMessage(ChatMessage message) {
    var nextMessages = state.activeMessages;
    if (state.activeChat?.id == message.chatId) {
      nextMessages = [
        ...state.activeMessages.where((item) => item.id != message.id),
        message,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final nextChats = List<ChatSummary>.of(state.chats);
    final chatIndex = nextChats.indexWhere((chat) => chat.id == message.chatId);
    if (chatIndex != -1 && nextChats[chatIndex].lastMessage?.id == message.id) {
      nextChats[chatIndex] = nextChats[chatIndex].copyWith(lastMessage: message);
    }
    _emit(state.copyWith(activeMessages: nextMessages, chats: nextChats));
  }

  void _applyMessageReceipts(
    List<String> messageIds,
    String userId,
    MessageReceiptStatus status,
  ) {
    if (messageIds.isEmpty) return;
    final ids = messageIds.toSet();
    final nextMessages = state.activeMessages
        .map(
          (message) => ids.contains(message.id)
              ? message.withReceiptStatus(userId, status)
              : message,
        )
        .toList();
    final nextChats = state.chats.map((chat) {
      final message = chat.lastMessage;
      if (message == null || !ids.contains(message.id)) return chat;
      return chat.copyWith(
        lastMessage: message.withReceiptStatus(userId, status),
      );
    }).toList();
    var nextActiveChat = state.activeChat;
    final activeLastMessage = nextActiveChat?.lastMessage;
    if (activeLastMessage != null && ids.contains(activeLastMessage.id)) {
      nextActiveChat = nextActiveChat?.copyWith(
        lastMessage: activeLastMessage.withReceiptStatus(userId, status),
      );
    }
    _emit(
      state.copyWith(
        activeMessages: nextMessages,
        chats: nextChats,
        activeChat: nextActiveChat,
      ),
    );
  }

  AppState _setUnreadCountOn(AppState source, String chatId, int count) {
    final nextChats = source.chats
        .map((chat) =>
            chat.id == chatId ? chat.copyWith(unreadCount: count) : chat)
        .toList();
    var nextActiveChat = source.activeChat;
    if (nextActiveChat?.id == chatId) {
      nextActiveChat = nextActiveChat?.copyWith(unreadCount: count);
    }
    return source.copyWith(chats: nextChats, activeChat: nextActiveChat);
  }

  List<ChatSummary> _sortedChats(List<ChatSummary> chats) {
    return List<ChatSummary>.of(chats)
      ..sort((a, b) {
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
    _emit(state.copyWith(loading: true, error: null));
    try {
      await action();
    } catch (e) {
      _emit(state.copyWith(error: e.toString()));
    } finally {
      _emit(state.copyWith(loading: false));
    }
  }

  void _emit(AppState nextState) {
    if (!isClosed) emit(nextState);
  }

  @override
  Future<void> close() async {
    socketService.disconnect();
    await callService.dispose();
    return super.close();
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
