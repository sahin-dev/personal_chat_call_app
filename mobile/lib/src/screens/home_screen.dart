import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'user_search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: UserAvatar(
            user: state.currentUser,
            online: state.socketService.isConnected,
            radius: 18,
          ),
        ),
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Search users',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSearchScreen()),
            ),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Refresh chats',
            onPressed: state.refreshChats,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'logout') state.logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Logout'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: state.refreshChats,
        child: state.chats.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                  const _EmptyChats(),
                ],
              )
            : _AnimatedChatList(
                chats: state.chats,
                itemBuilder: (chat) {
                  final other = _otherParticipant(state, chat);
                  return _ChatListItem(
                    key: ValueKey(chat.id),
                    chat: chat,
                    other: other,
                    online: state.isUserOnline(other?.id),
                    onTap: () => _openChat(context, state, chat),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New conversation',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UserSearchScreen()),
        ),
        child: const Icon(Icons.edit_square),
      ),
    );
  }

  AppUser? _otherParticipant(AppState state, ChatSummary chat) {
    for (final user in chat.participants) {
      if (user.id != state.currentUser?.id) return user;
    }
    return null;
  }

  Future<void> _openChat(
    BuildContext context,
    AppState state,
    ChatSummary chat,
  ) async {
    await state.openChat(chat);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }
}

class _AnimatedChatList extends StatefulWidget {
  const _AnimatedChatList({required this.chats, required this.itemBuilder});

  final List<ChatSummary> chats;
  final Widget Function(ChatSummary chat) itemBuilder;

  @override
  State<_AnimatedChatList> createState() => _AnimatedChatListState();
}

class _AnimatedChatListState extends State<_AnimatedChatList> {
  final _listKey = GlobalKey<AnimatedListState>();
  late List<ChatSummary> _items;
  List<ChatSummary>? _pendingItems;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.chats);
  }

  @override
  void didUpdateWidget(covariant _AnimatedChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pendingItems = List.of(widget.chats);
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      final next = _pendingItems;
      _pendingItems = null;
      if (mounted && next != null) _sync(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      padding: const EdgeInsets.symmetric(vertical: 8),
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) => _transition(
        _items[index],
        animation,
      ),
    );
  }

  void _sync(List<ChatSummary> next) {
    final list = _listKey.currentState;
    if (list == null) {
      setState(() => _items = next);
      return;
    }

    final nextIds = next.map((chat) => chat.id).toSet();
    for (var index = _items.length - 1; index >= 0; index--) {
      if (nextIds.contains(_items[index].id)) continue;
      final removed = _items.removeAt(index);
      list.removeItem(
        index,
        (context, animation) => _transition(removed, animation),
        duration: const Duration(milliseconds: 220),
      );
    }

    for (var targetIndex = 0; targetIndex < next.length; targetIndex++) {
      final target = next[targetIndex];
      final currentIndex = _items.indexWhere((item) => item.id == target.id);
      if (currentIndex == -1) {
        _items.insert(targetIndex, target);
        list.insertItem(
          targetIndex,
          duration: const Duration(milliseconds: 420),
        );
      } else if (currentIndex != targetIndex) {
        final removed = _items.removeAt(currentIndex);
        list.removeItem(
          currentIndex,
          (context, animation) => _transition(removed, animation),
          duration: const Duration(milliseconds: 220),
        );
        _items.insert(targetIndex, target);
        list.insertItem(
          targetIndex,
          duration: const Duration(milliseconds: 420),
        );
      } else {
        _items[targetIndex] = target;
      }
    }

    setState(() {});
  }

  Widget _transition(ChatSummary chat, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return SizeTransition(
      sizeFactor: curved,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: widget.itemBuilder(chat),
        ),
      ),
    );
  }
}

class _ChatListItem extends StatelessWidget {
  const _ChatListItem({
    super.key,
    required this.chat,
    required this.other,
    required this.online,
    required this.onTap,
  });

  final ChatSummary chat;
  final AppUser? other;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = chat.unreadCount > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: unread
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(90)
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            width: 3,
            color: unread
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
      ),
      child: ListTile(
        minVerticalPadding: 12,
        leading: UserAvatar(user: other, online: online),
        title: Text(
          other?.name ?? 'Unknown user',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                online ? 'Online' : 'Offline',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: online
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(width: 8),
              Text(
                '\u2022',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _messagePreview(chat.lastMessage),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: SizedBox(
          width: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatMessageTime(chat.lastMessage?.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: unread
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                    ),
              ),
              if (unread) ...[
                const SizedBox(height: 6),
                _UnreadBadge(count: chat.unreadCount),
              ],
            ],
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: Theme.of(context).colorScheme.primary,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No conversations',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Start a conversation using the compose button.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

String _messagePreview(ChatMessage? message) {
  if (message == null) return 'No messages yet';
  if (message.isDeleted) return 'Message deleted';
  if (message.type == MessageKind.file) {
    final caption = message.text?.trim();
    return caption?.isNotEmpty == true
        ? caption!
        : message.file?.originalName ?? 'File';
  }
  return message.text ?? '';
}

String _formatMessageTime(DateTime? dateTime) {
  if (dateTime == null) return '';
  final local = dateTime.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
  }
  if (local.year == now.year) return '${local.day}/${local.month}';
  return '${local.day}/${local.month}/${local.year}';
}
