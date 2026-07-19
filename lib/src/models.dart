enum MessageKind { text, file }

enum MessageReceiptStatus { sending, sent, delivered, seen, failed }

class MessageReceipt {
  const MessageReceipt({required this.userId, required this.status});

  final String userId;
  final MessageReceiptStatus status;

  factory MessageReceipt.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String? ?? 'SENT';
    return MessageReceipt(
      userId: json['userId'] as String,
      status: switch (rawStatus) {
        'READ' => MessageReceiptStatus.seen,
        'DELIVERED' => MessageReceiptStatus.delivered,
        _ => MessageReceiptStatus.sent,
      },
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String email;
  final String? avatarUrl;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class SharedFile {
  const SharedFile({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.size,
    required this.url,
    this.localPath,
  });

  final String id;
  final String originalName;
  final String mimeType;
  final int size;
  final String url;
  final String? localPath;

  factory SharedFile.fromJson(Map<String, dynamic> json) {
    return SharedFile(
      id: json['id'] as String,
      originalName: json['originalName'] as String,
      mimeType: json['mimeType'] as String,
      size: json['size'] as int,
      url: json['url'] as String,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.text,
    this.file,
    this.deletedAt,
    this.receipts = const [],
    this.localStatus,
    this.uploadProgress,
  });

  final String id;
  final String chatId;
  final String senderId;
  final MessageKind type;
  final DateTime createdAt;
  final String? text;
  final SharedFile? file;
  final DateTime? deletedAt;
  final List<MessageReceipt> receipts;
  final MessageReceiptStatus? localStatus;
  final double? uploadProgress;

  bool get isDeleted => deletedAt != null;

  MessageReceiptStatus get recipientStatus {
    if (localStatus != null) return localStatus!;
    final recipientReceipts = receipts.where(
      (receipt) => receipt.userId != senderId,
    );
    if (recipientReceipts.any(
      (receipt) => receipt.status == MessageReceiptStatus.seen,
    )) {
      return MessageReceiptStatus.seen;
    }
    if (recipientReceipts.any(
      (receipt) => receipt.status == MessageReceiptStatus.delivered,
    )) {
      return MessageReceiptStatus.delivered;
    }
    return MessageReceiptStatus.sent;
  }

  ChatMessage withReceiptStatus(
    String userId,
    MessageReceiptStatus status,
  ) {
    final current = receipts
        .where((receipt) => receipt.userId == userId)
        .map((receipt) => receipt.status)
        .firstOrNull;
    if (current != null && current.index >= status.index) return this;
    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: senderId,
      type: type,
      createdAt: createdAt,
      text: text,
      file: file,
      deletedAt: deletedAt,
      receipts: [
        ...receipts.where((receipt) => receipt.userId != userId),
        MessageReceipt(userId: userId, status: status),
      ],
      localStatus: localStatus,
      uploadProgress: uploadProgress,
    );
  }

  ChatMessage withLocalStatus(MessageReceiptStatus status) {
    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: senderId,
      type: type,
      createdAt: createdAt,
      text: text,
      file: file,
      deletedAt: deletedAt,
      receipts: receipts,
      localStatus: status,
      uploadProgress: uploadProgress,
    );
  }

  ChatMessage withUploadProgress(double progress) {
    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: senderId,
      type: type,
      createdAt: createdAt,
      text: text,
      file: file,
      deletedAt: deletedAt,
      receipts: receipts,
      localStatus: localStatus,
      uploadProgress: progress.clamp(0, 1).toDouble(),
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      chatId: json['chatId'] as String,
      senderId: json['senderId'] as String,
      type: (json['type'] as String) == 'FILE'
          ? MessageKind.file
          : MessageKind.text,
      text: json['text'] as String?,
      file: json['file'] == null
          ? null
          : SharedFile.fromJson(json['file'] as Map<String, dynamic>),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      receipts: (json['receipts'] as List<dynamic>? ?? const [])
          .map(
            (item) => MessageReceipt.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.participants,
    this.unreadCount = 0,
    this.lastMessage,
  });

  final String id;
  final List<AppUser> participants;
  final int unreadCount;
  final ChatMessage? lastMessage;

  ChatSummary copyWith({
    ChatMessage? lastMessage,
    int? unreadCount,
  }) {
    return ChatSummary(
      id: id,
      participants: participants,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      id: json['id'] as String,
      participants: (json['participants'] as List<dynamic>)
          .map((item) => AppUser.fromJson(item as Map<String, dynamic>))
          .toList(),
      unreadCount: json['unreadCount'] as int? ?? 0,
      lastMessage: json['lastMessage'] == null
          ? null
          : ChatMessage.fromJson(json['lastMessage'] as Map<String, dynamic>),
    );
  }
}

class AuthSession {
  const AuthSession({required this.user, required this.accessToken});

  final AppUser user;
  final String accessToken;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['accessToken'] as String,
    );
  }
}
